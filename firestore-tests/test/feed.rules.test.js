'use strict';

const {
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

const ENTRY = 'read_logs/2026-01-01/entries/alice';

describe('read_logs/{date}/entries/{userId}', () => {
  before(async () => {
    await seed(ENTRY, { chapters: 3, completed: true });
  });

  it('lets the entry owner write and other signed-in users read', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    await assertSucceeds(alice.doc(ENTRY).set({ chapters: 4, completed: true }));
    await assertSucceeds(bob.doc(ENTRY).get());
  });

  it('denies writes by other users', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc(ENTRY).set({ chapters: 9, completed: true }));
  });

  it('denies reads to unauthenticated clients', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc(ENTRY).get());
  });
});

describe('read_logs/{date}/entries/{userId}/likes', () => {
  before(async () => {
    await seed(`${ENTRY}/likes/bob`, { liked: true });
  });

  it('lets the liker manage only their own like', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(bob.doc(`${ENTRY}/likes/bob`).set({ liked: true }));
    await assertFails(bob.doc(`${ENTRY}/likes/carol`).set({ liked: true }));
  });

  it('lets any signed-in user read likes', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc(`${ENTRY}/likes/bob`).get());
  });

  it('denies unauthenticated likes access', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc(`${ENTRY}/likes/bob`).get());
  });
});

describe('read_logs/{date}/entries/{userId}/comments', () => {
  before(async () => {
    await seed(`${ENTRY}/comments/c1`, { uid: 'bob', text: 'great' });
  });

  it('lets the author create a comment naming themselves', async () => {
    const bob = await asUser('bob');
    await assertSucceeds(
      bob.doc(`${ENTRY}/comments/c2`).set({ uid: 'bob', text: ' amen' }),
    );
  });

  it('denies creating a comment that claims another author', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc(`${ENTRY}/comments/c3`).set({ uid: 'carol', text: 'hi' }));
  });

  it('denies comment updates outright', async () => {
    const bob = await asUser('bob');
    await assertFails(bob.doc(`${ENTRY}/comments/c1`).update({ text: 'edited' }));
  });

  it('lets the author or the entry owner delete, and denies others', async () => {
    const alice = await asUser('alice');
    const bob = await asUser('bob');
    const carol = await asUser('carol');
    await assertFails(carol.doc(`${ENTRY}/comments/c1`).delete());
    await assertSucceeds(bob.doc(`${ENTRY}/comments/c1`).delete());
    await assertSucceeds(alice.doc(`${ENTRY}/comments/c2`).delete());
  });

  it('lets any signed-in user read comments', async () => {
    await seed(`${ENTRY}/comments/c-kept`, { uid: 'bob', text: 'kept' });
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc(`${ENTRY}/comments/c-kept`).get());
  });
});
