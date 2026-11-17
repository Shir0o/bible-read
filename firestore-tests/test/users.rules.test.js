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

// Every collection gated by `read, write: if auth.uid == userId`.
describe('owner-only user collections', () => {
  const ownerOnlyDocs = [
    'nudges/bob',
    'notificationPrefs/likes',
    'settings/theme',
    'plan_progress/plan-1',
    'bible_books/Genesis',
    'read_throughs/rt-1',
    'read_through_state/old-testament',
    'summary/overall',
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
// owner, whose client no longer writes here either. ADR-0012 Friendships live
// at `friendships`, a fresh name, so a leftover pre-#833 `friends` doc can
// never resurrect; see friends.rules.test.js.
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
