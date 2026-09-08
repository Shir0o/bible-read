'use strict';

const {
  asUser,
  assertFails,
  assertSucceeds,
  seed,
  unseed,
} = require('../helpers/env');

// Sharing a Reflection copies the opted-in text onto the author's read-log
// entry (groups/{g}/read_log/{date}/entries/{uid}) — the already
// co-member-readable object from ADR-0004. The private Reflection document
// (users/{uid}/reflections/{date}) stays owner-only, shared or not: the rule
// and its comment are unchanged. #807.

const DATE = '2026-03-01';

async function seedWorld() {
  // g1: alice (owner) + bob. g2: carol only — she shares no Group with alice.
  await seed('groups/g1', { name: 'Morning', ownerUid: 'alice' });
  await seed('groups/g1/members/alice', { uid: 'alice', role: 'owner' });
  await seed('groups/g1/members/bob', { uid: 'bob', role: 'member' });
  await seed('groups/g2', { name: 'Other', ownerUid: 'carol' });
  await seed('groups/g2/members/carol', { uid: 'carol', role: 'owner' });

  // Alice's private reflection for the day, and her read-log entry in g1
  // carrying the shared copy.
  await seed(`users/alice/reflections/${DATE}`, {
    text: 'A private thought for today.',
    updatedAt: new Date('2026-03-01T08:00:00Z'),
    shared: true,
  });
  await seed(`groups/g1/read_log/${DATE}/entries/alice`, {
    uid: 'alice',
    name: 'Alice',
    dateId: DATE,
    timestamp: new Date('2026-03-01T08:00:00Z'),
    sharedReflection: 'A private thought for today.',
  });
}

describe('reflections shared with the circle (#807)', () => {
  beforeEach(seedWorld);

  describe('the private reflection document stays owner-only', () => {
    it('the owner reads their own reflection, shared or not', async () => {
      const alice = await asUser('alice');
      await assertSucceeds(alice.doc(`users/alice/reflections/${DATE}`).get());

      await seed(`users/alice/reflections/2026-03-02`, {
        text: 'Unshared one.',
        updatedAt: new Date('2026-03-02T08:00:00Z'),
      });
      await assertSucceeds(alice.doc('users/alice/reflections/2026-03-02').get());
    });

    it('a co-member who can read the shared copy cannot read the private document', async () => {
      const bob = await asUser('bob');
      await assertFails(bob.doc(`users/alice/reflections/${DATE}`).get());
    });

    it('nobody but the owner can write the private reflection document', async () => {
      const bob = await asUser('bob');
      await assertFails(
        bob.doc(`users/alice/reflections/${DATE}`).set({ text: 'hijacked' }),
      );
    });
  });

  describe('the shared copy on the read-log entry', () => {
    it('a co-member reads the shared text on the entry', async () => {
      const bob = await asUser('bob');
      const snap = await assertSucceeds(
        bob.doc(`groups/g1/read_log/${DATE}/entries/alice`).get(),
      );
      if (snap.data().sharedReflection !== 'A private thought for today.') {
        throw new Error('shared text missing from the entry');
      }
    });

    it('a non-member cannot read the shared text', async () => {
      const carol = await asUser('carol');
      await assertFails(carol.doc(`groups/g1/read_log/${DATE}/entries/alice`).get());
    });

    it('no client — not even the author — writes shared text onto someone else\'s entry', async () => {
      const bob = await asUser('bob');
      await assertFails(
        bob.doc(`groups/g1/read_log/${DATE}/entries/alice`).set({
          sharedReflection: 'words bob never wrote',
        }),
      );
      const alice = await asUser('alice');
      await assertFails(
        alice.doc(`groups/g1/read_log/${DATE}/entries/bob`).set({
          sharedReflection: 'alice writing onto bob\'s entry',
        }),
      );
    });

    it('the entry author removes their own shared copy (unshare deletes, not hides)', async () => {
      const alice = await asUser('alice');
      await assertSucceeds(
        alice.doc(`groups/g1/read_log/${DATE}/entries/alice`).update({
          sharedReflection: null,
        }),
      );
    });
  });

  describe('a former member', () => {
    it('cannot read entries written after they left', async () => {
      // dave joins g1, reads while a member, leaves, then is denied — the
      // membership document is deleted server-side; the test does it via the
      // rules-disabled path.
      await seed('groups/g1/members/dave', { uid: 'dave', role: 'member' });
      const dave = await asUser('dave');
      await assertSucceeds(
        dave.doc(`groups/g1/read_log/${DATE}/entries/alice`).get(),
      );

      await unseed('groups/g1/members/dave');
      await assertFails(
        dave.doc(`groups/g1/read_log/${DATE}/entries/alice`).get(),
      );
    });
  });
});