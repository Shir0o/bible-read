const {test} = require('node:test');
const assert = require('node:assert');
const functionsTest = require('firebase-functions-test')({projectId: 'demo'}, './serviceAccount.json');
const admin = require('firebase-admin');

const myFunctions = require('../index');

process.env.ADMIN_UID = 'admin1';

test('sendSignupNotification builds payload', async () => {
  const originalFirestore = admin.firestore;
  admin.firestore = () => ({
    collection: () => ({
      doc: () => ({
        get: async () => ({ data: () => ({ fcmToken: 'token123' }) })
      })
    })
  });

  let captured;
  const originalMessaging = admin.messaging;
  admin.messaging = () => ({
    send: async (msg) => { captured = msg; }
  });

  const wrapped = functionsTest.wrap(myFunctions.sendSignupNotification);
  await wrapped({ displayName: 'Test User', uid: 'u1' });

  assert.equal(captured.token, 'token123');
  assert.match(captured.notification.body, /Test User/);

  admin.firestore = originalFirestore;
  admin.messaging = originalMessaging;
  functionsTest.cleanup();
});
