'use strict';

const {
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

describe('users/{userId} profile', () => {
  before(async () => {
    await seed('users/alice', { displayName: 'Alice' });
    await seed('users/bob', { displayName: 'Bob' });
  });

  it('lets any signed-in user read a profile', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(bob.doc('users/alice').get());
  });

  it('denies profile reads to unauthenticated clients', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc('users/alice').get());
  });

  it('lets the owner write their profile', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc('users/alice').set({ displayName: 'Alice' }));
  });

  it('denies profile writes by other users', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc('users/alice').set({ displayName: 'Hacked' }));
  });
});

describe('users/{userId}/seasonChallenges', () => {
  before(async () => {
    await seed('users/alice/seasonChallenges/summer', {
      progress: true,
      claimed: false,
    });
  });

  it('lets the owner write valid progress flags', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice
        .doc('users/alice/seasonChallenges/summer')
        .set({ progress: true, claimed: false }),
    );
  });

  it('denies invalid progress flag values', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice
        .doc('users/alice/seasonChallenges/summer')
        .set({ progress: 'yes', claimed: false }),
    );
  });

  it('denies writes by other users', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob
        .doc('users/alice/seasonChallenges/summer')
        .set({ progress: true, claimed: false }),
    );
  });

  it('lets only the owner read', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    const anon = await asUnauthenticated();
    await assertSucceeds(alice.doc('users/alice/seasonChallenges/summer').get());
    await assertFails(bob.doc('users/alice/seasonChallenges/summer').get());
    await assertFails(anon.doc('users/alice/seasonChallenges/summer').get());
  });
});

describe('users/{userId}/seasonRewards', () => {
  before(async () => {
    await seed('users/alice/seasonRewards/reward-1', { seasonId: 'summer' });
  });

  it('lets the owner read', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc('users/alice/seasonRewards/reward-1').get());
  });

  it('denies writes even by the owner', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc('users/alice/seasonRewards/reward-2').set({ seasonId: 'summer' }),
    );
  });

  it('denies reads by other users', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc('users/alice/seasonRewards/reward-1').get());
  });
});

// Badges (the reader-facing word; the collection keeps `achievements`).
//
// Writes are server-only: the Admin SDK bypasses these rules, so a passing
// `seed()` below is what "the server path can write" looks like. No client —
// not even the owner — can grant one. Co-members read badges through the
// per-Group mirror in groups.rules.test.js: sharing a group with the owner is
// not expressible as a rule on this personal path (ADR-0004), so the direct
// cross-user read here stays denied by design.
describe('users/{userId}/achievements', () => {
  before(async () => {
    // Server-authored badge — the only way one comes into existence.
    await seed('users/alice/achievements/first_nt', { type: 'read_through' });
    // bob genuinely shares a group with alice; the mirror path in
    // groups.rules.test.js is where his read belongs.
    await seed('groups/g-shared-with-alice', { ownerUid: 'alice', isPublic: false });
    await seed('groups/g-shared-with-alice/members/alice', { uid: 'alice', role: 'owner' });
    await seed('groups/g-shared-with-alice/members/bob', { uid: 'bob', role: 'member' });
  });

  it('lets the owner read their own badges', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc('users/alice/achievements/first_nt').get());
  });

  it('denies the owner writing a badge for themselves', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc('users/alice/achievements/self_granted').set({ type: 'read_through' }),
    );
  });

  it('denies the owner updating or deleting a badge', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc('users/alice/achievements/first_nt').update({ type: 'forged' }),
    );
    await assertFails(alice.doc('users/alice/achievements/first_nt').delete());
  });

  it('denies direct badge reads to co-members and strangers alike', async () => {
    const bob = await asUser('bob');
    const carol = await asUser('carol');
    await assertFails(bob.doc('users/alice/achievements/first_nt').get());
    await assertFails(carol.doc('users/alice/achievements/first_nt').get());
  });

  it('denies badge writes by other signed-in users', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob.doc('users/alice/achievements/first_nt').set({ type: 'read_through' }),
    );
  });

  it('denies unauthenticated reads', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc('users/alice/achievements/first_nt').get());
  });
});

// Every collection gated by `read, write: if auth.uid == userId`.
describe('owner-only user collections', () => {
  const ownerOnlyDocs = [
    'nudges/bob',
    'notificationPrefs/likes',
    'settings/theme',
    'plan_progress/plan-1',
    'plan_pace/group-1',
    'bible_books/Genesis',
    'read_throughs/rt-1',
    'read_through_state/old-testament',
    'reflections/2026-01-01',
    'summary/overall',
    'cache/badges',
  ];

  before(async () => {
    for (const doc of ownerOnlyDocs) {
      await seed(`users/alice/${doc}`, { value: 1 });
    }
  });

  for (const doc of ownerOnlyDocs) {
    it(`lets the owner read and write users/alice/${doc}`, async () => {
      const alice = await asUser('alice');
      await assertSucceeds(alice.doc(`users/alice/${doc}`).get());
      await assertSucceeds(alice.doc(`users/alice/${doc}`).set({ value: 2 }));
    });

    it(`denies other users on users/alice/${doc}`, async () => {
      const bob = await asUser('bob');
      const anon = await asUnauthenticated();
      await assertFails(bob.doc(`users/alice/${doc}`).get());
      await assertFails(bob.doc(`users/alice/${doc}`).set({ value: 3 }));
      await assertFails(anon.doc(`users/alice/${doc}`).get());
    });
  }
});

// The friend graph is retired (ADR-0003): no rules block exists for these
// collections any more, so every path is denied outright — including to the
// owner, whose client no longer writes here either.
describe('retired friend collections', () => {
  const retiredDocs = [
    'friends/bob',
    'friendRequestsSent/bob',
    'friendRequestsReceived/bob',
    'friendStreakInvites/bob',
    'friendStreakLinks/bob',
  ];

  for (const doc of retiredDocs) {
    it(`denies everyone on users/alice/${doc}`, async () => {
      const alice = await asUser('alice');
      const bob = await asUser('bob');
      const anon = await asUnauthenticated();
      await assertFails(alice.doc(`users/alice/${doc}`).get());
      await assertFails(alice.doc(`users/alice/${doc}`).set({ value: 1 }));
      await assertFails(bob.doc(`users/alice/${doc}`).get());
      await assertFails(bob.doc(`users/alice/${doc}`).set({ value: 1 }));
      await assertFails(anon.doc(`users/alice/${doc}`).get());
    });
  }
});

describe('users/{userId}/reading likes', () => {
  before(async () => {
    await seed('users/alice/reading/2026-01-01', { chapters: 3 });
    await seed('users/alice/reading/2026-01-01/likes/bob', { liked: true });
  });

  it('lets only the owner write the reading entry', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    await assertSucceeds(
      alice.doc('users/alice/reading/2026-01-02').set({ chapters: 2 }),
    );
    await assertFails(bob.doc('users/alice/reading/2026-01-02').set({ chapters: 2 }));
  });

  it('lets the liker manage only their own like', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.doc('users/alice/reading/2026-01-01/likes/bob').set({ liked: true }),
    );
    await assertFails(
      bob.doc('users/alice/reading/2026-01-01/likes/carol').set({ liked: true }),
    );
  });

  it('lets only the entry owner or the liker read a like', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    const carol = await asUser('carol');
    await assertSucceeds(alice.doc('users/alice/reading/2026-01-01/likes/bob').get());
    await assertSucceeds(bob.doc('users/alice/reading/2026-01-01/likes/bob').get());
    await assertFails(carol.doc('users/alice/reading/2026-01-01/likes/bob').get());
  });
});

describe('users/{userId}/notifications', () => {
  before(async () => {
    await seed('users/alice/notifications/note-1', {
      senderUid: 'bob',
      body: 'hello',
    });
  });

  it('lets only the owner read their notifications', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    await assertSucceeds(alice.doc('users/alice/notifications/note-1').get());
    await assertFails(bob.doc('users/alice/notifications/note-1').get());
  });

  it('lets a client create a notification that names itself as sender', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.doc('users/alice/notifications/note-2').set({ senderUid: 'bob', body: 'hi' }),
    );
  });

  it('denies creating a notification that claims another sender', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob
        .doc('users/alice/notifications/note-3')
        .set({ senderUid: 'carol', body: 'hi' }),
    );
  });

  it('lets only the owner update or delete', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    await assertSucceeds(
      alice.doc('users/alice/notifications/note-1').update({ read: true }),
    );
    await assertFails(
      bob.doc('users/alice/notifications/note-1').update({ read: true }),
    );
    await assertSucceeds(alice.doc('users/alice/notifications/note-1').delete());
  });
});
