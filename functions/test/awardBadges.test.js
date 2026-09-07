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
  settleConsistencyBadges,
  settlePlanFinishedBadge,
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
  set(ref, data) {
    this.ops.push({ type: 'set', ref, data });
    return this;
  }
  async commit() {
    for (const op of this.ops) {
      if (op.type === 'create') {
        await op.ref.create(op.data);
      } else if (op.type === 'set') {
        await op.ref.set(op.data);
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
    // Support no-argument doc() the way Firestore generates an id.
    const resolved =
      id ?? `auto-${(this.db._autoId = (this.db._autoId ?? 0) + 1)}`;
    const fullPath = `${this.path}/${resolved}`;
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
  async create(data) {
    if (this.db._refuseWrites) {
      throw new Error(`write refused: ${this.path}`);
    }
    if (this.db._docs.has(this.path)) {
      throw new Error(`already exists: ${this.path}`);
    }
    this.db._docs.set(this.path, { ...data });
  }
  async set(data) {
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

describe('settleConsistencyBadges', () => {
  it('awards the 50-day badge on the 50th day shown up, exactly once', async () => {
    const db = new FakeFirestore();

    await settleConsistencyBadges(db, 'alice', 49);
    assert.strictEqual(await badgeDoc(db, 'alice', 'days_50'), null);

    await settleConsistencyBadges(db, 'alice', 50);
    const badge = await badgeDoc(db, 'alice', 'days_50');
    assert.ok(badge, 'the 50th day must award the badge');
    assert.ok(badge.dateUnlocked);

    await settleConsistencyBadges(db, 'alice', 51);
    const still = await badgeDoc(db, 'alice', 'days_50');
    assert.strictEqual(
      still.dateUnlocked,
      badge.dateUnlocked,
      'the 51st day must not move the unlock time',
    );
    assert.strictEqual(
      (await badgeIds(db, 'alice')).filter((id) => id === 'days_50').length,
      1,
    );
  });

  it('awards every tier whose threshold is crossed', async () => {
    const db = new FakeFirestore();

    await settleConsistencyBadges(db, 'alice', 365);

    assert.deepStrictEqual(await badgeIds(db, 'alice'), [
      'days_100',
      'days_30',
      'days_365',
      'days_50',
      'days_7',
    ]);
  });

  it('counts Showing up regardless of any Plan', async () => {
    // The source is the Showing-up summary — a reader who only marks the
    // day, with no plan attached, accrues consistency the same way.
    const db = new FakeFirestore();

    await settleConsistencyBadges(db, 'alice', 7);

    assert.ok(await badgeDoc(db, 'alice', 'days_7'));
  });

  it('a re-run never re-awards or moves the unlock time', async () => {
    const db = new FakeFirestore();
    await settleConsistencyBadges(db, 'alice', 30);

    await settleConsistencyBadges(db, 'alice', 30);
    await settleConsistencyBadges(db, 'alice', 365);

    const badge = await badgeDoc(db, 'alice', 'days_30');
    assert.strictEqual(
      (await badgeIds(db, 'alice')).filter((id) => id === 'days_30').length,
      1,
    );
    assert.ok(badge.dateUnlocked);
  });
});

describe('settlePlanFinishedBadge', () => {
  function seedPlan(db, uid, completedDays) {
    return Promise.all([
      seed(db, `users/${uid}/plan_progress/p1`, {
        planId: 'p1',
        completedDays,
      }),
      seed(db, 'custom_plans/p1', {
        title: 'Gospel of John',
        durationDays: 3,
        schedule: [
          { day: 1, readings: ['John 1'] },
          { day: 2, readings: ['John 2'] },
          { day: 3, readings: ['John 3'] },
        ],
      }),
    ]);
  }

  it('awards plan_finished when every day of the plan is complete', async () => {
    const db = new FakeFirestore();
    await seedPlan(db, 'alice', [1, 2, 3]);

    await settlePlanFinishedBadge(db, 'alice', 'p1');

    const badge = await badgeDoc(db, 'alice', 'plan_finished');
    assert.strictEqual(badge.type, 'plan');
    assert.ok(badge.dateUnlocked);
  });

  it('does not award while days remain', async () => {
    const db = new FakeFirestore();
    await seedPlan(db, 'alice', [1, 2]);

    await settlePlanFinishedBadge(db, 'alice', 'p1');

    assert.strictEqual(await badgeDoc(db, 'alice', 'plan_finished'), null);
  });

  it('skips quietly when the plan definition is missing', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/plan_progress/p1', {
      planId: 'p1',
      completedDays: [1, 2, 3],
    });

    await settlePlanFinishedBadge(db, 'alice', 'p1');

    assert.strictEqual(await badgeDoc(db, 'alice', 'plan_finished'), null);
  });

  it('a re-run never re-awards or moves the unlock time', async () => {
    const db = new FakeFirestore();
    await seedPlan(db, 'alice', [1, 2, 3]);
    await settlePlanFinishedBadge(db, 'alice', 'p1');
    const badge = await badgeDoc(db, 'alice', 'plan_finished');

    await settlePlanFinishedBadge(db, 'alice', 'p1');

    const still = await badgeDoc(db, 'alice', 'plan_finished');
    assert.strictEqual(still.dateUnlocked, badge.dateUnlocked);
  });
});

describe('unlock notifications', () => {
  it('the reader is notified when a badge unlocks', async () => {
    const db = new FakeFirestore();

    await settleConsistencyBadges(db, 'alice', 7);

    const notifications = await db
      .collection('users')
      .doc('alice')
      .collection('notifications')
      .get();
    const docs = notifications.docs.map((d) => d.data());
    assert.strictEqual(docs.length, 1);
    assert.strictEqual(docs[0].type, 'badge');
    assert.strictEqual(docs[0].read, false);
    assert.ok(docs[0].message.includes('7'));
    assert.ok(docs[0].timestamp, 'the notification carries a timestamp');
  });

  it('an already-held badge notifies nobody', async () => {
    const db = new FakeFirestore();
    // Day 50 crosses three tiers at once — one notification per badge.
    await settleConsistencyBadges(db, 'alice', 50);

    await settleConsistencyBadges(db, 'alice', 50);

    const notifications = await db
      .collection('users')
      .doc('alice')
      .collection('notifications')
      .get();
    assert.strictEqual(notifications.docs.length, 3);
  });
});

describe('refused writes', () => {
  it('a refused achievement write surfaces rather than being swallowed', async () => {
    const db = new FakeFirestore();
    db._refuseWrites = true;

    await assert.rejects(() => settleConsistencyBadges(db, 'alice', 50));
  });
});
