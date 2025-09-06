const { describe, it, afterEach } = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');

const utils = require('../notification-utils');

const originalFirestore = admin.firestore;
const originalMessaging = admin.messaging;

afterEach(() => {
  Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
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

  it('sendNotification forwards message', async () => {
    let captured;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async (msg) => { captured = msg; return 'id1'; } }),
      writable: true,
      configurable: true,
    });
    const id = await utils.sendNotification('tok', { title: 't', body: 'b' });
    assert.equal(id, 'id1');
    assert.equal(captured.token, 'tok');
    assert.equal(captured.notification.title, 't');
  });
});
