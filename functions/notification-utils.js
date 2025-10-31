const admin = require('firebase-admin');

// Cache tokens and notification pref flags by UID.
// Map structure: uid -> { token: string|undefined, prefs: Map<string, boolean> }
const cache = new Map();

/**
 * Retrieves the FCM token for a user.
 * @param {string} uid User ID.
 * @returns {Promise<string|undefined>} token or undefined if not found.
 */
async function getFcmToken(uid) {
  const entry = cache.get(uid);
  if (entry && entry.token !== undefined) {
    return entry.token;
  }
  const snap = await admin.firestore().collection('users').doc(uid).get();
  const token = snap.data()?.fcmToken;
  if (entry) {
    entry.token = token;
  } else {
    cache.set(uid, { token, prefs: new Map() });
  }
  return token;
}

/**
 * Checks if a notification type is enabled for a user.
 * @param {string} uid User ID.
 * @param {string} type Notification type doc ID.
 * @returns {Promise<boolean>} True if enabled.
 */
async function isNotificationEnabled(uid, type) {
  const entry = cache.get(uid);
  if (entry && entry.prefs.has(type)) {
    return entry.prefs.get(type);
  }
  const prefSnap = await admin.firestore()
    .collection('users')
    .doc(uid)
    .collection('notificationPrefs')
    .doc(type)
    .get();
  const enabled = !(prefSnap.exists && prefSnap.data()?.enabled === false);
  if (entry) {
    entry.prefs.set(type, enabled);
  } else {
    cache.set(uid, { token: undefined, prefs: new Map([[type, enabled]]) });
  }
  return enabled;
}

/**
 * Sends an FCM notification.
 * @param {string} token FCM token.
 * @param {{title: string, body: string, data?: Record<string, any>}} payload Notification content.
 * @returns {Promise<string>} messaging ID.
 */
function sendNotification(token, { title, body, data }) {
  const normalizedData = {};
  if (data && typeof data === 'object') {
    Object.entries(data).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        normalizedData[String(key)] = String(value);
      }
    });
  }

  const message = {
    token,
    notification: { title, body },
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  if (Object.keys(normalizedData).length > 0) {
    message.data = normalizedData;
  }
  return admin.messaging().send(message);
}

/**
 * Invalidates cached token and prefs for a user.
 * @param {string} uid User ID.
 */
function invalidateUserCache(uid) {
  if (uid) {
    cache.delete(uid);
  } else {
    cache.clear();
  }
}

module.exports = {
  getFcmToken,
  isNotificationEnabled,
  sendNotification,
  invalidateUserCache,
};
