'use strict';

const {
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
  unseed,
} = require('../helpers/env');

// ADR-0012: Friend codes are direct invites, friendships are mutual and
// server-written, and a Friend source is readable only by the author's
// Friends. These tests pin the rules side of those claims.

const CODE = '7QK4M2PX';

async function seedFriendship(viewerUid, authorUid) {
  await seed(`users/${viewerUid}/friends/${authorUid}`, {
    uid: authorUid,
    since: new Date('2026-10-03T00:00:00Z'),
  });
}

async function seedFriendEntry(authorUid, date = '2026-10-18') {
  await seed(`users/${authorUid}/friend_feed/${date}/entries/${authorUid}`, {
    uid: authorUid,
    dateId: date,
    name: 'Mei',
  });
}

describe('friendCodes/{code}', () => {
  before(async () => {
    await seed(`friendCodes/${CODE}`, { ownerUid: 'owner' });
  });

  it('lets any signed-in reader point-read a code for the preview', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc(`friendCodes/${CODE}`).get());
  });

  it('denies reading a code to unauthenticated clients', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc(`friendCodes/${CODE}`).get());
  });

  it('denies listing codes, even to the owner', async () => {
    const owner = await asUser('owner');
    await assertFails(owner.collection('friendCodes').get());
  });

  it('lets a reader create their own lookup', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.doc('friendCodes/ALICE234').set({ ownerUid: 'alice' }),
    );
  });

  it('denies creating a lookup for someone else', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc('friendCodes/OTHER234').set({ ownerUid: 'bob' }),
    );
  });

  it('denies lookup documents that carry more than the owner uid', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice
        .doc('friendCodes/EXTRA234')
        .set({ ownerUid: 'alice', friendUid: 'bob' }),
    );
  });

  it('lets the owner retire their lookup on reset', async () => {
    const owner = await asUser('owner');
    await assertSucceeds(owner.doc(`friendCodes/${CODE}`).delete());
    await seed(`friendCodes/${CODE}`, { ownerUid: 'owner' });
  });

  it('denies deleting someone else’s lookup', async () => {
    const carol = await asUser('carol');
    await assertFails(carol.doc(`friendCodes/${CODE}`).delete());
  });

  it('denies updating a lookup outright', async () => {
    const owner = await asUser('owner');
    await assertFails(
      owner.doc(`friendCodes/${CODE}`).update({ ownerUid: 'carol' }),
    );
  });
});

describe('users/{uid}/friends', () => {
  before(async () => {
    await seedFriendship('alice', 'mei');
  });

  it('lets a reader read their own side', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc('users/alice/friends/mei').get());
  });

  it('denies reading the other reader’s side', async () => {
    const mei = await asUser('mei');
    await assertFails(mei.doc('users/alice/friends/mei').get());
  });

  it('denies listing another reader’s friends', async () => {
    const mei = await asUser('mei');
    await assertFails(mei.collection('users/alice/friends').get());
  });

  it('denies every client write, even to the owner’s side', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc('users/alice/friends/carol').set({ uid: 'carol' }),
    );
    await assertFails(
      alice.doc('users/alice/friends/mei').delete(),
    );
    await assertFails(
      alice.doc('users/alice/friends/mei').update({ since: 'now' }),
    );
  });
});

describe('users/{uid}/friend_feed', () => {
  before(async () => {
    await seedFriendEntry('mei');
    await seedFriendship('alice', 'mei');
  });

  after(async () => {
    await unseed('users/alice/friends/mei');
  });

  it('lets a Friend read the author’s source', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice
        .collection('users/mei/friend_feed/2026-10-18/entries')
        .get(),
    );
  });

  it('denies a non-Friend reading the author’s source', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol
        .collection('users/mei/friend_feed/2026-10-18/entries')
        .get(),
    );
  });

  it('lets the author write their own entry', async () => {
    const mei = await asUser('mei');
    await assertSucceeds(
      mei
        .doc('users/mei/friend_feed/2026-10-18/entries/mei')
        .set({ uid: 'mei', dateId: '2026-10-18' }, { merge: true }),
    );
  });

  it('denies writing an entry on someone else’s source', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice
        .doc('users/mei/friend_feed/2026-10-18/entries/mei')
        .set({ uid: 'mei', dateId: '2026-10-18' }),
    );
  });

  it('lets a Friend write their own Amen', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice
        .doc(
          'users/mei/friend_feed/2026-10-18/entries/mei/likes/alice',
        )
        .set({ timestamp: new Date() }),
    );
  });

  it('lets the author manage their own Amen like any Group copy', async () => {
    const mei = await asUser('mei');
    await assertSucceeds(
      mei
        .doc('users/mei/friend_feed/2026-10-18/entries/mei/likes/mei')
        .set({timestamp: new Date()}),
    );
    await assertSucceeds(
      mei
        .doc('users/mei/friend_feed/2026-10-18/entries/mei/likes/mei')
        .delete(),
    );
  });

  it('denies an Amen from a non-Friend', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol
        .doc(
          'users/mei/friend_feed/2026-10-18/entries/mei/likes/carol',
        )
        .set({ timestamp: new Date() }),
    );
  });

  it('lets a Friend read the Amens', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice
        .collection(
          'users/mei/friend_feed/2026-10-18/entries/mei/likes',
        )
        .get(),
    );
  });

  it('loses access as soon as the friendship is gone', async () => {
    await unseed('users/alice/friends/mei');
    const alice = await asUser('alice');
    await assertFails(
      alice.collection('users/mei/friend_feed/2026-10-18/entries').get(),
    );
    // Leave the friendship in place for the badge-log describe.
    await seedFriendship('alice', 'mei');
  });
});

describe('users/{uid}/friend_badge_log', () => {
  before(async () => {
    await seed('users/mei/friend_badge_log/mei_days_7', {
      uid: 'mei',
      badgeId: 'days_7',
      type: 'consistency',
      dateUnlocked: new Date('2026-10-18T00:00:00Z'),
    });
    await seedFriendship('alice', 'mei');
  });

  it('lets a Friend read the badge log', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.collection('users/mei/friend_badge_log').get(),
    );
  });

  it('denies a non-Friend the badge log', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol.collection('users/mei/friend_badge_log').get(),
    );
  });

  it('denies every client write, including the author’s', async () => {
    const mei = await asUser('mei');
    await assertFails(
      mei
        .doc('users/mei/friend_badge_log/mei_days_30')
        .set({ uid: 'mei', badgeId: 'days_30' }),
    );
  });
});

describe('retired friend-graph paths', () => {
  const retired = [
    'users/alice/friendRequestsSent/bob',
    'users/alice/friendRequestsReceived/bob',
    'users/alice/friendStreakInvites/bob',
    'users/alice/friendStreakLinks/bob',
  ];

  for (const path of retired) {
    it(`stays denied: ${path}`, async () => {
      const alice = await asUser('alice');
      await assertFails(alice.doc(path).get());
      await assertFails(alice.doc(path).set({ uid: 'bob' }));
    });
  }
});
