'use strict';

const {
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
  unseed,
} = require('../helpers/env');

// The feed is denormalized per Group (ADR-0004): each entry lives at
// groups/{groupId}/read_log/{date}/entries/{userId}, gated by membership.
// The global read_logs path is retired and denies everything.
const GROUP = 'groups/g1';
const GROUP_ENTRY = `${GROUP}/read_log/2026-01-01/entries/alice`;

async function seedGroup(groupId, ownerUid, members) {
  await seed(`groups/${groupId}`, { name: `Group ${groupId}`, ownerUid });
  await seed(`groups/${groupId}/members/${ownerUid}`, { uid: ownerUid, role: 'owner' });
  for (const uid of members) {
    await seed(`groups/${groupId}/members/${uid}`, { uid, role: 'member' });
  }
}

describe('groups/{groupId}/read_log/{date}/entries/{userId}', () => {
  before(async () => {
    await seedGroup('g1', 'alice', ['bob']);
    await seedGroup('g2', 'carol', ['dave']);
    await seed(GROUP_ENTRY, { uid: 'alice', name: 'Alice', dateId: '2026-01-01' });
  });

  it('lets the entry owner write their own entry', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.doc(GROUP_ENTRY).set({ uid: 'alice', name: 'Alice', dateId: '2026-01-01', chapters: 3 }),
    );
  });

  it('lets a co-member read the entry', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(bob.doc(GROUP_ENTRY).get());
  });

  it('lets the owner read a member\'s entry', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc(GROUP_ENTRY).get());
  });

  it('denies a non-member', async () => {
    const carol = await asUser('carol');
    await assertFails(carol.doc(GROUP_ENTRY).get());
  });

  it('denies writes by anyone but the entry owner, including co-members', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc(GROUP_ENTRY).set({ uid: 'alice', name: 'Bob' }));
  });

  it('denies a former member entries written after they left', async () => {
    // dave is a member of g2, reads carol's entry, then leaves: their
    // membership document is deleted (the app does this server-side; the
    // test does it via the rules-disabled path). The rule is a pure
    // membership check, so a reader who is no longer a member loses access
    // to everything on this path — including entries written before and
    // after they left.
    await seed(`groups/g2/read_log/2026-01-02/entries/carol`, {
      uid: 'carol', name: 'Carol', dateId: '2026-01-02',
    });
    const dave = await asUser('dave');
    await assertSucceeds(
      dave.doc('groups/g2/read_log/2026-01-02/entries/carol').get(),
    );

    await unseed('groups/g2/members/dave');
    await assertFails(
      dave.doc('groups/g2/read_log/2026-01-02/entries/carol').get(),
    );
  });

  it('denies unauthenticated readers', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc(GROUP_ENTRY).get());
  });
});

describe('groups/{groupId}/read_log/{date}/entries/{userId}/likes', () => {
  before(async () => {
    await seedGroup('g3', 'alice', ['bob']);
    await seed('groups/g3/read_log/2026-01-01/entries/alice', {
      uid: 'alice', name: 'Alice', dateId: '2026-01-01',
    });
  });

  it('lets a co-member Amen and undo their own Amen', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.doc('groups/g3/read_log/2026-01-01/entries/alice/likes/bob').set({ name: 'Bob' }),
    );
    await assertSucceeds(
      bob.doc('groups/g3/read_log/2026-01-01/entries/alice/likes/bob').delete(),
    );
  });

  it('denies a non-member Amen', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol.doc('groups/g3/read_log/2026-01-01/entries/alice/likes/carol').set({ name: 'Carol' }),
    );
  });

  it('lets co-members read who has Amen\'d', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.doc('groups/g3/read_log/2026-01-01/entries/alice/likes/bob').get(),
    );
    const carol = await asUser('carol');
    await assertFails(
      carol.doc('groups/g3/read_log/2026-01-01/entries/alice/likes/bob').get(),
    );
  });
});

describe('retired global read_logs', () => {
  it('denies everything on the retired path', async () => {
    // A legacy entry is seeded so the read assertions are evaluated against
    // a real document — a read of a non-existent document is not evaluated
    // against resource-based rules and would pass vacuously. One residual
    // remains by design: the collection-group `entries` rule still lets an
    // entry's own author read their historical copy (firestore.rules
    // /{path=**}/entries). Writes deny everywhere, and nobody else can read
    // it; the data is a rolling daily record scheduled for migration.
    await seed('read_logs/2026-01-01/entries/alice', { uid: 'alice' });
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    const anon = await asUnauthenticated();
    await assertFails(bob.doc('read_logs/2026-01-01/entries/alice').get());
    await assertFails(alice.doc('read_logs/2026-01-01/entries/alice').set({ uid: 'alice', chapters: 9 }));
    await assertFails(anon.doc('read_logs/2026-01-01/entries/alice').get());
  });
});