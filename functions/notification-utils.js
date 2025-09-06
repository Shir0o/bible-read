const admin = require('firebase-admin');

/**
 * Retrieves the FCM token for a user.
 * @param {string} uid User ID.
 * @returns {Promise<string|undefined>} token or undefined if not found.
 */
async function getFcmToken(uid) {
  const snap = await admin.firestore().collection('users').doc(uid).get();
  return snap.data()?.fcmToken;
}

/**
 * Checks if a notification type is enabled for a user.
 * @param {string} uid User ID.
 * @param {string} type Notification type doc ID.
 * @returns {Promise<boolean>} True if enabled.
 */
async function isNotificationEnabled(uid, type) {
  const prefSnap = await admin.firestore()
    .collection('users')
    .doc(uid)
    .collection('notificationPrefs')
    .doc(type)
    .get();
  return !(prefSnap.exists && prefSnap.data()?.enabled === false);
}

/**
 * Sends an FCM notification.
 * @param {string} token FCM token.
 * @param {{title: string, body: string}} payload Notification content.
 * @returns {Promise<string>} messaging ID.
 */
function sendNotification(token, { title, body }) {
  const message = {
    token,
    notification: { title, body },
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  return admin.messaging().send(message);
}

module.exports = { getFcmToken, isNotificationEnabled, sendNotification };
