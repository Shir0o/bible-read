/****
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

/****
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const { onCall } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

exports.sendLikeNotification = onCall({ region: "us-central1" }, async (req) => {
  console.log('👤 req.auth:', req.auth);
  console.log('🔥 Admin project ID:', admin.app().options.projectId);
  if (!req.auth) {
    throw new Error("unauthenticated: The function must be called while authenticated.");
  }

  const { ownerUid, likerName } = req.data;

  if (!ownerUid || !likerName) {
    throw new Error("invalid-argument: Missing data");
  }

  const userDoc = await admin.firestore().collection('users').doc(ownerUid).get();
  const token = userDoc.data()?.fcmToken;

  if (!token) {
    console.log(
      `No FCM token for user ${ownerUid}`
    );
    return;
  }

  const message = {
    token,
    notification: {
      title: "📖 New Like on Your Reading!",
      body: `${likerName} liked your reading log.`,
    },
    android: {
      priority: "high",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  };

  return admin.messaging().send(message);
});

exports.deleteFriendRequestPair = onCall({ region: "us-central1" }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
  }

  const { fromUid, toUid } = req.data;
  if (!fromUid || !toUid) {
    throw new functions.https.HttpsError("invalid-argument", "Missing fromUid or toUid");
  }

  if (req.auth.uid !== toUid) {
    throw new functions.https.HttpsError("permission-denied", "Only the receiver can delete both friend request documents.");
  }

  const db = admin.firestore();

  const receivedRef = db.collection("users").doc(toUid)
    .collection("friendRequestsReceived").doc(fromUid);

  const sentRef = db.collection("users").doc(fromUid)
    .collection("friendRequestsSent").doc(toUid);

  await Promise.all([
    receivedRef.delete(),
    sentRef.delete()
  ]);

  return { success: true };
});

exports.acceptFriendRequest = onCall({ region: "us-central1" }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const { fromUid, toUid, fromName, toName } = req.data;
  if (!fromUid || !toUid || !fromName || !toName) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Missing parameters"
    );
  }

  if (req.auth.uid !== toUid) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only the receiver can accept this request."
    );
  }

  const db = admin.firestore();
  const fromRef = db.collection("users").doc(fromUid);
  const toRef = db.collection("users").doc(toUid);

  const batch = db.batch();

  batch.set(fromRef.collection("friends").doc(toUid), {
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    name: toName,
  });

  batch.set(toRef.collection("friends").doc(fromUid), {
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    name: fromName,
  });

  batch.delete(fromRef.collection("friendRequestsSent").doc(toUid));
  batch.delete(toRef.collection("friendRequestsReceived").doc(fromUid));

  await batch.commit();

  return { success: true };
});

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
