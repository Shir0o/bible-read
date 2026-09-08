// Tests the achievements backfill pass (backfill-achievements.js), the
// one-off re-runnable sweep that grants readers the badges their history
// predating the server-side triggers already earned (#805).
//
// The pass calls the same settle functions the Firestore triggers call, so a
// backfilled badge and a trigger-awarded one are indistinguishable. These
// tests assert what a reader ends up holding: derivation from the three
// ledgers (read-throughs, completed books, Showing-up summary, plan
// progress), the backfill-run unlock stamp, idempotency under re-runs, and
// the silent-award decision — no notification burst for old milestones.
const { describe, it } = require('mocha');
const assert = require('node:assert');
const { backfillUser, main } = require('../backfill-achievements');
const { BACKFILL_QUIET } = require('../badge-awarding');

// A small in-memory Firestore double shaped like the surface the backfill
// and the awarding module use: collection/doc walks, listDocuments, batched
// creates, and a collectionGroup query on `members` by its `uid` field.
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
          // members/{uid} sits directly under groups/{groupId}; for other
          // names the full path is what the backfill's discovery needs.
          groupId: parts[parts.length - 3],
          ref: { path: key },
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
      async get() {
        return {
          docs: matches,
          size: matches.length,
          empty: matches.length === 0,
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
  async listDocuments() {
    const prefix = `${this.path}/`;
    const refs = [];
    for (const key of this.db._docs.keys()) {
      if (key.startsWith(prefix) && !key.slice(prefix.length).includes('/')) {
        const parts = key.split('/');
        refs.push(
          new FakeDocumentRef(this.db, key, parts[parts.length - 1]),
        );
      }
    }
    return refs;
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
    return { docs, size: docs.length, empty: docs.length === 0 };
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
  async update(data) {
    const existing = this.db._docs.get(this.path) ?? {};
    this.db._docs.set(this.path, { ...existing, ...data });
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

async function badgeIds(db, uid) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('achievements')
    .get();
  return snap.docs.map((d) => d.id).sort();
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

async function notificationDocs(db, uid) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('notifications')
    .get();
  return snap.docs.map((d) => d.data());
}

describe('backfillUser — completion family', () => {
  it('derives the testament badges exactly from the read-through ledger', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/read_throughs/nt-0', { scope: 'nt' });
    await seed(db, 'users/alice/read_throughs/ot-0', { scope: 'ot' });

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), [
      'first_bible',
      'first_nt',
      'first_ot',
    ]);
  });

  it('awards first_book from any completed book, not only a lone one', async () => {
    const db = new FakeFirestore();
    // Three completed books: the trigger's settleFirstBookBadge would see
    // three and stay silent; the backfill knows a first book happened.
    await seed(db, 'users/alice/bible_books/Genesis', { completed: true });
    await seed(db, 'users/alice/bible_books/Exodus', { completed: true });
    await seed(db, 'users/alice/bible_books/John', { completed: true });

    await backfillUser(db, 'alice');

    assert.ok(await badgeDoc(db, 'alice', 'first_book'));
  });

  it('awards nothing when the reader has no history', async () => {
    const db = new FakeFirestore();

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), []);
  });
});

describe('backfillUser — consistency family', () => {
  it('derives the Showing-up tiers from the summary total', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/summary/data', { totalReadDays: 52 });

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), [
      'days_30',
      'days_50',
      'days_7',
    ]);
  });

  it('skips the family entirely when no summary exists — nothing invented', async () => {
    const db = new FakeFirestore();

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), []);
  });

  it('stamps the badge with a real unlock time, not a fabricated past date', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/summary/data', { totalReadDays: 100 });

    await backfillUser(db, 'alice');

    const badge = await badgeDoc(db, 'alice', 'days_100');
    assert.ok(badge.dateUnlocked, 'the badge must carry a timestamp');
  });
});

describe('backfillUser — plan family', () => {
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

  it('awards plan_finished when a plan progress covers its schedule', async () => {
    const db = new FakeFirestore();
    await seedPlan(db, 'alice', [1, 2, 3]);

    await backfillUser(db, 'alice');

    assert.ok(await badgeDoc(db, 'alice', 'plan_finished'));
  });

  it('does not award while days remain', async () => {
    const db = new FakeFirestore();
    await seedPlan(db, 'alice', [1, 2]);

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), []);
  });

  it('handles several plans, awarding only the finished ones', async () => {
    const db = new FakeFirestore();
    await Promise.all([
      seed(db, 'users/alice/plan_progress/done', {
        planId: 'done',
        completedDays: [1, 2],
      }),
      seed(db, 'users/alice/plan_progress/ongoing', {
        planId: 'ongoing',
        completedDays: [1],
      }),
      seed(db, 'custom_plans/done', { durationDays: 2 }),
      seed(db, 'custom_plans/ongoing', { durationDays: 2 }),
    ]);

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), ['plan_finished']);
  });
});

describe('backfillUser — mirror and silence', () => {
  it('mirrors the biggest backfilled badge into the reader’s groups', async () => {
    const db = new FakeFirestore();
    await seed(db, 'groups/g1/members/alice', { uid: 'alice', role: 'member' });
    await seed(db, 'users/alice/read_throughs/nt-0', { scope: 'nt' });
    await seed(db, 'users/alice/read_throughs/ot-0', { scope: 'ot' });

    await backfillUser(db, 'alice');

    const mirror = db._docs.get('groups/g1/badges/alice');
    assert.strictEqual(mirror.badgeId, 'first_bible');
  });

  it('notifies nobody — old milestones do not burst the inbox', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/summary/data', { totalReadDays: 365 });
    await seed(db, 'users/alice/read_throughs/nt-0', { scope: 'nt' });

    await backfillUser(db, 'alice');

    const notifications = await notificationDocs(db, 'alice');
    assert.strictEqual(
      notifications.length,
      0,
      'a backfill award must write no notification',
    );
  });

  it('the quiet flag is unset once the pass returns', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/summary/data', { totalReadDays: 7 });

    await backfillUser(db, 'alice');

    assert.strictEqual(globalThis[BACKFILL_QUIET], undefined);
  });
});

describe('backfillUser — idempotency', () => {
  it('a second run is a no-op', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/read_throughs/nt-0', { scope: 'nt' });
    await seed(db, 'users/alice/summary/data', { totalReadDays: 30 });

    await backfillUser(db, 'alice');
    const first = await badgeDoc(db, 'alice', 'days_7');

    await backfillUser(db, 'alice');

    assert.deepStrictEqual(await badgeIds(db, 'alice'), [
      'days_30',
      'days_7',
      'first_nt',
    ]);
    const still = await badgeDoc(db, 'alice', 'days_7');
    assert.strictEqual(
      still.dateUnlocked,
      first.dateUnlocked,
      'a re-run must not move the unlock time',
    );
  });

  it('does not re-notify on a re-run', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/read_throughs/nt-0', { scope: 'nt' });
    await backfillUser(db, 'alice');
    // Re-run inside the trigger world (quiet flag off): held badges notify
    // nobody because nothing is missing.
    const { settleReadThroughBadges } = require('../badge-awarding');
    await settleReadThroughBadges(db, 'alice');
    const notifications = await notificationDocs(db, 'alice');
    assert.strictEqual(notifications.length, 0);
  });
});
describe('main — the production sweep', () => {
  it('processes every reader holding derivable history and reports the count', async () => {
    const db = new FakeFirestore();
    await seed(db, 'users/alice/summary/data', { totalReadDays: 7 });
    await seed(db, 'users/bob/summary/data', { totalReadDays: 1 });
    // A reader with no history in any source is not visited at all.
    await seed(db, 'users/zoe', { name: 'Zoe' });

    const result = await main(db);

    assert.strictEqual(result.users, 2);
    assert.deepStrictEqual(await badgeIds(db, 'alice'), ['days_7']);
    assert.deepStrictEqual(await badgeIds(db, 'bob'), []);
    assert.deepStrictEqual(await badgeIds(db, 'zoe'), []);
  });

  it('finds a reader whose profile document is missing entirely', async () => {
    // The FCM write and profile doc are best-effort; history is not. A
    // reader with only subcollection documents must still be discovered.
    const db = new FakeFirestore();
    await seed(db, 'users/alice/read_throughs/nt-0', { scope: 'nt' });

    const result = await main(db);

    assert.strictEqual(result.users, 1);
    assert.deepStrictEqual(await badgeIds(db, 'alice'), ['first_nt']);
  });
});
