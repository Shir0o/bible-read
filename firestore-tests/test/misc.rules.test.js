'use strict';

const {
  asAdmin,
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

describe('seasons (server-managed)', () => {
  before(async () => {
    await seed('seasons/summer', { name: 'Summer' });
    await seed('seasons/summer/challenges/ch1', { title: 'Read Genesis' });
  });

  it('lets signed-in users read seasons and challenges', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc('seasons/summer').get());
    await assertSucceeds(alice.doc('seasons/summer/challenges/ch1').get());
  });

  it('denies all writes, even by signed-in users', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.doc('seasons/summer').set({ name: 'hacked' }));
    await assertFails(alice.doc('seasons/summer/challenges/ch1').set({ title: 'hacked' }));
  });

  it('denies reads to unauthenticated clients', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc('seasons/summer').get());
  });
});

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

describe('feedback: bugReports and featureRequests', () => {
  const now = new Date();
  const validBugReport = {
    uid: 'alice',
    email: 'alice@example.com',
    displayName: 'Alice',
    title: 'Crash on load',
    description: 'The app crashes after sign in.',
    reproductionSteps: 'Open the app and sign in.',
    platform: 'android',
    timestamp: now,
    status: 'open',
    updatedAt: now,
    resolvedAt: null,
    resolutionNotes: null,
  };

  before(async () => {
    await seed('bugReports/report-1', validBugReport);
    await seed('featureRequests/feature-1', {
      title: 'Add offline mode',
      description: 'Allow reading without connectivity.',
      platform: 'ios',
      timestamp: now,
      status: 'open',
      updatedAt: now,
      resolvedAt: null,
      resolutionNotes: null,
    });
    // isAdmin() also honours a users/{uid} document flag; exercise that branch.
    await seed('users/doc-admin', { admin: true });
  });
  it('lets an authenticated user file a valid bug report', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(bob.doc('bugReports/report-2').set(validBugReport));
  });

  it('denies bug reports missing required fields', async () => {
    const bob = await asUser('bob');
    const { title, ...missingTitle } = validBugReport;
    await assertFails(bob.doc('bugReports/report-3').set(missingTitle));
  });

  it('denies bug reports with fields outside the schema', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob
        .doc('bugReports/report-4')
        .set({ ...validBugReport, uid: 'bob', extra: 'field' }),
    );
  });

  it('denies bug reports whose status is not open', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob.doc('bugReports/report-5').set({ ...validBugReport, uid: 'bob', status: 'closed' }),
    );
  });

  it('denies feedback submission to unauthenticated clients', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc('bugReports/report-6').set(validBugReport));
  });

  it('lets the filer read their own report and denies other users', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    await assertSucceeds(alice.doc('bugReports/report-1').get());
    await assertFails(bob.doc('bugReports/report-1').get());
  });

  it('lets admins read reports claimed by a token', async () => {
    const admin = await asAdmin('moderator');
    await assertSucceeds(admin.doc('bugReports/report-1').get());
    await assertSucceeds(admin.doc('featureRequests/feature-1').get());
  });


  it('lets users flagged admin in their profile document read reports', async () => {
    const docAdmin = await asUser('doc-admin');
    await assertSucceeds(docAdmin.doc('bugReports/report-1').get());
  });
  it('denies users without the admin claim reading others’ reports', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc('featureRequests/feature-1').get());
  });

  it('lets only admins update or delete feedback', async () => {
    const alice = await asUser('alice');
    const admin = await asAdmin('moderator');
    await assertFails(alice.doc('bugReports/report-1').update({ status: 'closed' }));
    await assertSucceeds(admin.doc('bugReports/report-1').update({ status: 'closed' }));
  });

  // Absent properties error in rules evaluation, so every schema key must be
  // present — optional strings pass only as explicit nulls.
  it('denies a feature request with the uid field omitted', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob.doc('featureRequests/feature-3').set({
        title: 'Add offline mode',
        description: 'Allow reading without connectivity.',
        platform: 'ios',
        timestamp: now,
        status: 'open',
        updatedAt: now,
        resolvedAt: null,
        resolutionNotes: null,
      }),
    );
  });

  it('lets an authenticated user file a feature request with a null uid', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.doc('featureRequests/feature-2').set({
        uid: null,
        email: null,
        displayName: null,
        reproductionSteps: null,
        title: 'Add offline mode',
        description: 'Allow reading without connectivity.',
        platform: 'ios',
        timestamp: now,
        status: 'open',
        updatedAt: now,
        resolvedAt: null,
        resolutionNotes: null,
      }),
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
    await seed('groups/g1/joinRequests/carol', { uid: 'carol' });
    await seed('read_logs/cg-day/entries/alice', { uid: 'alice', chapters: 1 });
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

  it('lets a requester query their own join requests', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(
      carol.collectionGroup('joinRequests').where('uid', '==', 'carol').get(),
    );
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
});
