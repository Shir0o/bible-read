'use strict';

const {
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

// Regression: released clients up to 1.42.4 mark a reading with ONE atomic
// batch containing the per-Group feed entry AND the reader's Friend-visible
// copy at users/{uid}/friend_feed/{date}/entries/{uid}
// (ReadLogService.mark). If either write is denied the whole batch is
// rejected and "Failed to mark reading" surfaces. The friend copy is
// dead code on main but still written by every installed build, so the
// rule must stay until those builds age out.
const DATE = '2026-01-01';
const UID = 'alice';
const GROUP_ENTRY = `groups/g1/read_log/${DATE}/entries/${UID}`;
const FRIEND_ENTRY = `users/${UID}/friend_feed/${DATE}/entries/${UID}`;

const entry = {
  uid: UID,
  name: 'Alice',
  email: 'alice@example.com',
  dateId: DATE,
  reading: 'Genesis 1',
};

describe('mark-reading batch from shipped clients (<= 1.42.4)', () => {
  before(async () => {
    await seed('groups/g1', { name: 'Group g1', ownerUid: UID });
    await seed(`groups/g1/members/${UID}`, { uid: UID, role: 'owner' });
  });

  it('commits the group entry and the friend copy together', async () => {
    const alice = await asUser(UID);
    const batch = alice.batch();
    batch.set(alice.doc(GROUP_ENTRY), entry, { merge: true });
    batch.set(alice.doc(FRIEND_ENTRY), entry, { merge: true });
    await assertSucceeds(batch.commit());
  });

  it('commits the unmark batch (both deletes) together', async () => {
    const alice = await asUser(UID);
    const batch = alice.batch();
    batch.delete(alice.doc(GROUP_ENTRY));
    batch.delete(alice.doc(FRIEND_ENTRY));
    await assertSucceeds(batch.commit());
  });

  it('still denies another reader writing the friend copy', async () => {
    const bob = await asUser('bob');
    await assertFails(
      bob.doc(FRIEND_ENTRY).set({ uid: UID, dateId: DATE }),
    );
  });
});
