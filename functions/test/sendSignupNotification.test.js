const {test} = require('node:test');
const assert = require('node:assert');
const admin = require('firebase-admin');

// Stub initialization before loading the functions module so requiring
// `index.js` does not attempt to load real credentials.
const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');

process.env.ADMIN_UID = 'admin1';

test('sendSignupNotification builds payload', async () => {
  const originalFirestore = admin.firestore;
  Object.defineProperty(admin, 'firestore', {
    value: () => ({
      collection: () => ({
        doc: () => ({
          get: async () => ({ data: () => ({ fcmToken: 'token123' }) })
        })
      })
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

  const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
  await wrapped({ displayName: 'Test User', uid: 'u1' });

  assert.equal(captured.token, 'token123');
  assert.match(captured.notification.body, /Test User/);

  Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
