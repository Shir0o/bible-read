const {afterEach, beforeEach, describe, it} = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');

const originalFirestore = admin.firestore;
const originalMessaging = admin.messaging;
const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({options: {projectId: 'demo'}});

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');
const utils = require('../notification-utils');

// A small in-memory Firestore for the two callables: enough for point reads,
// transactions, writes, deletes and the notification document. The real
// behaviour of interest is which documents the callables touch and what they
// return, not Firestore's own semantics.
const FAKE_FIELD_VALUE = {serverTimestamp: () => 'server-ts'};

class FakeFirestore {
  constructor() {
    this.docs = new Map();
    this.autoId = 0;
  }


  collection(name) {
    return new CollectionRef(this, name);
  }

  collectionGroup(name) {
    const db = this;
    return {
      where: (field, op, value) => ({
        get: async () => {
          const matches = [];
          for (const [path, data] of db.docs.entries()) {
            const segments = path.split('/');
            if (!segments.includes(name)) continue;
            if (op === '==' && data[field] !== value) continue;
            matches.push({path, data});
          }
          return {
            docs: matches.map(({path, data}) => {
              const segments = path.split('/');
              const groupId = segments[1];
              return {
                id: segments[segments.length - 1],
                data: () => data,
                ref: {
                  parent: {
                    parent: {id: groupId},
                  },
                },
              };
            }),
          };
        },
      }),
    };
  }

  runTransaction(fn) {
    return fn({
      get: (ref) => ref.get(),
      set: (ref, data) => ref.set(data),
      delete: (ref) => ref.delete(),
    });
  }

  async recursiveDelete(collectionRef) {
    const prefix = `${collectionRef.path}/`;
    for (const path of [...this.docs.keys()]) {
      if (path.startsWith(prefix)) this.docs.delete(path);
    }
  }

  batch() {
    const ops = [];
    return {
      set: (ref, data) => ops.push(() => ref.set(data)),
      delete: (ref) => ops.push(() => ref.delete()),
      commit: async () => {
        for (const op of ops) await op();
      },
    };
  }

  read(path) {
    return this.docs.get(path);
  }

  write(path, data) {
    this.docs.set(path, data);
  }

  delete(path) {
    this.docs.delete(path);
  }
}

FakeFirestore.FieldValue = FAKE_FIELD_VALUE;

class DocRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  collection(name) {
    return new CollectionRef(this.db, `${this.path}/${name}`);
  }

  async get() {
    const data = this.db.read(this.path);
    return {exists: data !== undefined, data: () => data, ref: this};
  }

  async set(data) {
    this.db.write(this.path, {...data});
  }

  async update(data) {
    this.db.write(this.path, {...(this.db.read(this.path) || {}), ...data});
  }

  async delete() {
    this.db.delete(this.path);
  }
}

class CollectionRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  doc(id) {
    const docId = id || `auto-${this.db.autoId++}`;
    return new DocRef(this.db, `${this.path}/${docId}`);
  }

  where(field, op, value) {
    const db = this.db;
    const path = this.path;
    return {
      get: async () => {
        const docs = [];
        const prefix = `${path}/`;
        for (const [docPath, data] of db.docs.entries()) {
          if (!docPath.startsWith(prefix)) continue;
          if (docPath.slice(prefix.length).includes('/')) continue;
          if (op === '==' && data[field] !== value) continue;
          docs.push({
            id: docPath.slice(prefix.length),
            data: () => data,
            ref: new DocRef(db, docPath),
          });
        }
        return {docs, size: docs.length};
      },
    };
  }

  async get() {
    const docs = [];
    const prefix = `${this.path}/`;
    for (const [path, data] of this.db.docs.entries()) {
      if (!path.startsWith(prefix)) continue;
      const rest = path.slice(prefix.length);
      if (rest.includes('/')) continue;
      docs.push({id: rest, data: () => data, ref: new DocRef(this.db, path)});
    }
    return {docs, size: docs.length};
  }
}

function installFakeDb(db) {
  function fakeFirestore() {
    return db;
  }
  fakeFirestore.FieldValue = FakeFirestore.FieldValue;
  Object.defineProperty(admin, 'firestore', {
    value: fakeFirestore,
    configurable: true,
    writable: true,
  });
}

function friendCode(seed = 'ABCDEFGH') {
  return seed;
}

describe('friend callables (ADR-0012)', () => {
  let db;

  beforeEach(() => {
    db = new FakeFirestore();
    installFakeDb(db);
  });

  afterEach(() => {
    utils.invalidateUserCache();
    Object.defineProperty(admin, 'messaging', {
      value: originalMessaging,
      configurable: true,
      writable: true,
    });
    Object.defineProperty(admin, 'firestore', {
      value: originalFirestore,
      configurable: true,
      writable: true,
    });
  });

  it('redeems a code by writing both sides and notifying the owner', async () => {
    const code = friendCode();
    db.write(`friendCodes/${code}`, {ownerUid: 'owner'});
    db.write('users/owner', {name: 'Mei'});
    db.write('users/joiner', {name: 'Jonah'});

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    const result = await wrapped({data: {code}, auth: {uid: 'joiner'}});

    assert.equal(result.status, 'added');
    const ownerSide = db.read('users/owner/friendships/joiner');
    const joinerSide = db.read('users/joiner/friendships/owner');
    assert.equal(ownerSide.uid, 'joiner');
    assert.equal(ownerSide.name, 'Jonah');
    assert.equal(joinerSide.uid, 'owner');
    assert.equal(joinerSide.name, 'Mei');
    assert.equal(joinerSide.since, 'server-ts');

    const notifications = await db
      .collection('users')
      .doc('owner')
      .collection('notifications')
      .get();
    assert.equal(notifications.docs.length, 1);
    assert.equal(notifications.docs[0].data().type, 'friend');
  });

  it('normalises case and separators before resolving', async () => {
    const code = friendCode('7QK4M2PX');
    db.write(`friendCodes/${code}`, {ownerUid: 'owner'});
    db.write('users/owner', {name: 'Mei'});
    db.write('users/joiner', {name: 'Jonah'});

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    const result = await wrapped({
      data: {code: ' 7qk4-m2px '},
      auth: {uid: 'joiner'},
    });

    assert.equal(result.status, 'added');
  });

  it('rejects the reader’s own code', async () => {
    const code = friendCode();
    db.write(`friendCodes/${code}`, {ownerUid: 'owner'});

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    const result = await wrapped({data: {code}, auth: {uid: 'owner'}});

    assert.equal(result.status, 'self');
    assert.equal(db.read('users/owner/friendships/owner'), undefined);
  });

  it('reports unknown, malformed and reset codes as unknown', async () => {
    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);

    assert.equal(
      (await wrapped({data: {code: 'ZZZZZZZZ'}, auth: {uid: 'joiner'}}))
        .status,
      'unknown',
    );
    assert.equal(
      (await wrapped({data: {code: 'SHORT'}, auth: {uid: 'joiner'}})).status,
      'unknown',
    );
    assert.equal(
      (await wrapped({data: {code: 'ABCDEFG0'}, auth: {uid: 'joiner'}}))
        .status,
      'unknown',
    );
  });

  it('reports an existing friendship instead of writing again', async () => {
    const code = friendCode();
    db.write(`friendCodes/${code}`, {ownerUid: 'owner'});
    db.write('users/owner', {name: 'Mei'});
    db.write('users/joiner', {name: 'Jonah'});
    db.write('users/owner/friendships/joiner', {uid: 'joiner'});

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    const result = await wrapped({data: {code}, auth: {uid: 'joiner'}});

    assert.equal(result.status, 'alreadyFriends');
    const notifications = await db
      .collection('users')
      .doc('owner')
      .collection('notifications')
      .get();
    assert.equal(notifications.docs.length, 0);
  });

  it('unfriends for both readers', async () => {
    db.write('users/a/friendships/b', {uid: 'b'});
    db.write('users/b/friendships/a', {uid: 'a'});

    const wrapped = functionsTest.wrap(myFunctions.unfriend);
    const result = await wrapped({
      data: {friendUid: 'b'},
      auth: {uid: 'a'},
    });

    assert.equal(result.success, true);
    assert.equal(db.read('users/a/friendships/b'), undefined);
    assert.equal(db.read('users/b/friendships/a'), undefined);
  });

  it('rejects unfriending yourself', async () => {
    const wrapped = functionsTest.wrap(myFunctions.unfriend);
    await assert.rejects(
      wrapped({data: {friendUid: 'a'}, auth: {uid: 'a'}}),
      /friendUid is required/,
    );
  });

  it('pushes “added you as a friend” to the owner, honouring the preference',
      async () => {
    const code = friendCode();
    db.write(`friendCodes/${code}`, {ownerUid: 'owner'});
    db.write('users/owner', {name: 'Mei', fcmToken: 'owner-token'});
    db.write('users/joiner', {name: 'Jonah'});
    const sent = [];
    Object.defineProperty(admin, 'messaging', {
      value: () => ({
        send: async (message) => {
          sent.push(message);
          return 'id';
        },
      }),
      configurable: true,
      writable: true,
    });

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    await wrapped({data: {code}, auth: {uid: 'joiner'}});

    assert.equal(sent.length, 1);
    assert.equal(sent[0].token, 'owner-token');
    assert.match(sent[0].notification.body, /Jonah added you as a friend/);
    assert.equal(sent[0].data.type, 'friend');
  });

  it('respects a disabled “new friends” preference', async () => {
    const code = friendCode();
    db.write(`friendCodes/${code}`, {ownerUid: 'owner'});
    db.write('users/owner', {name: 'Mei', fcmToken: 'owner-token'});
    db.write('users/joiner', {name: 'Jonah'});
    db.write('users/owner/notificationPrefs/friend', {enabled: false});
    let sends = 0;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({send: async () => { sends += 1; }}),
      configurable: true,
      writable: true,
    });

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    const result = await wrapped({data: {code}, auth: {uid: 'joiner'}});

    assert.equal(result.status, 'added');
    assert.equal(sends, 0);
  });

  it('sends no notification for a failed redemption', async () => {
    let sends = 0;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({send: async () => { sends += 1; }}),
      configurable: true,
      writable: true,
    });

    const wrapped = functionsTest.wrap(myFunctions.redeemFriendCode);
    await wrapped({data: {code: 'ZZZZZZZZ'}, auth: {uid: 'joiner'}});

    assert.equal(sends, 0);
  });

  it('deleteFriendData removes the code, both friendship sides and the source',
      async () => {
    db.write('friendCodes/ABCDEFGH', {ownerUid: 'owner'});
    db.write('friendCodes/OTHER234', {ownerUid: 'other'});
    db.write('users/owner/private/friendCode', {code: 'ABCDEFGH'});
    db.write('users/owner/friendships/f1', {uid: 'f1'});
    db.write('users/f1/friendships/owner', {uid: 'owner'});
    db.write('users/owner/friendships/f2', {uid: 'f2'});
    db.write('users/f2/friendships/owner', {uid: 'owner'});
    db.write('users/owner/friend_feed/2026-10-18/entries/owner', {
      uid: 'owner',
    });
    db.write('users/owner/friend_badge_log/owner_days_7', {uid: 'owner'});

    const wrapped = functionsTest.wrap(myFunctions.deleteFriendData);
    const result = await wrapped({data: {}, auth: {uid: 'owner'}});

    assert.equal(result.success, true);
    assert.equal(result.friends, 2);
    assert.equal(db.read('friendCodes/ABCDEFGH'), undefined);
    assert.ok(db.read('friendCodes/OTHER234'), 'other codes are untouched');
    assert.equal(db.read('users/owner/friendships/f1'), undefined);
    assert.equal(db.read('users/f1/friendships/owner'), undefined);
    assert.equal(db.read('users/owner/friendships/f2'), undefined);
    assert.equal(db.read('users/f2/friendships/owner'), undefined);
    assert.equal(
      db.read('users/owner/friend_feed/2026-10-18/entries/owner'),
      undefined,
    );
    assert.equal(db.read('users/owner/friend_badge_log/owner_days_7'), undefined);
    assert.equal(db.read('users/owner/private/friendCode'), undefined);
  });
});
