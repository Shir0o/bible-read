const { describe, it, afterEach } = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');

const utils = require('../notification-utils');

const originalFirestore = admin.firestore;
const originalMessaging = admin.messaging;

afterEach(() => {
  Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  utils.invalidateUserCache();
});

describe('notification-utils', () => {
  it('getFcmToken returns token', async () => {
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 'abc' }) }) }) })
      }),
      writable: true,
      configurable: true,
    });
    const token = await utils.getFcmToken('u1');
    assert.equal(token, 'abc');
  });

  it('caches FCM tokens', async () => {
    let calls = 0;
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({ doc: () => ({ get: async () => { calls++; return { data: () => ({ fcmToken: 'abc' }) }; } }) })
      }),
      writable: true,
      configurable: true,
    });
    const t1 = await utils.getFcmToken('u1');
    assert.equal(t1, 'abc');
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({ doc: () => ({ get: async () => { calls++; return { data: () => ({ fcmToken: 'def' }) }; } }) })
      }),
      writable: true,
      configurable: true,
    });
    const t2 = await utils.getFcmToken('u1');
    assert.equal(t2, 'abc');
    assert.equal(calls, 1);
  });

  it('invalidateUserCache refreshes token', async () => {
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 'abc' }) }) }) })
      }),
      writable: true,
      configurable: true,
    });
    await utils.getFcmToken('u1');
    utils.invalidateUserCache('u1');
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({ doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 'def' }) }) }) })
      }),
      writable: true,
      configurable: true,
    });
    const t = await utils.getFcmToken('u1');
    assert.equal(t, 'def');
  });

  it('isNotificationEnabled respects pref', async () => {
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({
            collection: () => ({
              doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: false }) }) })
            })
          })
        })
      }),
      writable: true,
      configurable: true,
    });
    const enabled = await utils.isNotificationEnabled('u1', 'like');
    assert.equal(enabled, false);
  });

  it('caches notification prefs', async () => {
    let calls = 0;
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({
            collection: () => ({
              doc: () => ({ get: async () => { calls++; return { exists: false, data: () => ({}) }; } })
            })
          })
        })
      }),
      writable: true,
      configurable: true,
    });
    const first = await utils.isNotificationEnabled('u1', 'like');
    assert.equal(first, true);
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({
            collection: () => ({
              doc: () => ({ get: async () => { calls++; return { exists: true, data: () => ({ enabled: false }) }; } })
            })
          })
        })
      }),
      writable: true,
      configurable: true,
    });
    const second = await utils.isNotificationEnabled('u1', 'like');
    assert.equal(second, true);
    assert.equal(calls, 1);
  });

  it('invalidateUserCache refreshes prefs', async () => {
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({
            collection: () => ({
              doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: false }) }) })
            })
          })
        })
      }),
      writable: true,
      configurable: true,
    });
    await utils.isNotificationEnabled('u1', 'like');
    utils.invalidateUserCache('u1');
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({
            collection: () => ({
              doc: () => ({ get: async () => ({ exists: true, data: () => ({ enabled: true }) }) })
            })
          })
        })
      }),
      writable: true,
      configurable: true,
    });
    const enabled = await utils.isNotificationEnabled('u1', 'like');
    assert.equal(enabled, true);
  });

  it('sendNotification forwards message', async () => {
    let captured;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async (msg) => { captured = msg; return 'id1'; } }),
      writable: true,
      configurable: true,
    });
    const id = await utils.sendNotification('tok', {
      title: 't',
      body: 'b',
      data: { type: 'sample', fromUid: 123, skip: undefined },
    });
    assert.equal(id, 'id1');
    assert.equal(captured.token, 'tok');
    assert.equal(captured.notification.title, 't');
    assert.deepEqual(captured.data, { type: 'sample', fromUid: '123' });
  });
});
