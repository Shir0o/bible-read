// Tests the server-side badge awarding module (badge-awarding.js), which the
// awardReadThroughBadges and awardFirstBookBadge Firestore triggers call.
//
// The security rules deny every client write to users/{uid}/achievements, so
// these triggers are the only path a badge can enter through; the emulator
// suite in firestore-tests/ pins the rules side.
const { describe, it } = require('mocha');
const assert = require('node:assert');
const {
  settleReadThroughBadges,
  settleFirstBookBadge,
} = require('../badge-awarding');

// A small in-memory Firestore double shaped like the surface the awarding
// module uses: collection/doc walks, batched creates, and a collectionGroup
// query on `members` by its `uid` field.
class FakeBatch {
  constructor(db) {
    this.db = db;
    this.ops = [];
  }
  create(ref, data) {
    this.ops.push({ type: 'create', ref, data });
    return this;
  }
  async commit() {
    for (const op of this.ops) {
      if (op.type === 'create') {
        await op.ref.create(op.data);
      }
    }
  }
}

class FakeFirestore {
  constructor() {
    this._docs = new Map();
  }
  collection(name) {
    return new FakeCollectionRef(this, name);
  }
  collectionGroup(name) {
    const matches = [];
    for (const [key, value] of this._docs.entries()) {
      const parts = key.split('/');
      if (parts.length >= 3 && parts[parts.length - 2] === name) {
        matches.push({
          id: parts[parts.length - 1],
          // members/{uid} sits directly under groups/{groupId}.
          groupId: parts[parts.length - 3],
          data: value,
        });
      }
    }
    return {
      where(field, op, value) {
        assert.strictEqual(op, '==');
        const hits = matches.filter((m) => m.data[field] === value);
        return {
          async get() {
            return {
              docs: hits.map((m) => ({
                id: m.id,
                ref: { parent: { parent: { id: m.groupId } } },
                data: () => ({ ...m.data }),
              })),
              size: hits.length,
            };
          },
        };
      },
    };
  }
  batch() {
    return new FakeBatch(this);
  }
}

class FakeCollectionRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }
  doc(id) {
    const fullPath = `${this.path}/${id}`;
    const parts = fullPath.split('/');
    return new FakeDocumentRef(this.db, fullPath, parts[parts.length - 1]);
  }
  async get() {
    const prefix = `${this.path}/`;
    const docs = [];
    for (const [key, value] of this.db._docs.entries()) {
      if (key.startsWith(prefix) && !key.slice(prefix.length).includes('/')) {
        docs.push({
          id: key.slice(prefix.length),
          data: () => ({ ...value }),
        });
      }
    }
    return { docs, size: docs.length };
  }
}

class FakeDocumentRef {
  constructor(db, path, id) {
    this.db = db;
    this.path = path;
    this.id = id;
  }
  collection(name) {
    return new FakeCollectionRef(this.db, `${this.path}/${name}`);
  }
  async get() {
    if (!this.db._docs.has(this.path)) {
      return { exists: false, id: this.id, data: () => undefined };
    }
    const data = this.db._docs.get(this.path);
    return { exists: true, id: this.id, data: () => ({ ...data }) };
  }
  async set(data) {
    this.db._docs.set(this.path, { ...data });
  }
  async create(data) {
    if (this.db._docs.has(this.path)) {
      throw new Error(`already exists: ${this.path}`);
    }
    this.db._docs.set(this.path, { ...data });
  }
}

async function seed(db, path, data) {
  const parts = path.split('/');
  let ref = db.collection(parts[0]);
  let i = 1;
  while (i + 1 < parts.length) {
    ref = ref.doc(parts[i]).collection(parts[i + 1]);
    i += 2;
  }
  await ref.doc(parts[parts.length - 1]).set(data);
}

async function badgeDoc(db, uid, id) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('achievements')
    .doc(id)
    .get();
  return snap.exists ? snap.data() : null;
}

async function badgeIds(db, uid) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('achievements')
    .get();
  return snap.docs.map((d) => d.id).sort();
}

function testamentLedger(db, uid, scope, from, n) {
  return Promise.all(
    Array.from({ length: n }, (_, i) =>
      seed(db, `users/${uid}/read_throughs/${scope}-${from + i}`, { scope })),
  );
}

describe('settleReadThroughBadges', () => {
  it('awards a first testament badge, stamped once', async () => {
    const db = new FakeFirestore();
    await testamentLedger(db, 'alice', 'nt', 0, 1);

    await settleReadThroughBadges(db, 'alice');
    await settleReadThroughBadges(db, 'alice');

    const badge = await badgeDoc(db, 'alice', 'first_nt');
    assert.strictEqual(badge.type, 'read_through');
    assert.ok(badge.dateUnlocked, 'badge must carry an unlock timestamp');
    assert.deepStrictEqual(await badgeIds(db, 'alice'), ['first_nt']);
  });

  it('awards the landmark set on the first whole Bible', async () => {
    const db = new FakeFirestore();
    await testamentLedger(db, 'alice', 'ot', 0, 1);
    await testamentLedger(db, 'alice', 'nt', 0, 1);

    await settleReadThroughBadges(db, 'alice');

    assert.deepStrictEqual(
      await badgeIds(db, 'alice'),
      ['first_bible', 'first_nt', 'first_ot'],
    );
  });

  it('unlocks tiers at five whole Bibles, not either side', async () => {
    const db = new FakeFirestore();
    await testamentLedger(db, 'alice', 'ot', 0, 4);
    await testamentLedger(db, 'alice', 'nt', 0, 4);
    await settleReadThroughBadges(db, 'alice');
    assert.ok(!(await badgeIds(db, 'alice')).includes('bible_5'));

    await testamentLedger(db, 'alice', 'ot', 4, 1);
    await testamentLedger(db, 'alice', 'nt', 4, 1);
    await settleReadThroughBadges(db, 'alice');
    assert.ok((await badgeIds(db, 'alice')).includes('bible_5'));

    await testamentLedger(db, 'alice', 'ot', 5, 1);
    await testamentLedger(db, 'alice', 'nt', 5, 1);
    await settleReadThroughBadges(db, 'alice');
    assert.strictEqual(
      (await badgeIds(db, 'alice')).filter((id) => id === 'bible_5').length,
      1,
    );
  });

  it('a re-run never re-awards or moves the unlock time', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/achievements/first_nt', {
      type: 'read_through',
      dateUnlocked: 'the-original-time',
    });
    await testamentLedger(db, 'alice', 'nt', 0, 2);

    await settleReadThroughBadges(db, 'alice');

    const badge = await badgeDoc(db, 'alice', 'first_nt');
    assert.strictEqual(badge.dateUnlocked, 'the-original-time');
  });

  it('badges are never lost when a count falls', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/achievements/first_bible', {
      type: 'read_through',
      dateUnlocked: 'kept',
    });

    await settleReadThroughBadges(db, 'alice');

    const badge = await badgeDoc(db, 'alice', 'first_bible');
    assert.strictEqual(badge.dateUnlocked, 'kept');
  });

  it('mirrors the biggest new badge into each of the reader’s groups', async () => {
    const db = new FakeFirestore();
    await seed(db, 'groups/g1/members/alice', { uid: 'alice', role: 'member' });
    await seed(db, 'groups/g2/members/alice', { uid: 'alice', role: 'member' });
    await testamentLedger(db, 'alice', 'ot', 0, 1);
    await testamentLedger(db, 'alice', 'nt', 0, 1);

    await settleReadThroughBadges(db, 'alice');

    for (const groupId of ['g1', 'g2']) {
      const parts = db._docs.get(`groups/${groupId}/badges/alice`);
      assert.strictEqual(parts.badgeId, 'first_bible');
      assert.strictEqual(parts.type, 'read_through');
    }
  });

  it('a later, bigger badge replaces an older mirror', async () => {
    const db = new FakeFirestore();
    await seed(db, 'groups/g1/members/alice', { uid: 'alice', role: 'member' });
    await seed(db, 'groups/g1/badges/alice', { badgeId: 'first_nt' });
    await testamentLedger(db, 'alice', 'nt', 0, 1);
    await settleReadThroughBadges(db, 'alice');

    await testamentLedger(db, 'alice', 'ot', 0, 1);
    await settleReadThroughBadges(db, 'alice');

    assert.strictEqual(
      db._docs.get('groups/g1/badges/alice').badgeId,
      'first_bible',
    );
  });

  it('handles a reader in no groups', async () => {
    const db = new FakeFirestore();
    await testamentLedger(db, 'alice', 'nt', 0, 1);

    await settleReadThroughBadges(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), ['first_nt']);
  });
});

describe('settleFirstBookBadge', () => {
  it('awards first_book on the first completed book', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/bible_books/Genesis', { completed: true });

    await settleFirstBookBadge(db, 'alice');

    const badge = await badgeDoc(db, 'alice', 'first_book');
    assert.strictEqual(badge.type, 'achievement');
    assert.ok(badge.dateUnlocked);
  });

  it('does not award when completed books already exist', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/bible_books/Genesis', { completed: true });
    await seed(db, 'users/alice/bible_books/Exodus', { completed: true });

    await settleFirstBookBadge(db, 'alice');

    assert.strictEqual(await badgeDoc(db, 'alice', 'first_book'), null);
  });
});
