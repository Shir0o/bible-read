'use strict';

const {
  asAdmin,
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

describe('custom_plans', () => {
  before(async () => {
    await seed('custom_plans/plan-alice', { userId: 'alice', name: 'Alice plan' });
    await seed('custom_plans/plan-bob', { userId: 'bob', name: 'Bob plan' });
  });

  it('lets a user create a plan naming themselves as owner', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(
      carol.doc('custom_plans/plan-carol').set({ userId: 'carol', name: 'Carol plan' }),
    );
  });

  it('denies creating a plan owned by someone else', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol.doc('custom_plans/plan-spoof').set({ userId: 'alice', name: 'spoof' }),
    );
  });

  // The app's saveCustomPlan writes with an auto-generated document id
  // (collection.add), where `resource` is null on create — the rule must not
  // dereference it. Regression for "new plan is not saving".
  it('lets a user create a plan with an auto-generated id', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(
      carol.collection('custom_plans').add({ userId: 'carol', name: 'Carol plan' }),
    );
  });

  it('lets the owner read their plan and denies other users', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    await assertSucceeds(alice.doc('custom_plans/plan-alice').get());
    await assertFails(bob.doc('custom_plans/plan-alice').get());
  });

  it('denies updates by anyone but the owner', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob.doc('custom_plans/plan-alice').update({ name: 'renamed' }),
    );
  });
});

describe('app_check_errors', () => {
  it('lets authenticated clients write, and denies every read', async () => {
    const alice = await asUser('alice');
    const anon = await asUnauthenticated();
    await assertFails(anon.doc('app_check_errors/e1').set({ error: 'integrity' }));
    await assertSucceeds(alice.doc('app_check_errors/e1').set({ error: 'integrity' }));
    const admin = await asAdmin('moderator');
    await assertFails(admin.doc('app_check_errors/e1').get());
  });
});

describe('collection-group rules', () => {
  before(async () => {
    await seed('groups/g1', { ownerUid: 'owner', isPublic: true });
    await seed('groups/g1/members/alice', { uid: 'alice', role: 'member' });
    await seed('groups/g1/members/bob', { uid: 'bob', role: 'member' });
    await seed('read_logs/cg-day/entries/alice', { uid: 'alice', chapters: 1 });
    await seed('groups/g1/progress/2026-10-14/entries/alice', {
      uid: 'alice', groupId: 'g1', dateId: '2026-10-14', count: 1,
    });
  });

  it('lets a user query their own membership records across groups', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.collectionGroup('members').where('uid', '==', 'alice').get(),
    );
  });

  it('denies a query for membership records of other users', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.collectionGroup('members').where('uid', '==', 'bob').get());
  });

  it('lets a user query their own progress entries across collections', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.collectionGroup('entries').where('uid', '==', 'alice').get(),
    );
  });

  it('denies a query for other users’ progress entries', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.collectionGroup('entries').where('uid', '==', 'alice').get());
  });

  it('lets a group member query a co-member’s entries filtered by groupId', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.collectionGroup('entries')
        .where('groupId', '==', 'g1')
        .where('uid', '==', 'alice')
        .get(),
    );
  });

  it('denies a non-member the same groupId-filtered query', async () => {
    const dave = await asUser('dave');
    await assertFails(
      dave.collectionGroup('entries')
        .where('groupId', '==', 'g1')
        .where('uid', '==', 'alice')
        .get(),
    );
  });
});
