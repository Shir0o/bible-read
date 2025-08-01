const {after, describe, it} = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions/v1');

// Stub initialization before loading the functions module so requiring
// `index.js` does not attempt to load real credentials.
const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');

process.env.ADMIN_UID = 'admin1';

describe('sendSignupNotification', () => {

  it('builds payload', async () => {
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
  });

  it('logs error when send fails', async () => {
    const originalFirestore = admin.firestore;
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({ get: async () => ({ data: () => ({ fcmToken: 'token123' }) }) })
        })
      }),
      configurable: true,
      writable: true,
    });

    const originalMessaging = admin.messaging;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async () => { throw new Error('fail'); } }),
      configurable: true,
      writable: true,
    });

    let logged = false;
    const originalLogger = functions.logger.error;
    functions.logger.error = () => { logged = true; };

    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ displayName: 'Test User', uid: 'u1' });

    assert.ok(logged);

    functions.logger.error = originalLogger;
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
  });

  it('warns when ADMIN_UID is not set', async () => {
    const origEnv = process.env.ADMIN_UID;
    delete process.env.ADMIN_UID;

    let warned;
    const originalWarn = functions.logger.warn;
    functions.logger.warn = (msg) => { warned = msg; };

    let sent = false;
    const originalMessaging = admin.messaging;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async () => { sent = true; } }),
      configurable: true,
      writable: true,
    });

    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ displayName: 'Test User', uid: 'u1' });

    assert.equal(warned, 'ADMIN_UID not set');
    assert.equal(sent, false);

    functions.logger.warn = originalWarn;
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
    process.env.ADMIN_UID = origEnv;
  });

  it('warns when admin user lacks fcmToken', async () => {
    const originalFirestore = admin.firestore;
    Object.defineProperty(admin, 'firestore', {
      value: () => ({
        collection: () => ({
          doc: () => ({ get: async () => ({ data: () => ({}) }) }),
        }),
      }),
      configurable: true,
      writable: true,
    });

    let warned;
    const originalWarn = functions.logger.warn;
    functions.logger.warn = (msg) => { warned = msg; };

    let sent = false;
    const originalMessaging = admin.messaging;
    Object.defineProperty(admin, 'messaging', {
      value: () => ({ send: async () => { sent = true; } }),
      configurable: true,
      writable: true,
    });

    const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
    await wrapped({ displayName: 'Test User', uid: 'u1' });

    assert.equal(warned, 'No FCM token for admin user admin1');
    assert.equal(sent, false);

    functions.logger.warn = originalWarn;
    Object.defineProperty(admin, 'messaging', { value: originalMessaging, writable: true });
    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });

});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
