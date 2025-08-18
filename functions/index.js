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
const functions = require("firebase-functions/v1");
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
  if (process.env.NODE_ENV !== 'production') {
    console.log('👤 req.auth:', req.auth);
    console.log('🔥 Admin project ID:', admin.app().options.projectId);
  }
  if (!req.auth) {
    throw new Error("unauthenticated: The function must be called while authenticated.");
  }

  const { ownerUid, likerName } = req.data;

  if (!ownerUid || !likerName) {
    throw new Error("invalid-argument: Missing data");
  }

  const db = admin.firestore();
  const likePref = await db
    .collection('users')
    .doc(ownerUid)
    .collection('notificationPrefs')
    .doc('like')
    .get();
  if (likePref.exists && likePref.data()?.enabled === false) {
    return;
  }

  const userDoc = await db.collection('users').doc(ownerUid).get();
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

  try {
    return await admin.messaging().send(message);
  } catch (err) {
    functions.logger.error('Failed to send like notification', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to send like notification',
      err instanceof Error ? err.message : String(err)
    );
  }
});

exports.sendCommentNotification = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated.'
    );
  }

  const { ownerUid, commenterName } = req.data;
  if (!ownerUid || !commenterName) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing data');
  }

  const db = admin.firestore();
  const commentPref = await db
    .collection('users')
    .doc(ownerUid)
    .collection('notificationPrefs')
    .doc('comment')
    .get();
  if (commentPref.exists && commentPref.data()?.enabled === false) {
    return;
  }

  const userDoc = await db.collection('users').doc(ownerUid).get();
  const token = userDoc.data()?.fcmToken;
  if (!token) {
    functions.logger.info(`No FCM token for user ${ownerUid}`);
    return;
  }

  const message = {
    token,
    notification: {
      title: '📖 New Comment',
      body: `${commenterName} commented on your reading.`,
    },
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  };

  try {
    return await admin.messaging().send(message);
  } catch (err) {
    functions.logger.error('Failed to send comment notification', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to send comment notification',
      err instanceof Error ? err.message : String(err)
    );
  }
});

exports.sendNudgeNotification = onCall({ region: "us-central1" }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated."
    );
  }

  const { toUid, fromName } = req.data;
  if (!toUid || !fromName) {
    throw new functions.https.HttpsError("invalid-argument", "Missing parameters");
  }

  const fromUid = req.auth.uid;
  const db = admin.firestore();

  const nudgePref = await db
    .collection('users')
    .doc(toUid)
    .collection('notificationPrefs')
    .doc('nudge')
    .get();
  if (nudgePref.exists && nudgePref.data()?.enabled === false) {
    await db
      .collection('users')
      .doc(fromUid)
      .collection('nudges')
      .doc(toUid)
      .set({ timestamp: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    return { alreadySent: false };
  }
  const logRef = db.collection("users").doc(fromUid)
    .collection("nudges").doc(toUid);

  const logDoc = await logRef.get();
  const now = new Date();
  if (logDoc.exists) {
    const lastTs = logDoc.data().timestamp?.toDate ? logDoc.data().timestamp.toDate() : null;
    if (lastTs && lastTs.getFullYear() === now.getFullYear() &&
        lastTs.getMonth() === now.getMonth() &&
        lastTs.getDate() === now.getDate()) {
      return { alreadySent: true };
    }
  }

  const dateKey = new Date().toISOString().slice(0, 10);
  const readDoc = await db
    .collection('users')
    .doc(toUid)
    .collection('reading')
    .doc(dateKey)
    .get();
  if (readDoc.exists && readDoc.data()?.read === true) {
    return { alreadyRead: true };
  }

  const userDoc = await db.collection('users').doc(toUid).get();
  const token = userDoc.data()?.fcmToken;
  if (token) {
    const message = {
      token,
      notification: {
        title: "📖 Time to Read!",
        body: `${fromName} nudged you to read today.`,
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

    try {
      await admin.messaging().send(message);
    } catch (err) {
      functions.logger.error('Failed to send nudge notification', err);
      throw new functions.https.HttpsError(
        'internal',
        'Failed to send nudge notification',
        err instanceof Error ? err.message : String(err)
      );
    }
  }

  await logRef.set(
    { timestamp: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  return { alreadySent: false };
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
  try {
    await Promise.all([
      receivedRef.delete(),
      sentRef.delete()
    ]);
  } catch (err) {
    functions.logger.error('Failed to delete friend request pair', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to delete friend request pair',
      err instanceof Error ? err.message : String(err)
    );
  }

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

  // Remove the pending request documents now that the users are friends
  batch.delete(fromRef.collection("friendRequestsSent").doc(toUid));
  batch.delete(toRef.collection("friendRequestsReceived").doc(fromUid));
  try {
    await batch.commit();
  } catch (err) {
    functions.logger.error('Failed to accept friend request', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to accept friend request',
      err instanceof Error ? err.message : String(err)
    );
  }

  return { success: true };
});

exports.sendSignupNotification = functions.auth.user().onCreate(async (user) => {
  const adminUid = process.env.ADMIN_UID;
  if (!adminUid) {
    functions.logger.warn('ADMIN_UID not set');
    return;
  }

  const adminDoc = await admin.firestore().collection('users').doc(adminUid).get();
  const token = adminDoc.data()?.fcmToken;
  if (!token) {
    functions.logger.warn(`No FCM token for admin user ${adminUid}`);
    return;
  }

  // Prefer displayName, then email, otherwise use a generic label
  const name = user.displayName || user.email || 'New user';
  const message = {
    token,
    notification: {
      title: 'New Signup',
      body: `${name} just signed up.`,
    },
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  };

  try {
    await admin.messaging().send(message);
  } catch (err) {
    functions.logger.error('Failed to send signup notification', err);
  }
});

exports.markFirstReader = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated.'
    );
  }

  const { dateKey } = req.data;
  if (!dateKey) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing dateKey');
  }

  const uid = req.auth.uid;
  const db = admin.firestore();
  const rewardRef = db.collection('daily_rewards').doc(dateKey);
  const entriesRef = db
    .collection('read_logs')
    .doc(dateKey)
    .collection('entries');

  try {
    const result = await db.runTransaction(async (t) => {
      const rewardSnap = await t.get(rewardRef);
      if (rewardSnap.exists) {
        const storedUid = rewardSnap.data()?.uid;
        const storedTs = rewardSnap.data()?.timestamp;
        return { first: storedUid === uid, existingUid: storedUid, existingTs: storedTs };
      }

      const entriesSnap = await t.get(
        entriesRef.orderBy('timestamp').limit(2)
      );

      if (entriesSnap.empty) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'No log entries found for the day'
        );
      }

      const firstDoc = entriesSnap.docs[0];
      const firstUid = firstDoc.id;
      const firstData = typeof firstDoc.data === 'function' ? firstDoc.data() : firstDoc.data;
      const firstTs = firstData?.timestamp;

      let conflict = false;
      const conflictUids = [];
      if (entriesSnap.docs.length > 1) {
        const secondDoc = entriesSnap.docs[1];
        const secondData = typeof secondDoc.data === 'function' ? secondDoc.data() : secondDoc.data;
        const secondTs = secondData?.timestamp;
        if (secondTs && firstTs && secondTs.isEqual && secondTs.isEqual(firstTs)) {
          conflict = true;
          conflictUids.push(firstUid, secondDoc.id);
        }
      }

      t.create(rewardRef, {
        uid: firstUid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      t.set(entriesRef.doc(firstUid), { firstReader: true }, { merge: true });

      return { first: firstUid === uid, firstUid, firstTs, conflict, conflictUids };
    });

    const logTs = new Date().toISOString();
    if (result.existingUid) {
      functions.logger.info('First reader already recorded', {
        dateKey,
        storedUid: result.existingUid,
        storedTimestamp: result.existingTs?.toDate ? result.existingTs.toDate().toISOString() : result.existingTs,
        requestedUid: uid,
        logTs,
      });
    } else {
      functions.logger.info('First reader set', {
        dateKey,
        chosenUid: result.firstUid,
        entryTimestamp: result.firstTs?.toDate ? result.firstTs.toDate().toISOString() : result.firstTs,
        logTs,
      });
      if (result.conflict) {
        functions.logger.warn('First reader conflict detected', {
          dateKey,
          timestamp: result.firstTs?.toDate ? result.firstTs.toDate().toISOString() : result.firstTs,
          uids: result.conflictUids,
          logTs,
        });
      }
    }

    return { first: result.first };
  } catch (err) {
    functions.logger.error('Failed to mark first reader', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to mark first reader',
      err instanceof Error ? err.message : String(err)
    );
  }
});

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
