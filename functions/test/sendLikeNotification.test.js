const {test, after} = require('node:test');
const assert = require('node:assert');
const admin = require('firebase-admin');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');

process.env.NODE_ENV = 'test';

test('sendLikeNotification sends payload when enabled', async () => {
  const originalFirestore = admin.firestore;
  Object.defineProperty(admin, 'firestore', {
    value: () => ({
      collection: () => ({
        doc: () => ({
          get: async () => ({ data: () => ({ fcmToken: 'token456' }) }),
          collection: () => ({
            doc: () => ({ get: async () => ({ exists: false }) })
          }),
        }),
      }),
    }),
    configurable: true,
    writable: true,
  });

  let captured;
  const originalMessaging = admin.messaging;
  Object.defineProperty(admin, 'messaging', {
    value: () => ({
      send: async (msg) => { captured = msg; }
    }),
    configurable: true,
    writable: true,
  });

  const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
  await wrapped({ data: { ownerUid: 'u2', likerName: 'Alice' }, auth: { uid: 'u1' } });

  assert.equal(captured.token, 'token456');
  assert.match(captured.notification.body, /Alice/);

  Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
});


test('sendLikeNotification exits when no token', async () => {
  const originalFirestore = admin.firestore;
  Object.defineProperty(admin, 'firestore', {
    value: () => ({
      collection: () => ({
        doc: () => ({
          get: async () => ({ data: () => ({}) }),
          collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }),
        })
      })
    }),
    configurable: true,
    writable: true,
  });

  let sent = false;
  const originalMessaging = admin.messaging;
  Object.defineProperty(admin, 'messaging', {
    value: () => ({
      send: async () => { sent = true; }
    }),
    configurable: true,
    writable: true,
  });

  const wrapped = functionsTest.wrap(myFunctions.sendLikeNotification);
  await wrapped({ data: { ownerUid: 'u2', likerName: 'Alice' }, auth: { uid: 'u1' } });

  assert.equal(sent, false);

  Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
