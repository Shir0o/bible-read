const {after, afterEach, describe, it} = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({ projectId: 'demo' });
const myFunctions = require('../index');
const utils = require('../notification-utils');

process.env.NODE_ENV = 'test';

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

class FakeQueryDocumentSnapshot {
  constructor(id, data) {
    this.id = id;
    this._data = clone(data) || {};
  }

  data() {
    return clone(this._data);
  }
}

class FakeQuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.size = docs.length;
    this.empty = docs.length === 0;
  }

  forEach(cb) {
    this.docs.forEach(cb);
  }
}

class FakeFirestore {
  constructor() {
    this._docs = new Map();
    this._auto = 0;
  }

  collection(name) {
    return new FakeCollectionRef(this, name);
  }

  async runTransaction(handler) {
    const transaction = new FakeTransaction(this);
    return handler(transaction);
  }
}

class FakeCollectionRef {
  constructor(db, path) {
    this.db = db;
    this.path = path; // string path like 'users' or 'users/user1/notifications'
  }

  doc(id) {
    let docId = id;
    if (!docId) {
      docId = `auto_${++this.db._auto}`;
    }
    const path = this.path ? `${this.path}/${docId}` : docId;
    return new FakeDocumentRef(this.db, path, docId);
  }

  async get() {
    const prefix = this.path ? `${this.path}/` : '';
    const docs = [];
    for (const [key, value] of this.db._docs.entries()) {
      if (key.startsWith(prefix)) {
        const remainder = key.substring(prefix.length);
        if (!remainder.includes('/')) {
          docs.push(new FakeQueryDocumentSnapshot(remainder, value));
        }
      }
    }
    return new FakeQuerySnapshot(docs);
  }
}

class FakeDocumentRef {
  constructor(db, path, id) {
    this.db = db;
    this.path = path;
    this.id = id;
  }

  async get() {
    if (!this.db._docs.has(this.path)) {
      return { exists: false, id: this.id, data: () => undefined };
    }
    const data = this.db._docs.get(this.path);
    return {
      exists: true,
      id: this.id,
      data: () => clone(data),
    };
  }

  async set(data, options) {
    if (options && options.merge && this.db._docs.has(this.path)) {
      const existing = this.db._docs.get(this.path) || {};
      this.db._docs.set(this.path, { ...existing, ...clone(data) });
      return;
    }
    this.db._docs.set(this.path, clone(data));
  }

  async update(data) {
    if (!this.db._docs.has(this.path)) {
      throw new Error('not-found');
    }
    const existing = this.db._docs.get(this.path) || {};
    this.db._docs.set(this.path, { ...existing, ...clone(data) });
  }

  collection(name) {
    const subPath = this.path ? `${this.path}/${name}` : name;
    return new FakeCollectionRef(this.db, subPath);
  }
}

class FakeTransaction {
  constructor(db) {
    this.db = db;
  }

  async get(ref) {
    return ref.get();
  }

  set(ref, data, options) {
    return ref.set(data, options);
  }

  update(ref, data) {
    return ref.update(data);
  }
}

describe('claimSeasonalChallengeReward', () => {
  afterEach(() => {
    utils.invalidateUserCache();
  });

  it('awards reward and sends push when enabled', async () => {
    const db = new FakeFirestore();
    await db.collection('seasons').doc('spring').collection('challenges').doc('c1').set({
      title: 'Read together',
      goal: 3,
      reward: { title: 'Bonus Badge', type: 'badge' },
    });
    await db.collection('users').doc('user1').set({ fcmToken: 'tok123' });
    await db
      .collection('users')
      .doc('user1')
      .collection('seasonChallenges')
      .doc('spring_c1')
      .set({ totalProgress: 3 });

    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    function fakeFirestore() {
      return db;
    }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let captured;
    Object.defineProperty(admin, 'firestore', {
      value: fakeFirestore,
      configurable: true,
      writable: true,
    });
    Object.defineProperty(admin, 'messaging', {
      value: () => ({
        send: async (msg) => {
          captured = msg;
        },
      }),
      configurable: true,
      writable: true,
    });

    try {
      const wrapped = functionsTest.wrap(myFunctions.claimSeasonalChallengeReward);
      const result = await wrapped({
        data: { seasonId: 'spring', challengeId: 'c1' },
        auth: { uid: 'user1' },
      });

      assert.deepEqual(result, { success: true });

      const rewardDoc = await db
        .collection('users')
        .doc('user1')
        .collection('seasonRewards')
        .doc('spring_c1')
        .get();
      assert.equal(rewardDoc.exists, true);
      assert.equal(rewardDoc.data().challengeTitle, 'Read together');

      const progressDoc = await db
        .collection('users')
        .doc('user1')
        .collection('seasonChallenges')
        .doc('spring_c1')
        .get();
      assert.equal(progressDoc.data().rewardClaimedAt, 'ts');

      const notifications = await db
        .collection('users')
        .doc('user1')
        .collection('notifications')
        .get();
      assert.equal(notifications.size, 1);
      assert.equal(
        notifications.docs[0].data().message,
        'You claimed Bonus Badge.',
      );

      assert.equal(captured.token, 'tok123');
      assert.match(captured.notification.body, /Read together/);
    } finally {
      Object.defineProperty(admin, 'firestore', {
        value: originalFirestore,
        configurable: true,
        writable: true,
      });
      Object.defineProperty(admin, 'messaging', {
        value: originalMessaging,
        configurable: true,
        writable: true,
      });
    }
  });

  it('throws when already claimed', async () => {
    const db = new FakeFirestore();
    await db.collection('seasons').doc('spring').collection('challenges').doc('c1').set({
      title: 'Read together',
      goal: 1,
    });
    await db.collection('users').doc('user2').set({ fcmToken: 'tok456' });
    await db
      .collection('users')
      .doc('user2')
      .collection('seasonChallenges')
      .doc('spring_c1')
      .set({ totalProgress: 1, rewardClaimedAt: 'yesterday' });

    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    function fakeFirestore() {
      return db;
    }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let sent = false;
    Object.defineProperty(admin, 'firestore', {
      value: fakeFirestore,
      configurable: true,
      writable: true,
    });
    Object.defineProperty(admin, 'messaging', {
      value: () => ({
        send: async () => {
          sent = true;
        },
      }),
      configurable: true,
      writable: true,
    });

    try {
      const wrapped = functionsTest.wrap(myFunctions.claimSeasonalChallengeReward);
      await wrapped({
        data: { seasonId: 'spring', challengeId: 'c1' },
        auth: { uid: 'user2' },
      });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'failed-precondition');
    } finally {
      assert.equal(sent, false);
      Object.defineProperty(admin, 'firestore', {
        value: originalFirestore,
        configurable: true,
        writable: true,
      });
      Object.defineProperty(admin, 'messaging', {
        value: originalMessaging,
        configurable: true,
        writable: true,
      });
    }
  });

  it('throws when progress is insufficient', async () => {
    const db = new FakeFirestore();
    await db.collection('seasons').doc('spring').collection('challenges').doc('c1').set({
      title: 'Read together',
      goal: 5,
    });
    await db.collection('users').doc('user3').set({ fcmToken: 'tok789' });
    await db
      .collection('users')
      .doc('user3')
      .collection('seasonChallenges')
      .doc('spring_c1')
      .set({ totalProgress: 2 });

    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    function fakeFirestore() {
      return db;
    }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', {
      value: fakeFirestore,
      configurable: true,
      writable: true,
    });
    Object.defineProperty(admin, 'messaging', {
      value: () => ({
        send: async () => {
          throw new Error('should not send');
        },
      }),
      configurable: true,
      writable: true,
    });

    try {
      const wrapped = functionsTest.wrap(myFunctions.claimSeasonalChallengeReward);
      await wrapped({
        data: { seasonId: 'spring', challengeId: 'c1' },
        auth: { uid: 'user3' },
      });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'failed-precondition');
    } finally {
      Object.defineProperty(admin, 'firestore', {
        value: originalFirestore,
        configurable: true,
        writable: true,
      });
      Object.defineProperty(admin, 'messaging', {
        value: originalMessaging,
        configurable: true,
        writable: true,
      });
    }
  });

  it('does not send push when notifications are disabled', async () => {
    const db = new FakeFirestore();
    await db.collection('seasons').doc('spring').collection('challenges').doc('c1').set({
      title: 'Read together',
      goal: 2,
    });
    await db.collection('users').doc('user4').set({ fcmToken: 'tok999' });
    await db
      .collection('users')
      .doc('user4')
      .collection('seasonChallenges')
      .doc('spring_c1')
      .set({ totalProgress: 2 });
    await db
      .collection('users')
      .doc('user4')
      .collection('notificationPrefs')
      .doc('seasonalChallenge')
      .set({ enabled: false });

    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    function fakeFirestore() {
      return db;
    }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let sent = false;
    Object.defineProperty(admin, 'firestore', {
      value: fakeFirestore,
      configurable: true,
      writable: true,
    });
    Object.defineProperty(admin, 'messaging', {
      value: () => ({
        send: async () => {
          sent = true;
        },
      }),
      configurable: true,
      writable: true,
    });

    try {
      const wrapped = functionsTest.wrap(myFunctions.claimSeasonalChallengeReward);
      await wrapped({
        data: { seasonId: 'spring', challengeId: 'c1' },
        auth: { uid: 'user4' },
      });

      assert.equal(sent, false);
      const rewardDoc = await db
        .collection('users')
        .doc('user4')
        .collection('seasonRewards')
        .doc('spring_c1')
        .get();
      assert.equal(rewardDoc.exists, true);
    } finally {
      Object.defineProperty(admin, 'firestore', {
        value: originalFirestore,
        configurable: true,
        writable: true,
      });
      Object.defineProperty(admin, 'messaging', {
        value: originalMessaging,
        configurable: true,
        writable: true,
      });
    }
  });
});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
