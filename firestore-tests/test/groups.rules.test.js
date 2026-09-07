'use strict';

const {
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  seed,
} = require('../helpers/env');

const PRIVATE_GROUP = 'g-private';
const PUBLIC_GROUP = 'g-public';
const JOIN_GROUP = 'g-join';

async function seedGroup(groupId, ownerUid, isPublic) {
  await seed(`groups/${groupId}`, { ownerUid, isPublic, name: groupId });
  await seed(`groups/${groupId}/members/${ownerUid}`, { uid: ownerUid, role: 'owner' });
}

describe('groups/{groupId} document', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seedGroup(PUBLIC_GROUP, 'owner', true);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
    await seed(`groups/${PRIVATE_GROUP}/members/admin-user`, { uid: 'admin-user', role: 'admin' });
  });

  it('lets any signed-in user read a group', async () => {
    const anon = await asUnauthenticated();
    const bob = await asUser('bob');
    await assertFails(anon.doc(`groups/${PRIVATE_GROUP}`).get());
    await assertSucceeds(bob.doc(`groups/${PRIVATE_GROUP}`).get());
  });

  it('lets any signed-in user create a group', async () => {
    const dave = await asUser('dave');
    await assertSucceeds(
      dave.doc('groups/g-dave').set({ ownerUid: 'dave', isPublic: false }),
    );
  });

  it('lets the owner update, and denies other members', async () => {
    const owner = await asUser('owner');
    const alice = await asUser('alice');
    await assertSucceeds(
      owner.doc(`groups/${PRIVATE_GROUP}`).update({ name: 'renamed' }),
    );
    await assertFails(
      alice.doc(`groups/${PRIVATE_GROUP}`).update({ name: 'renamed' }),
    );
  });

  it('lets admins update, but not plain members', async () => {
    const admin = await asUser('admin-user');
    const alice = await asUser('alice');
    await assertSucceeds(
      admin.doc(`groups/${PRIVATE_GROUP}`).update({ name: 'admin-renamed' }),
    );
    await assertFails(alice.doc(`groups/${PRIVATE_GROUP}`).update({ name: 'nope' }));
  });

  it('denies deletes by users who are not owner or admin', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.doc(`groups/${PRIVATE_GROUP}`).delete());
  });
});

describe('groups/{groupId}/members', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seedGroup(PUBLIC_GROUP, 'owner', true);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
    await seed(`groups/${PRIVATE_GROUP}/members/admin-user`, {
      uid: 'admin-user',
      role: 'admin',
    });
    // isOwner() resolves through the group document, so it must exist.
    await seed('groups/g-dave', { ownerUid: 'dave', isPublic: false });
    // Dedicated group for tests that mint memberships, so carol never becomes
    // a member of the group other describes rely on treating her as an outsider.
    await seedGroup(JOIN_GROUP, 'owner', false);
    await seed(`groups/${JOIN_GROUP}/members/admin-user`, {
      uid: 'admin-user',
      role: 'admin',
    });
  });

  it('lets any signed-in user read members', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc(`groups/${PRIVATE_GROUP}/members/alice`).get());
  });

  it('lets the owner create their own member record', async () => {
    const dave = await asUser('dave');
    await assertSucceeds(
      dave.doc('groups/g-dave/members/dave').set({ uid: 'dave', role: 'owner' }),
    );
  });

  it('lets a user join a public group', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice.doc(`groups/${PUBLIC_GROUP}/members/alice`).set({ uid: 'alice', role: 'member' }),
    );
  });

  it('denies joining a private group without an invitation', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol.doc(`groups/${PRIVATE_GROUP}/members/carol`).set({ uid: 'carol', role: 'member' }),
    );
  });

  it('lets a user join a private group holding an invitation', async () => {
    const carol = await asUser('carol');
    await seed(`groups/${JOIN_GROUP}/invites/carol`, { invitedBy: 'owner' });
    await assertSucceeds(
      carol.doc(`groups/${JOIN_GROUP}/members/carol`).set({ uid: 'carol', role: 'member' }),
    );
  });

  it('denies approving a join request without removing it', async () => {
    const admin = await asUser('admin-user');
    await seed(`groups/${JOIN_GROUP}/joinRequests/dave`, { uid: 'dave' });
    await assertFails(
      admin.doc(`groups/${JOIN_GROUP}/members/dave`).set({ uid: 'dave', role: 'member' }),
    );
  });

  it('lets an admin approve a join request in the same write as its removal', async () => {
    const admin = await asUser('admin-user');
    await seed(`groups/${JOIN_GROUP}/joinRequests/carol`, { uid: 'carol' });

    const batch = admin.batch();
    batch.set(admin.doc(`groups/${JOIN_GROUP}/members/carol`), {
      uid: 'carol',
      role: 'member',
    });
    batch.delete(admin.doc(`groups/${JOIN_GROUP}/joinRequests/carol`));
    await assertSucceeds(batch.commit());
  });

  it('denies a member promoting themselves', async () => {
    const alice = await asUser('alice');
    await assertFails(
      alice.doc(`groups/${PRIVATE_GROUP}/members/alice`).set({ uid: 'alice', role: 'admin' }),
    );
  });

  it('denies member deletes by non-admins', async () => {
    const alice = await asUser('alice');
    await assertFails(alice.doc(`groups/${PRIVATE_GROUP}/members/admin-user`).delete());
  });
});

describe('groups/{groupId}/invites', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
  });

  it('lets owners and admins send invites, and denies members', async () => {
    const owner = await asUser('owner');
    const alice = await asUser('alice');
    await assertSucceeds(
      owner.doc(`groups/${PRIVATE_GROUP}/invites/carol`).set({ invitedBy: 'owner' }),
    );
    await assertFails(
      alice.doc(`groups/${PRIVATE_GROUP}/invites/dave`).set({ invitedBy: 'alice' }),
    );
  });

  it('lets the recipient read and delete their own invite', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc(`groups/${PRIVATE_GROUP}/invites/carol`).get());
    await assertSucceeds(carol.doc(`groups/${PRIVATE_GROUP}/invites/carol`).delete());
  });

  it('denies reading invites to unrelated members', async () => {
    const alice = await asUser('alice');
    await seed(`groups/${PRIVATE_GROUP}/invites/dave`, { invitedBy: 'owner' });
    await assertFails(alice.doc(`groups/${PRIVATE_GROUP}/invites/dave`).get());
  });
});

describe('groups/{groupId}/schedule', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
    await seed(`groups/${PRIVATE_GROUP}/schedule/2026-01-01`, { chapters: [] });
  });

  it('lets any signed-in user read the schedule', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(carol.doc(`groups/${PRIVATE_GROUP}/schedule/2026-01-01`).get());
  });

  it('lets only owners and admins write the schedule', async () => {
    const owner = await asUser('owner');
    const alice = await asUser('alice');
    await assertSucceeds(
      owner.doc(`groups/${PRIVATE_GROUP}/schedule/2026-01-01`).set({ chapters: [1] }),
    );
    await assertFails(
      alice.doc(`groups/${PRIVATE_GROUP}/schedule/2026-01-01`).set({ chapters: [2] }),
    );
  });
});

describe('groups/{groupId}/progress', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
    await seed(`groups/${PRIVATE_GROUP}/members/admin-user`, {
      uid: 'admin-user',
      role: 'admin',
    });
  });

  it('lets a member write only their own entry', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice
        .doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/alice`)
        .set({ uid: 'alice', done: true }),
    );
    await assertFails(
      alice
        .doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/admin-user`)
        .set({ uid: 'admin-user', done: true }),
    );
  });

  it('denies writes by non-members', async () => {
    const carol = await asUser('carol');
    await assertFails(
      carol
        .doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/carol`)
        .set({ uid: 'carol', done: true }),
    );
  });

  it('lets members read entries and denies non-members', async () => {
    const alice = await asUser('alice');
    const carol = await asUser('carol');
    await assertSucceeds(
      alice.doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/alice`).get(),
    );
    await assertFails(
      carol.doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/alice`).get(),
    );
  });

  it('lets users delete their own entries and admins any entry', async () => {
    const admin = await asUser('admin-user');
    const carol = await asUser('carol');
    await seed(`groups/${PRIVATE_GROUP}/progress/2026-01-02/entries/alice`, {
      uid: 'alice',
      done: true,
    });
    await assertFails(carol.doc(`groups/${PRIVATE_GROUP}/progress/2026-01-02/entries/alice`).delete());
    await assertSucceeds(
      admin.doc(`groups/${PRIVATE_GROUP}/progress/2026-01-02/entries/alice`).delete(),
    );
  });

  it('lets members manage per-item progress under their entry', async () => {
    const alice = await asUser('alice');
    await assertSucceeds(
      alice
        .doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/alice/items/chapter-1`)
        .set({ done: true }),
    );
    await assertFails(
      alice
        .doc(`groups/${PRIVATE_GROUP}/progress/2026-01-01/entries/admin-user/items/chapter-1`)
        .set({ done: true }),
    );
  });
});

describe('groups/{groupId}/progressSummary', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
    await seed(`groups/${PRIVATE_GROUP}/progressSummary/overall/entries/alice`, {
      uid: 'alice',
      completed: 4,
    });
  });

  it('lets members read and denies non-members', async () => {
    const alice = await asUser('alice');
    const carol = await asUser('carol');
    await assertSucceeds(
      alice.doc(`groups/${PRIVATE_GROUP}/progressSummary/overall/entries/alice`).get(),
    );
    await assertFails(
      carol.doc(`groups/${PRIVATE_GROUP}/progressSummary/overall/entries/alice`).get(),
    );
  });

  it('lets any signed-in user write their own entry (current rule)', async () => {
    const carol = await asUser('carol');
    await assertSucceeds(
      carol
        .doc(`groups/${PRIVATE_GROUP}/progressSummary/overall/entries/carol`)
        .set({ uid: 'carol', completed: 1 }),
    );
  });
});

describe('groups/{groupId}/joinRequests', () => {
  before(async () => {
    await seedGroup(PRIVATE_GROUP, 'owner', false);
    await seed(`groups/${PRIVATE_GROUP}/members/alice`, { uid: 'alice', role: 'member' });
    await seed(`groups/${PRIVATE_GROUP}/joinRequests/carol`, { uid: 'carol' });
  });

  it('lets a user create their own join request', async () => {
    const dave = await asUser('dave');
    await assertSucceeds(
      dave.doc(`groups/${PRIVATE_GROUP}/joinRequests/dave`).set({ uid: 'dave' }),
    );
  });

  it('lets the requester read their request and denies other plain members', async () => {
    const carol = await asUser('carol');
    const alice = await asUser('alice');
    await assertSucceeds(carol.doc(`groups/${PRIVATE_GROUP}/joinRequests/carol`).get());
    await assertFails(alice.doc(`groups/${PRIVATE_GROUP}/joinRequests/carol`).get());
  });

  it('lets the owner read requests', async () => {
    const owner = await asUser('owner');
    await assertSucceeds(owner.doc(`groups/${PRIVATE_GROUP}/joinRequests/carol`).get());
  });

  it('lets the requester delete their request', async () => {
    const dave = await asUser('dave');
    await assertSucceeds(dave.doc(`groups/${PRIVATE_GROUP}/joinRequests/dave`).delete());
  });
});
