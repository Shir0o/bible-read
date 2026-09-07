'use strict';

const {
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

const CODED = 'g-coded';

async function seedGroupWithCode(groupId, ownerUid, code) {
  await seed(`groups/${groupId}`, { ownerUid, isPublic: true, name: groupId });
  await seed(`groups/${groupId}/members/${ownerUid}`, { uid: ownerUid, role: 'owner' });
  await seed(`groups/${groupId}/members/alice`, { uid: 'alice', role: 'member' });
  await seed(`joinCodes/${code}`, { groupId });
}

describe('joinCodes/{code}', () => {
  before(async () => {
    await seedGroupWithCode(CODED, 'owner', 'ABC234');
  });

  it('lets any signed-in user resolve a code for redemption', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc('joinCodes/ABC234').get());
  });

  it('denies code reads to unauthenticated clients', async () => {
    const anon = await asUnauthenticated();
    await assertFails(anon.doc('joinCodes/ABC234').get());
  });

  it('denies listing codes, even to a member', async () => {
    const owner = await asUser('owner');
    await assertFails(owner.collection('joinCodes').get());
  });

  it('lets a member mint a code for a group they belong to', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.doc('joinCodes/DEF567').set({ groupId: CODED }),
    );
  });

  it('denies minting a code naming a group the caller is not in', async () => {
    const carol = await asUser('carol');
    await assertFails(carol.doc('joinCodes/GHI89X').set({ groupId: CODED }));
  });

  it('rejects lookup documents that carry more than the group id', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc('joinCodes/JKL12X').set({ groupId: CODED, extra: true }),
    );
  });

  it('lets a member retire their group code when regenerating', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc('joinCodes/ABC234').delete());
    // Restore for the later describes.
    await seed(`joinCodes/ABC234`, { groupId: CODED });
  });

  it('denies deleting a code pointing at a group the caller is not in', async () => {
    const carol = await asUser('carol');
    await assertFails(carol.doc('joinCodes/ABC234').delete());
  });

  it('denies updating a code document outright', async () => {
    const owner = await asUser('owner');
    await assertFails(
      owner.doc('joinCodes/ABC234').update({ groupId: 'other-group' }),
    );
  });
});

describe('groups/{groupId}.joinCode updates', () => {
  before(async () => {
    await seedGroupWithCode(CODED, 'owner', 'ABC234');
    // A committed lookup for the code a member will legitimately set.
    await seed('joinCodes/MNO345', { groupId: CODED });
  });

  it('lets a plain member change only the joinCode field', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(alice.doc(`groups/${CODED}`).update({ joinCode: 'MNO345' }));
  });

  it('denies a plain member changing other fields', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.doc(`groups/${CODED}`).update({ memberCount: 99 }));
  });

  it('denies a plain member sneaking other fields in with the joinCode', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc(`groups/${CODED}`).update({ joinCode: 'PQR678', name: 'Hijacked' }),
    );
  });

  it('denies a member clearing the joinCode', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.doc(`groups/${CODED}`).update({ joinCode: null }));
  });

  it('denies pointing joinCode at a code with no lookup document', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.doc(`groups/${CODED}`).update({ joinCode: 'QRT901' }));
  });

  it('still lets the owner update anything', async () => {
    const owner = await asUser('owner');
    await assertSucceeds(owner.doc(`groups/${CODED}`).update({ name: 'Renamed' }));
  });
});
