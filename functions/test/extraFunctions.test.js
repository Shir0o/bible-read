const {after, describe, it} = require('mocha');
const assert = require('node:assert');
const sinon = require('sinon');
const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');
const utils = require('../notification-utils');

class FakeDoc {
  constructor(id, data = undefined, parent = null) {
    this.id = id;
    this._data = data;
    this.parent = parent;
    this.exists = data !== undefined;
    this._collections = new Map();
  }

  data() {
    return this._data;
  }

  get path() {
    if (!this.parent) {
      return this.id;
    }
    const parentDoc = this.parent.parentDoc;
    const parentPath = parentDoc ? parentDoc.path : this.parent.name;
    return `${parentPath}/${this.id}`;
  }

  async get() {
    return { exists: this.exists, data: () => this._data, ref: this, id: this.id };
  }

  async set(data, options) {
    if (options?.merge) {
      this._data = { ...(this._data || {}), ...data };
    } else {
      this._data = data;
    }
    this.exists = true;
  }

  async update(data) {
    this._data = { ...(this._data || {}), ...data };
    this.exists = true;
  }


  collection(name) {
    if (!this._collections.has(name)) {
      this._collections.set(name, new FakeCollection(name, this));
    }
    return this._collections.get(name);
  }
}

class FakeQuerySnapshot {
  constructor(documents) {
    this.docs = documents.map((doc) => ({
      id: doc.id,
      data: () => doc.data(),
      ref: doc,
      exists: doc.exists,
    }));
    this.empty = this.docs.length === 0;
  }

  forEach(cb) {
    this.docs.forEach(cb);
  }
}

class FakeCollection {
  constructor(name, parentDoc = null) {
    this.name = name;
    this.parentDoc = parentDoc;
    this.docs = new Map();
  }

  doc(id) {
    if (!this.docs.has(id)) {
      this.docs.set(id, new FakeDoc(id, undefined, this));
    }
    return this.docs.get(id);
  }

  where(field, op, value) {
    const docs = Array.from(this.docs.values()).filter((doc) => {
      const data = doc.data() || {};
      return op === '==' ? data[field] === value : false;
    });
    return {
      get: async () => new FakeQuerySnapshot(docs),
    };
  }

  async get() {
    const docs = Array.from(this.docs.values());
    return new FakeQuerySnapshot(docs);
  }
}

class FakeFirestore {
  constructor() {
    this.collections = new Map();
  }

  async getAll(...refs) { return Promise.all(refs.map(ref => ref.get())); }
  batch() { return { set: (ref, data, options) => ref.set(data, options), update: (ref, data) => ref.update(data), delete: (ref) => {}, commit: async () => {} }; }

  collection(name) {
    if (!this.collections.has(name)) {
      this.collections.set(name, new FakeCollection(name));
    }
    return this.collections.get(name);
  }
}

process.env.NODE_ENV = 'test';
process.env.ADMIN_UID = 'admin1';

describe('other cloud functions', () => {
  afterEach(() => utils.invalidateUserCache());
  it('sendCommentNotification sends message', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({
            doc: () => ({ get: async () => ({ exists: false }) })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokC' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let sent;
    Object.defineProperty(admin, 'firestore', {value: fakeFirestore, configurable: true, writable: true});
    Object.defineProperty(admin, 'messaging', {value: () => ({ send: async (msg) => { sent = msg; } }), configurable: true, writable: true});

    const wrapped = functionsTest.wrap(myFunctions.sendCommentNotification);
    await wrapped({ data: { ownerUid: 'u1', commenterName: 'Bob' }, auth: { uid: 'u2' } });

    assert.equal(sent.token, 'tokC');
    assert.match(sent.notification.body, /Bob/);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendCommentNotification handles messaging error', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }),
          get: async () => ({ data: () => ({ fcmToken: 'tokErr' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async () => { throw new Error('boom'); } }),
      configurable: true,
      writable: true
    });

    const wrapped = functionsTest.wrap(myFunctions.sendCommentNotification);
    try {
      await wrapped({ data: { ownerUid: 'u1', commenterName: 'Bob' }, auth: { uid: 'u2' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'internal');
      assert.match(err.message, /Failed to send comment notification/);
    }

    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendNudgeNotification logs and sends', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    let logSet = false;
    const fakeDb = {
      collection: (name) => ({
        doc: () => ({
          collection: (sub) => ({
            doc: () => ({
              get: async () => ({ exists: false }),
              set: async () => { logSet = true; }
            })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokN' }) })
        })
      }),
      runTransaction: async (fn) => fn({})
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let captured;
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (msg) => { captured = msg; } }), configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    const res = await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
    assert.equal(res.alreadySent, false);
    assert.equal(captured.token, 'tokN');
    assert.ok(logSet);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendNudgeNotification handles messaging error', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    let logSet = false;
    const fakeDb = {
      collection: (name) => ({
        doc: () => ({
          collection: () => ({
            doc: () => ({
              get: async () => ({ exists: false }),
              set: async () => { logSet = true; }
            })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokN' }) })
        })
      }),
      runTransaction: async (fn) => fn({})
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async () => { throw new Error('fail'); } }),
      configurable: true,
      writable: true
    });

    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    try {
      await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'internal');
      assert.match(err.message, /Failed to send nudge notification/);
    }

    assert.ok(!logSet); // should fail before log set
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('deleteFriendRequestPair removes docs', async () => {
    const originalFirestore = admin.firestore;
    let deletedA = false, deletedB = false;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'friendRequestsReceived') {
              return { doc: () => ({ delete: async () => { deletedA = true; } }) };
            }
            if (sub === 'friendRequestsSent') {
              return { doc: () => ({ delete: async () => { deletedB = true; } }) };
            }
            if (sub === 'notifications') {
              return {
                where: () => ({ where: () => ({ get: async () => ({ forEach: () => {} }) }) })
              };
            }
          }
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', {value: fakeFirestore, configurable: true, writable: true});

    const wrapped = functionsTest.wrap(myFunctions.deleteFriendRequestPair);
    const res = await wrapped({ data: { fromUid: 'u1', toUid: 'u2' }, auth: { uid: 'u2' } });
    assert.equal(res.success, true);
    assert.ok(deletedA && deletedB);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('deleteFriendRequestPair handles deletion error', async () => {
    const originalFirestore = admin.firestore;
    const stderrStub = sinon.stub(process.stderr, 'write');
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'friendRequestsReceived' || sub === 'friendRequestsSent') {
              return { doc: () => ({ delete: async () => { throw new Error('nope'); } }) };
            }
            if (sub === 'notifications') {
              return {
                where: () => ({ where: () => ({ get: async () => ({ forEach: () => {} }) }) })
              };
            }
          }
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.deleteFriendRequestPair);
    try {
      await wrapped({ data: { fromUid: 'u1', toUid: 'u2' }, auth: { uid: 'u2' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'internal');
    }
    assert.ok(stderrStub.called);
    assert.match(stderrStub.getCall(0).args[0], /Failed to delete friend request pair/);

    stderrStub.restore();
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('acceptFriendRequest commits batch', async () => {
    const originalFirestore = admin.firestore;
    let commit = false;
    const fakeBatch = {
      set: () => {},
      delete: () => {},
      commit: async () => { commit = true; }
    };
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'notifications') {
              return {
                where: () => ({ where: () => ({ get: async () => ({ forEach: () => {} }) }) })
              };
            }
            return { doc: () => ({}) };
          }
        })
      }),
      batch: () => fakeBatch
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', {value: fakeFirestore, configurable: true, writable: true});

    const wrapped = functionsTest.wrap(myFunctions.acceptFriendRequest);
    const res = await wrapped({ data: { fromUid: 'a', toUid: 'b', fromName: 'A', toName: 'B' }, auth: { uid: 'b' } });
    assert.equal(res.success, true);
    assert.ok(commit);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('acceptFriendRequest handles commit error', async () => {
    const originalFirestore = admin.firestore;
    const stderrStub = sinon.stub(process.stderr, 'write');
    const fakeBatch = {
      set: () => {},
      delete: () => {},
      commit: async () => { throw new Error('boom'); }
    };
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'notifications') {
              return {
                where: () => ({ where: () => ({ get: async () => ({ forEach: () => {} }) }) })
              };
            }
            return { doc: () => ({}) };
          }
        })
      }),
      batch: () => fakeBatch
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.acceptFriendRequest);
    try {
      await wrapped({ data: { fromUid: 'a', toUid: 'b', fromName: 'A', toName: 'B' }, auth: { uid: 'b' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'internal');
    }
    assert.ok(stderrStub.called);
    assert.match(stderrStub.getCall(0).args[0], /Failed to accept friend request/);

    stderrStub.restore();
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('markFirstReader first-time', async () => {
    const originalFirestore = admin.firestore;
    let created = false, setFlag = false;
    const rewardRef = {};
    const entryDocRef = {};
    const entriesQuery = {};
    const entriesRef = {
      orderBy: () => ({ limit: () => entriesQuery }),
      doc: () => entryDocRef,
    };
    const fakeDb = {
      collection: (name) => {
        if (name === 'daily_rewards') return { doc: () => rewardRef };
        if (name === 'read_logs') return { doc: () => ({ collection: () => entriesRef }) };
        return { doc: () => ({}) };
      },
      runTransaction: async (fn) => {
        const t = {
          get: async (ref) => {
            if (ref === rewardRef) return { exists: false };
            if (ref === entriesQuery) return { empty: false, docs: [{ id: 'u1' }] };
            return {};
          },
          create: () => { created = true; },
          set: () => { setFlag = true; },
        };
        return fn(t);
      },
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.markFirstReader);
    const res = await wrapped({ data: { dateKey: '2024-01-01' }, auth: { uid: 'u1' } });
    assert.equal(res.first, true);
    assert.ok(created && setFlag);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });
});

  it('sendCommentNotification returns when disabled', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({
            doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: false }) }) })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokC' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let sent = false;
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => { sent = true; } }), configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.sendCommentNotification);
    const res = await wrapped({ data: { ownerUid: 'u1', commenterName: 'Bob' }, auth: { uid: 'u2' } });
    assert.equal(res, undefined);
    assert.equal(sent, false);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('deleteFriendRequestPair permission denied', async () => {
    const originalFirestore = admin.firestore;
    function fakeFirestore() { return {}; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.deleteFriendRequestPair);
    try {
      await wrapped({ data: { fromUid: 'u1', toUid: 'u2' }, auth: { uid: 'u1' } });
      assert.fail('should have thrown');
    } catch (err) {
      assert.equal(err.code, 'permission-denied');
    }
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('markFirstReader already taken', async () => {
    const originalFirestore = admin.firestore;
    const rewardRef = {};
    const fakeDb = {
      collection: (name) => {
        if (name === 'daily_rewards') return { doc: () => rewardRef };
        if (name === 'read_logs') return { doc: () => ({ collection: () => ({}) }) };
        return { doc: () => ({}) };
      },
      runTransaction: async (fn) => {
        const t = {
          get: async () => ({ exists: true, data: () => ({ uid: 'u0' }) })
        };
        return fn(t);
      },
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.markFirstReader);
    const res = await wrapped({ data: { dateKey: 'd1' }, auth: { uid: 'u1' } });
    assert.equal(res.first, false);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('markFirstReader handles transaction error', async () => {
    const originalFirestore = admin.firestore;
    const rewardRef = { id: 'reward' };
    const logRef = { id: 'log' };
    const fakeDb = {
      collection: (name) => {
        if (name === 'daily_rewards') return { doc: () => rewardRef };
        if (name === 'read_logs') return { doc: () => ({ collection: () => ({ doc: () => logRef }) }) };
        return { doc: () => ({}) };
      },
      runTransaction: async () => { throw new Error('boom'); }
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.markFirstReader);
    let message;
    try {
      await wrapped({ data: { dateKey: 'd2' }, auth: { uid: 'u1' } });
      assert.fail('expected error');
    } catch (err) {
      message = err.message;
      assert.equal(err.code, 'internal');
    }
    assert.match(message, /Failed to mark first reader/);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('markFirstReader chooses earliest timestamp regardless of call order', async () => {
    const originalFirestore = admin.firestore;
    const rewardRef = {};
    const entriesQuery = {};
    const entriesRef = {
      orderBy: () => ({ limit: () => entriesQuery }),
      doc: (uid) => ({ id: uid }),
    };
    let rewardUid;
    const firstFlags = {};
    const fakeDb = {
      collection: (name) => {
        if (name === 'daily_rewards') return { doc: () => rewardRef };
        if (name === 'read_logs')
          return { doc: () => ({ collection: () => entriesRef }) };
        return { doc: () => ({}) };
      },
      runTransaction: async (fn) => {
        const t = {
          get: async (ref) => {
            if (ref === rewardRef) {
              return rewardUid
                ? { exists: true, data: () => ({ uid: rewardUid }) }
                : { exists: false };
            }
            if (ref === entriesQuery) {
              return {
                empty: false,
                docs: [
                  { id: 'u1', data: () => ({ timestamp: 1 }) },
                  { id: 'u2', data: () => ({ timestamp: 2 }) },
                ],
              };
            }
            return {};
          },
          create: (ref, data) => {
            if (ref === rewardRef) {
              rewardUid = data.uid;
            }
          },
          set: (ref, data) => {
            firstFlags[ref.id] = data.firstReader;
          },
        };
        return fn(t);
      },
    };
    function fakeFirestore() {
      return fakeDb;
    }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', {
      value: fakeFirestore,
      configurable: true,
      writable: true,
    });

    const wrapped = functionsTest.wrap(myFunctions.markFirstReader);
    const res2 = await wrapped({ data: { dateKey: 'd1' }, auth: { uid: 'u2' } });
    const res1 = await wrapped({ data: { dateKey: 'd1' }, auth: { uid: 'u1' } });
    assert.equal(res2.first, false);
    assert.equal(res1.first, true);
    assert.deepEqual(firstFlags, { u1: true });
    assert.equal(rewardUid, 'u1');
    Object.defineProperty(admin, 'firestore', {
      value: originalFirestore,
      writable: true,
    });
  });

  it('sendLikeNotification invalid data', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
    try {
      await wrapped({ data: { ownerUid: 'u1' }, auth: { uid: 'u2' } });
      assert.fail('expected error');
    } catch (err) {
      assert.match(err.message, /invalid-argument/);
    }
  });

  it('sendNudgeNotification pref disabled', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    let setLog = false;
    const fakeDb = {
      collection: (name) => ({
        doc: () => ({
          collection: () => ({
            doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: false }) }), set: async () => { setLog = true; } })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tok' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => { throw new Error('should not send'); } }), configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    const res = await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
    assert.equal(res.alreadySent, false);
    assert.ok(setLog);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendNudgeNotification already nudged today', async () => {
    const originalFirestore = admin.firestore;
    const fakeDb = {
      collection: (name) => ({
        doc: () => ({
          collection: (sub) => ({
            doc: () => ({
              get: async () => ({ exists: false }),
              set: async () => {}
            })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokN' }) })
        })
      })
    };
    const logDoc = { exists: true, data: () => ({ timestamp: { toDate: () => new Date() } }) };
    fakeDb.collection = (name) => {
      if (name === 'users') return { doc: () => ({ collection: (sub) => ({ doc: () => ({ get: async () => (sub === 'nudges' ? logDoc : { exists: false, data: () => ({ enabled: true }) }), set: async () => {} }) }), get: async () => ({ data: () => ({ fcmToken: 'tokN' }) }) }) };
      return { doc: () => ({}) };
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let captured;
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (m) => { captured = m; } }), configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    const res = await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
    assert.equal(res.alreadySent, true);
    assert.equal(captured, undefined);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => {} }), writable: true });
  });

  it('sendNudgeNotification skips if already read today', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    let sent = false;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => ({
            doc: () => ({
              get: async () => {
                if (sub === 'notificationPrefs') {
                  return { exists: false };
                }
                if (sub === 'nudges') {
                  return { exists: false };
                }
                if (sub === 'reading') {
                  return { exists: true, data: () => ({ read: true }) };
                }
                return { exists: false };
              },
              set: async () => { sent = true; }
            })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokR' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let captured;
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (m) => { captured = m; } }), configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    const res = await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
    assert.equal(res.alreadyRead, true);
    assert.equal(captured, undefined);
    assert.equal(sent, false);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendNudgeNotification timestamp object without toDate', async () => {
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    let logSet = false;
    const fakeDb = {
      collection: (name) => ({
        doc: () => ({
          collection: (sub) => ({
            doc: () => ({
              get: async () => (sub === 'nudges' ? { exists: true, data: () => ({ timestamp: {} }) } : { exists: false }),
              set: async () => { logSet = true; }
            })
          }),
          get: async () => ({ data: () => ({ fcmToken: 'tokNA' }) })
        })
      }),
      runTransaction: async (fn) => fn({})
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let captured;
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (m) => { captured = m; } }), configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    const res = await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
    assert.equal(res.alreadySent, false);
    assert.equal(captured.token, 'tokNA');
    assert.ok(logSet);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendLikeNotification missing data', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
    try {
      await wrapped({ data: { ownerUid: 'u1' }, auth: { uid: 'u2' } });
      assert.fail('expected error');
    } catch (err) {
      assert.match(err.message, /invalid-argument/);
    }
  });

  it('sendCommentNotification unauthenticated', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendCommentNotification);
    try {
      await wrapped({ data: { ownerUid: 'u1', commenterName: 'Bob' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'unauthenticated');
    }
  });

  it('sendNudgeNotification missing params', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    try {
      await wrapped({ data: { toUid: 'u2' }, auth: { uid: 'u1' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'invalid-argument');
    }
  });

  it('deleteFriendRequestPair invalid args', async () => {
    const wrapped = functionsTest.wrap(myFunctions.deleteFriendRequestPair);
    try {
      await wrapped({ data: { toUid: 'u2' }, auth: { uid: 'u2' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'invalid-argument');
    }
  });

  it('acceptFriendRequest not receiver', async () => {
    const wrapped = functionsTest.wrap(myFunctions.acceptFriendRequest);
    try {
      await wrapped({ data: { fromUid: 'a', toUid: 'b', fromName: 'A', toName: 'B' }, auth: { uid: 'c' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'permission-denied');
    }
  });

  it('markFirstReader missing dateKey', async () => {
    const wrapped = functionsTest.wrap(myFunctions.markFirstReader);
    try {
      await wrapped({ data: {}, auth: { uid: 'u1' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'invalid-argument');
    }
  });

  it('sendSignupNotification without ADMIN_UID', async () => {
    const originalAdminUid = process.env.ADMIN_UID;
    delete process.env.ADMIN_UID;
    let warned = false;
    const originalFirestore = admin.firestore;
    const originalMessaging = admin.messaging;
    function fakeFirestore() { return { collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 't' }) }) }) }) }; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => { warned = true; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ displayName: 'x', uid: 'u1' });
    assert.equal(warned, false);
    process.env.ADMIN_UID = originalAdminUid;
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendLikeNotification auth required', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
    try {
      await wrapped({ data: { ownerUid: 'u1', likerName: 'Bob' } });
      assert.fail('expected error');
    } catch (err) {
      assert.match(err.message, /unauthenticated/);
    }
  });

  it('sendLikeNotification disabled pref', async () => {
    const originalFirestore = admin.firestore;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({ doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: false }) }) }) }),
          get: async () => ({ data: () => ({ fcmToken: 't' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
    const res = await wrapped({ data: { ownerUid: 'u1', likerName: 'Bob' }, auth: { uid: 'u2' } });
    assert.equal(res, undefined);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('sendCommentNotification invalid args', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendCommentNotification);
    try {
      await wrapped({ data: { ownerUid: 'u1' }, auth: { uid: 'u2' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'invalid-argument');
    }
  });

  it('sendCommentNotification no token', async () => {
    const originalFirestore = admin.firestore;
    let sent = false;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({ doc: () => ({ get: async () => ({ exists: false }), set: async () => {} }) }),
          get: async () => ({ data: () => ({}) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => { sent = true; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendCommentNotification);
    await wrapped({ data: { ownerUid: 'u1', commenterName: 'Bob' }, auth: { uid: 'u2' } });
    assert.equal(sent, false);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('sendNudgeNotification unauthenticated', async () => {
    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    try {
      await wrapped({ data: { toUid: 'u2', fromName: 'Sue' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'unauthenticated');
    }
  });

  it('sendNudgeNotification no token', async () => {
    const originalFirestore = admin.firestore;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({ doc: () => ({ get: async () => ({ exists: false }), set: async () => {} }) }),
          get: async () => ({ data: () => ({}) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    let sent = false;
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => { sent = true; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendNudgeNotification);
    const res = await wrapped({ data: { toUid: 'u2', fromName: 'Sue' }, auth: { uid: 'u1' } });
    assert.equal(res.alreadySent, false);
    assert.equal(sent, false);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('deleteFriendRequestPair unauthenticated', async () => {
    const wrapped = functionsTest.wrap(myFunctions.deleteFriendRequestPair);
    try {
      await wrapped({ data: { fromUid: 'a', toUid: 'b' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'unauthenticated');
    }
  });

  it('acceptFriendRequest invalid args', async () => {
    const wrapped = functionsTest.wrap(myFunctions.acceptFriendRequest);
    try {
      await wrapped({ data: { fromUid: 'a' }, auth: { uid: 'b' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'invalid-argument');
    }
  });

  it('acceptFriendRequest unauthenticated', async () => {
    const wrapped = functionsTest.wrap(myFunctions.acceptFriendRequest);
    try {
      await wrapped({ data: { fromUid: 'a', toUid: 'b', fromName: 'A', toName: 'B' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'unauthenticated');
    }
  });

  it('deleteFriendRequestPair removes notification', async () => {
    const originalFirestore = admin.firestore;
    let receivedDeleted = false;
    let sentDeleted = false;
    let notifDeleted = false;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'friendRequestsReceived') {
              return { doc: () => ({ delete: async () => { receivedDeleted = true; } }) };
            }
            if (sub === 'friendRequestsSent') {
              return { doc: () => ({ delete: async () => { sentDeleted = true; } }) };
            }
            if (sub === 'notifications') {
              return {
                where: () => ({
                  where: () => ({
                    get: async () => ({
                      forEach: (cb) => cb({ ref: { delete: async () => { notifDeleted = true; } } })
                    })
                  })
                })
              };
            }
          }
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.deleteFriendRequestPair);
    await wrapped({ data: { fromUid: 'a', toUid: 'b' }, auth: { uid: 'b' } });
    assert.equal(receivedDeleted, true);
    assert.equal(sentDeleted, true);
    assert.equal(notifDeleted, true);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('removeFriendRequestNotification prunes notifications on delete', async () => {
    const originalFirestore = admin.firestore;
    let notifDeleted = false;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'notifications') {
              return {
                where: () => ({
                  where: () => ({
                    get: async () => ({
                      forEach: (cb) => cb({ ref: { delete: async () => { notifDeleted = true; } } })
                    })
                  })
                })
              };
            }
            return {};
          }
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.removeFriendRequestNotification);
    await wrapped({}, { params: { uid: 'u2', fromUid: 'u1' } });
    assert.equal(notifDeleted, true);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('acceptFriendRequest marks notification read', async () => {
    const originalFirestore = admin.firestore;
    const notifRef = { id: 'n1' };
    let updated = false;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: (sub) => {
            if (sub === 'friends') {
              return { doc: () => ({}) };
            }
            if (sub === 'friendRequestsSent' || sub === 'friendRequestsReceived') {
              return { doc: () => ({}) };
            }
            if (sub === 'notifications') {
              return {
                where: () => ({
                  where: () => ({
                    get: async () => ({ forEach: (cb) => cb({ ref: notifRef }) })
                  })
                })
              };
            }
          }
        })
      }),
      batch: () => ({
        set: () => {},
        delete: () => {},
        update: (ref, data) => {
          if (ref === notifRef && data.read === true) {
            updated = true;
          }
        },
        commit: async () => {}
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.acceptFriendRequest);
    await wrapped({ data: { fromUid: 'a', toUid: 'b', fromName: 'A', toName: 'B' }, auth: { uid: 'b' } });
    assert.equal(updated, true);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('markFirstReader unauthenticated', async () => {
    const wrapped = functionsTest.wrap(myFunctions.markFirstReader);
    try {
      await wrapped({ data: { dateKey: 'd1' } });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'unauthenticated');
    }
  });

  it('sendSignupNotification missing token', async () => {
    const originalFirestore = admin.firestore;
    const fakeDb = { collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({}) }) }) }) };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    let warned = false;
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async () => { warned = true; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ displayName: 'User', uid: 'u1' });
    assert.equal(warned, false);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

  it('sendSignupNotification falls back to email', async () => {
    const originalFirestore = admin.firestore;
    const fakeDb = { collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 'tokEmail' }) }) }) }) };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    let captured;
    const originalMessaging = admin.messaging;
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (msg) => { captured = msg; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ email: 'a@b.c', uid: 'u1' });
    assert.match(captured.notification.body, /a@b.c/);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendSignupNotification uses default name', async () => {
    const originalFirestore = admin.firestore;
    const fakeDb = { collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 'tokDef' }) }) }) }) };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    let captured;
    const originalMessaging = admin.messaging;
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (msg) => { captured = msg; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ uid: 'u3' });
    assert.match(captured.notification.body, /New user/);
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('sendLikeNotification in production', async () => {
    const env = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    const originalFirestore = admin.firestore;
    const fakeDb = {
      collection: () => ({
        doc: () => ({
          collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }),
          get: async () => ({ data: () => ({ fcmToken: 'tokP' }) })
        })
      })
    };
    function fakeFirestore() { return fakeDb; }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    let sent;
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });
    Object.defineProperty(admin, 'messaging', { value: () => ({ send: async (m) => { sent = m; } }), configurable: true, writable: true });
    const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
    await wrapped({ data: { ownerUid: 'u1', likerName: 'Bob' }, auth: { uid: 'u2' } });
    assert.equal(sent.token, 'tokP');
    process.env.NODE_ENV = env;
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
