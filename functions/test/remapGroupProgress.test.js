// Tests the cross-member remap Cloud Function.
//
// The function ports the Dart `remapProgress` algorithm to JavaScript and
// applies it to every member's progress on a group's schedule regeneration,
// then rewrites:
//   * groups/{gid}/schedule/{dateId}
//   * groups/{gid}/progress/{dateId}/entries/{uid}/items/{index}
//   * groups/{gid}/progressSummary/data/entries/{uid}.completed (absolutely)
//   * groups/{gid}/planConfig.revision (bumped)
//   * groups/{gid}/members/{uid}.remappedRevision (per member)
//
// Ordered so a mid-flight failure leaves a *superset* schedule, never a hole.
const {after, describe, it} = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');

process.env.NODE_ENV = 'test';

// A small in-memory Firestore double shaped exactly like the surface the
// callable uses.
class FakeBatch {
  constructor(db) {
    this.db = db;
    this.ops = [];
  }
  set(ref, data, options) {
    this.ops.push({ type: 'set', ref, data, options });
    return this;
  }
  update(ref, data) {
    this.ops.push({ type: 'update', ref, data });
    return this;
  }
  delete(ref) {
    this.ops.push({ type: 'delete', ref });
    return this;
  }
  async commit() {
    for (const op of this.ops) {
      if (op.type === 'set') {
        await op.ref.set(op.data, op.options);
      } else if (op.type === 'update') {
        await op.ref.update(op.data);
      } else if (op.type === 'delete') {
        await op.ref.delete();
      }
    }
  }
}

class FakeFirestore {
  constructor() {
    this._docs = new Map();
    this._auto = 0;
  }
  collection(name) {
    return new FakeCollectionRef(this, name, '');
  }
  batch() {
    return new FakeBatch(this);
  }
}

class FakeCollectionRef {
  constructor(db, path, parentPath) {
    this.db = db;
    this.path = path; // absolute path
    this.parentPath = parentPath || '';
  }
  doc(id) {
    const docId = id || `auto_${++this.db._auto}`;
    const fullPath = this.path ? `${this.path}/${docId}` : docId;
    return new FakeDocumentRef(this.db, fullPath, docId);
  }
  async get() {
    const prefix = this.path ? `${this.path}/` : '';
    const docs = [];
    for (const [key, value] of this.db._docs.entries()) {
      if (key.startsWith(prefix)) {
        const remainder = key.substring(prefix.length);
        if (!remainder.includes('/')) {
          const data = value;
          docs.push({
            id: remainder,
            ref: new FakeDocumentRef(this.db, key, remainder),
            data: () => JSON.parse(JSON.stringify(data)),
            exists: true,
          });
        }
      }
    }
    return {
      docs,
      size: docs.length,
      empty: docs.length === 0,
      forEach(cb) { docs.forEach(cb); },
    };
  }
}

class FakeDocumentRef {
  constructor(db, path, id) {
    this.db = db;
    this.path = path;
    this.id = id;
  }
  doc(id) {
    return new FakeDocumentRef(this.db, `${this.path}/${id}`, id);
  }
  collection(name) {
    const subPath = `${this.path}/${name}`;
    return new FakeCollectionRef(this.db, subPath, this.path);
  }
  async get() {
    if (!this.db._docs.has(this.path)) {
      return { exists: false, id: this.id, data: () => undefined };
    }
    const data = this.db._docs.get(this.path);
    return { exists: true, id: this.id, data: () => JSON.parse(JSON.stringify(data)) };
  }
  async set(data, options) {
    if (options && options.merge && this.db._docs.has(this.path)) {
      const existing = this.db._docs.get(this.path) || {};
      this.db._docs.set(this.path, { ...existing, ...JSON.parse(JSON.stringify(data)) });
      return;
    }
    this.db._docs.set(this.path, JSON.parse(JSON.stringify(data)));
  }
  async delete() {
    this.db._docs.delete(this.path);
  }
}

function navigate(db, path) {
  // Paths are collection/doc(/collection/doc)* — they may also describe a
  // sub-collection alone (e.g. "groups/g1/planConfig" reads as
  // collection(doc(planConfig)) for our tests). Walk pairs of
  // (collection, doc); if a trailing collection is left over, treat it as
  // a doc name so setDoc/getDoc always end on a document.
  const parts = path.split('/');
  let ref = db;
  for (let i = 0; i < parts.length; i += 2) {
    ref = ref.collection(parts[i]);
    if (i + 1 < parts.length) {
      ref = ref.doc(parts[i + 1]);
    } else {
      return ref;
    }
  }
  return ref;
}

async function setDoc(db, path, data) {
  await navigate(db, path).set(data);
}

async function getDoc(db, path) {
  return navigate(db, path).get();
}

function withFirestore(db, fn) {
  const originalFirestore = admin.firestore;
  const fakeFirestore = () => db;
  fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
  fakeFirestore.Timestamp = admin.firestore.Timestamp;
  Object.defineProperty(admin, 'firestore', {
    value: fakeFirestore,
    configurable: true,
    writable: true,
  });
  try {
    return fn();
  } finally {
    Object.defineProperty(admin, 'firestore', {
      value: originalFirestore,
      configurable: true,
      writable: true,
    });
  }
}

describe('remapGroupProgress', () => {
  it('moves a tick from the old position to the new day that means the same chapter', async () => {
    const db = new FakeFirestore();
    await setDoc(db, 'groups/g1', { ownerUid: 'owner', planConfig: { revision: 1 } });
    await setDoc(db, 'groups/g1/members/owner', { role: 'owner' });

    // Old schedule: day 1 = Jeremiah 1-2, day 2 = Jeremiah 3-4.
    await setDoc(db, 'groups/g1/schedule/2026-09-01', {
      chapters: ['Jeremiah 1', 'Jeremiah 2'],
    });
    await setDoc(db, 'groups/g1/schedule/2026-09-02', {
      chapters: ['Jeremiah 3', 'Jeremiah 4'],
    });

    // Alice ticked day 2 = 0 ("Jeremiah 3"). FakeFirestore needs the parent
    // progress/{dateId} doc to exist for the collection listing to surface
    // it; the real Firestore auto-creates on subcollection writes, but the
    // fake does not.
    await setDoc(db, 'groups/g1/progress/2026-09-02', { dateId: '2026-09-02' });
    await setDoc(db, 'groups/g1/progress/2026-09-02/entries/alice', {
      count: 1,
      uid: 'alice',
      groupId: 'g1',
      dateId: '2026-09-02',
    });
    await setDoc(db, 'groups/g1/progress/2026-09-02/entries/alice/items/0', {
      done: true,
    });
    await setDoc(db, 'groups/g1/progressSummary/data/entries/alice', {
      uid: 'alice',
      completed: 1,
    });

    await withFirestore(db, async () => {
      const wrapped = functionsTest.wrap(myFunctions.remapGroupProgress);
      await wrapped({
        data: {
          groupId: 'g1',
          days: [
            { dateId: '2026-09-01', chapters: ['Jeremiah 1'] },
            { dateId: '2026-09-02', chapters: ['Jeremiah 2'] },
            { dateId: '2026-09-03', chapters: ['Jeremiah 3', 'Jeremiah 4'] },
          ],
        },
        auth: { uid: 'owner' },
      });
    });

    // The new schedule has been written.
    const day1 = await getDoc(db, 'groups/g1/schedule/2026-09-01');
    assert.deepStrictEqual(day1.data().chapters, ['Jeremiah 1']);
    const day3 = await getDoc(db, 'groups/g1/schedule/2026-09-03');
    assert.deepStrictEqual(day3.data().chapters, ['Jeremiah 3', 'Jeremiah 4']);

    // Jeremiah 3 is still ticked for alice, but now on day 3 at index 0.
    const moved = await getDoc(
      db,
      'groups/g1/progress/2026-09-03/entries/alice/items/0',
    );
    assert.equal(moved.exists, true);
    const old = await getDoc(
      db,
      'groups/g1/progress/2026-09-02/entries/alice',
    );
    assert.equal(old.exists, false);

    // Summary is repaired absolutely — still 1.
    const summary = await getDoc(
      db,
      'groups/g1/progressSummary/data/entries/alice',
    );
    assert.equal(summary.data().completed, 1);

    // revision bumped, remappedRevision stamped.
    const group = await getDoc(db, 'groups/g1');
    assert.equal(group.data().planConfig.revision, 2);
    const member = await getDoc(db, 'groups/g1/members/owner');
    assert.equal(member.data().remappedRevision, 2);
  });

  it('rejects a caller who is not the owner or an admin', async () => {
    const db = new FakeFirestore();
    await setDoc(db, 'groups/g1', { ownerUid: 'owner' });
    await setDoc(db, 'groups/g1/members/eve', { role: 'member' });

    await withFirestore(db, async () => {
      const wrapped = functionsTest.wrap(myFunctions.remapGroupProgress);
      await assert.rejects(
        wrapped({ data: { groupId: 'g1', days: [] }, auth: { uid: 'eve' } }),
        (err) => err.code === 'permission-denied',
      );
    });
  });

  it('rejects unauthenticated callers', async () => {
    const db = new FakeFirestore();
    await setDoc(db, 'groups/g1', { ownerUid: 'owner' });

    await withFirestore(db, async () => {
      const wrapped = functionsTest.wrap(myFunctions.remapGroupProgress);
      await assert.rejects(
        wrapped({ data: { groupId: 'g1', days: [] }, auth: null }),
        (err) => err.code === 'unauthenticated',
      );
    });
  });

  it('throws resource-exhausted when the synchronous cap is exceeded', async () => {
    const db = new FakeFirestore();
    await setDoc(db, 'groups/g1', { ownerUid: 'owner', planConfig: { revision: 1 } });
    await setDoc(db, 'groups/g1/members/owner', { role: 'owner' });
    // 26 members, each with a tick — over the synthetic 500x25 cap.
    await setDoc(db, 'groups/g1/progress/2026-09-01', { dateId: '2026-09-01' });
    for (var i = 0; i < 26; i++) {
      await setDoc(db, `groups/g1/members/m${i}`, { role: 'member' });
      await setDoc(
        db,
        `groups/g1/progress/2026-09-01/entries/m${i}/items/0`,
        { done: true },
      );
    }

    const days = [];
    for (var i = 0; i < 600; i++) {
      days.push({
        dateId: `2026-09-${(i + 1).toString().padStart(2, '0')}`,
        chapters: ['Jeremiah 1'],
      });
    }

    await withFirestore(db, async () => {
      const wrapped = functionsTest.wrap(myFunctions.remapGroupProgress);
      await assert.rejects(
        wrapped({ data: { groupId: 'g1', days }, auth: { uid: 'owner' } }),
        (err) => err.code === 'resource-exhausted',
      );
    });
  });

  it('deletes schedule days that no longer belong to the plan', async () => {
    const db = new FakeFirestore();
    await setDoc(db, 'groups/g1', { ownerUid: 'owner', planConfig: { revision: 1 } });
    await setDoc(db, 'groups/g1/members/owner', { role: 'owner' });
    await setDoc(db, 'groups/g1/schedule/2026-09-01', { chapters: ['Isaiah 1'] });
    await setDoc(db, 'groups/g1/schedule/2026-09-02', { chapters: ['Isaiah 2'] });
    await setDoc(db, 'groups/g1/schedule/2026-09-03', { chapters: ['Jeremiah 1'] });

    await withFirestore(db, async () => {
      const wrapped = functionsTest.wrap(myFunctions.remapGroupProgress);
      await wrapped({
        data: {
          groupId: 'g1',
          days: [{ dateId: '2026-09-03', chapters: ['Jeremiah 1'] }],
        },
        auth: { uid: 'owner' },
      });
    });

    // The Isaiah days are gone.
    const dropped1 = await getDoc(db, 'groups/g1/schedule/2026-09-01');
    assert.equal(dropped1.exists, false);
    const dropped2 = await getDoc(db, 'groups/g1/schedule/2026-09-02');
    assert.equal(dropped2.exists, false);
    const kept = await getDoc(db, 'groups/g1/schedule/2026-09-03');
    assert.equal(kept.exists, true);
  });

  it('rejects a day whose dateId is missing or whose chapters are not strings', async () => {
    const db = new FakeFirestore();
    await setDoc(db, 'groups/g1', { ownerUid: 'owner' });

    const malformed = [
      { dateId: '', chapters: ['Jeremiah 1'] },          // empty dateId
      { dateId: '2026-09-01', chapters: 'not-an-array' }, // chapters not array
      { dateId: '2026-09-01', chapters: [1, 2, 3] },      // non-string chapters
      null,                                                // null entry
      'a string',                                          // wrong type
    ];

    await withFirestore(db, async () => {
      const wrapped = functionsTest.wrap(myFunctions.remapGroupProgress);
      for (const bad of malformed) {
        await assert.rejects(
          wrapped({
            data: { groupId: 'g1', days: [bad] },
            auth: { uid: 'owner' },
          }),
          (err) => err.code === 'invalid-argument',
          'should reject malformed day: ' + JSON.stringify(bad),
        );
      }
    });
  });
});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});