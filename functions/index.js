/****
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const { onCall } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {
  getFcmToken,
  isNotificationEnabled,
  sendNotification,
} = require("./notification-utils");


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

  const actorUid = req.auth.uid;
  const { ownerUid, likerName } = req.data;

  if (!ownerUid || !likerName) {
    throw new Error("invalid-argument: Missing data");
  }

  const [enabled, token] = await Promise.all([
    isNotificationEnabled(ownerUid, 'like'),
    getFcmToken(ownerUid),
  ]);

  if (!enabled || !token) {
    if (!token) {
      console.log(`No FCM token for user ${ownerUid}`);
    }
    return;
  }

  try {
    return await sendNotification(token, {
      title: "📖 New Like on Your Reading!",
      body: `${likerName} liked your reading log.`,
      data: {
        type: 'like',
        ownerUid,
        fromUid: actorUid,
      },
    });
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

  const actorUid = req.auth.uid;
  const { ownerUid, commenterName } = req.data;
  if (!ownerUid || !commenterName) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing data');
  }

  const [enabled, token] = await Promise.all([
    isNotificationEnabled(ownerUid, 'comment'),
    getFcmToken(ownerUid),
  ]);

  if (!enabled || !token) {
    if (!token) {
      functions.logger.info(`No FCM token for user ${ownerUid}`);
    }
    return;
  }

  try {
    return await sendNotification(token, {
      title: '📖 New Comment',
      body: `${commenterName} commented on your reading.`,
      data: {
        type: 'comment',
        ownerUid,
        fromUid: actorUid,
      },
    });
  } catch (err) {
    functions.logger.error('Failed to send comment notification', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to send comment notification',
      err instanceof Error ? err.message : String(err)
    );
  }
});

exports.claimSeasonalChallengeReward = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated.'
    );
  }

  const { seasonId, challengeId } = req.data || {};
  if (!seasonId || !challengeId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing seasonId or challengeId'
    );
  }

  const uid = req.auth.uid;
  const db = admin.firestore();
  const challengeRef = db
    .collection('seasons')
    .doc(seasonId)
    .collection('challenges')
    .doc(challengeId);
  const progressRef = db
    .collection('users')
    .doc(uid)
    .collection('seasonChallenges')
    .doc(`${seasonId}_${challengeId}`);
  const rewardRef = db
    .collection('users')
    .doc(uid)
    .collection('seasonRewards')
    .doc(`${seasonId}_${challengeId}`);

  let challengeData;
  let rewardRecord;

  await db.runTransaction(async (transaction) => {
    const [challengeSnap, progressSnap, rewardSnap] = await Promise.all([
      transaction.get(challengeRef),
      transaction.get(progressRef),
      transaction.get(rewardRef),
    ]);

    if (!challengeSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Challenge not found');
    }

    if (!progressSnap.exists) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Progress not found'
      );
    }

    if (rewardSnap.exists || progressSnap.data()?.rewardClaimedAt) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Reward already claimed'
      );
    }

    challengeData = challengeSnap.data() || {};
    const goalValue = Number(challengeData.goal || 0);
    const progressData = progressSnap.data() || {};
    const total = Number(progressData.totalProgress || 0);
    if (goalValue > 0 && total < goalValue) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Challenge not complete'
      );
    }

    const claimedAt = admin.firestore.FieldValue.serverTimestamp();
    rewardRecord = {
      seasonId,
      challengeId,
      challengeTitle: challengeData.title || '',
      reward: challengeData.reward || null,
      claimedAt,
    };

    transaction.set(rewardRef, rewardRecord);
    transaction.set(
      progressRef,
      { rewardClaimedAt: claimedAt },
      { merge: true }
    );
  });

  const notificationsRef = db
    .collection('users')
    .doc(uid)
    .collection('notifications');
  const notificationId = notificationsRef.doc().id;
  const message = rewardRecord?.reward?.title
    ? `You claimed ${rewardRecord.reward.title}.`
    : 'Your seasonal challenge reward is ready!';

  await notificationsRef.doc(notificationId).set({
    type: 'seasonalChallenge',
    read: false,
    message,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });

  const [enabled, token] = await Promise.all([
    isNotificationEnabled(uid, 'seasonalChallenge'),
    getFcmToken(uid),
  ]);

  if (enabled && token) {
    const title = 'Seasonal reward unlocked';
    const body = challengeData?.title
      ? `You completed "${challengeData.title}".`
      : 'Your seasonal challenge reward is ready!';
    try {
      await sendNotification(token, {
        title,
        body,
        data: {
          type: 'seasonalChallenge',
          seasonId,
          challengeId,
        },
      });
    } catch (err) {
      functions.logger.error(
        'Failed to send seasonal challenge notification',
        err,
      );
    }
  }

  return { success: true };
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
  const logRef = db.collection('users').doc(fromUid)
    .collection('nudges').doc(toUid);

  const [enabled, token] = await Promise.all([
    isNotificationEnabled(toUid, 'nudge'),
    getFcmToken(toUid),
  ]);

  if (!enabled) {
    await logRef.set(
      { timestamp: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { alreadySent: false };
  }

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

  if (!token) {
    await logRef.set(
      { timestamp: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { alreadySent: false };
  }

  try {
    await sendNotification(token, {
      title: "Encouragement",
      body: `${fromName} sent you some encouragement.`,
      data: {
        type: 'nudge',
        fromUid,
        toUid,
      },
    });
  } catch (err) {
    functions.logger.error('Failed to send nudge notification', err);
    throw new functions.https.HttpsError(
      'internal',
      'Failed to send nudge notification',
      err instanceof Error ? err.message : String(err)
    );
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
    const notificationsSnap = await db
      .collection('users')
      .doc(toUid)
      .collection('notifications')
      .where('type', '==', 'friendRequest')
      .where('fromUid', '==', fromUid)
      .get();

    const ops = [receivedRef.delete(), sentRef.delete()];
    notificationsSnap.forEach((doc) => ops.push(doc.ref.delete()));
    await Promise.all(ops);
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
    const notificationsSnap = await toRef
      .collection('notifications')
      .where('type', '==', 'friendRequest')
      .where('fromUid', '==', fromUid)
      .get();
    notificationsSnap.forEach((doc) => batch.update(doc.ref, { read: true }));
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

exports.removeFriendRequestNotification = functions.firestore
  .document('users/{uid}/friendRequestsReceived/{fromUid}')
  .onDelete(async (_snap, context) => {
    const { uid, fromUid } = context.params;
    const db = admin.firestore();
    try {
      const notificationsSnap = await db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('type', '==', 'friendRequest')
        .where('fromUid', '==', fromUid)
        .get();
      const deletions = [];
      notificationsSnap.forEach((doc) => deletions.push(doc.ref.delete()));
      await Promise.all(deletions);
    } catch (err) {
      functions.logger.error('Failed to prune friend request notifications', err);
    }
  });

exports.sendSignupNotification = functions.auth.user().onCreate(async (user) => {
  const adminUid = process.env.ADMIN_UID;
  if (!adminUid) {
    functions.logger.warn('ADMIN_UID not set');
    return;
  }

  const token = await getFcmToken(adminUid);
  if (!token) {
    functions.logger.warn(`No FCM token for admin user ${adminUid}`);
    return;
  }

  // Prefer displayName, then email, otherwise use a generic label
  const name = user.displayName || user.email || 'New user';
  try {
    await sendNotification(token, {
      title: 'New Signup',
      body: `${name} just signed up.`,
      data: {
        type: 'signup',
        fromUid: user.uid,
      },
    });
  } catch (err) {
    functions.logger.error('Failed to send signup notification', err);
  }
});

const OT_CANON = [
  ['Gen', 50], ['Ex', 40], ['Lev', 27], ['Num', 36], ['Deut', 34],
  ['Josh', 24], ['Judg', 21], ['Ruth', 4], ['1Sam', 31], ['2Sam', 24],
  ['1Kgs', 22], ['2Kgs', 25], ['1Chr', 29], ['2Chr', 36], ['Ezra', 10],
  ['Neh', 13], ['Esth', 10], ['Job', 42], ['Psalm', 150], ['Prov', 31],
  ['Eccl', 12], ['Song', 8], ['Isa', 66], ['Jer', 52], ['Lam', 5],
  ['Ezek', 48], ['Dan', 12], ['Hos', 14], ['Joel', 3], ['Amos', 9],
  ['Obad', 1], ['Jonah', 4], ['Mic', 7], ['Nah', 3], ['Hab', 3],
  ['Zeph', 3], ['Hag', 2], ['Zech', 14], ['Mal', 4],
];
const NT_CANON = [
  ['Matt', 28], ['Mark', 16], ['Luke', 24], ['John', 21], ['Acts', 28],
  ['Rom', 16], ['1Cor', 16], ['2Cor', 13], ['Gal', 6], ['Eph', 6],
  ['Phil', 4], ['Col', 4], ['1Thess', 5], ['2Thess', 3], ['1Tim', 6],
  ['2Tim', 4], ['Titus', 3], ['Phlm', 1], ['Heb', 13], ['Jas', 5],
  ['1Pet', 5], ['2Pet', 3], ['1John', 5], ['2John', 1], ['3John', 1],
  ['Jude', 1], ['Rev', 22],
];
const PSALMS_CANON = [['Psalm', 150]];

const WEEKDAY_MAP = { SU: 'SU', MO: 'MO', TU: 'TU', WE: 'WE', TH: 'TH', FR: 'FR', SA: 'SA' };

function canonForPlan(plan) {
  if (plan === 'sequential_nt') return NT_CANON;
  if (plan === 'psalms') return PSALMS_CANON;
  if (plan === 'sequential_ot') return OT_CANON;
  return null;
}

function parseChapterRef(ref, canon) {
  if (!ref || typeof ref !== 'string') return null;
  const parts = ref.trim().split(/\s+/);
  if (parts.length < 2) return null;
  const book = parts[0];
  const chap = Number(parts[1]);
  if (!Number.isFinite(chap)) return null;
  const idx = canon.findIndex(([name]) => name === book);
  if (idx === -1) return null;
  return { idx, chap };
}

function formatChapterRef(idx, chap, canon) {
  return `${canon[idx][0]} ${chap}`;
}

function advanceCursor(startRef, count, canon) {
  if (!canon) {
    return { chapters: [], nextCursor: startRef };
  }
  const start = parseChapterRef(startRef, canon) || { idx: 0, chap: 1 };
  let i = start.idx;
  let c = start.chap;
  const chapters = [];
  let last = null;
  for (let k = 0; k < count; k += 1) {
    if (i >= canon.length) break;
    chapters.push(formatChapterRef(i, c, canon));
    last = { idx: i, chap: c };
    c += 1;
    const max = canon[i][1];
    if (c > max) {
      i += 1;
      c = 1;
    }
  }
  let nextCursor = startRef;
  if (last) {
    const max = canon[last.idx][1];
    if (last.chap < max) {
      nextCursor = formatChapterRef(last.idx, last.chap + 1, canon);
    } else if (last.idx + 1 < canon.length) {
      nextCursor = formatChapterRef(last.idx + 1, 1, canon);
    } else {
      nextCursor = formatChapterRef(last.idx, last.chap, canon);
    }
  }
  return { chapters, nextCursor };
}

function timestampFromParts(parts) {
  return admin.firestore.Timestamp.fromDate(
    new Date(Date.UTC(parts.y, parts.m - 1, parts.d)),
  );
}

function parseDateValue(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') {
    const date = value.toDate();
    return { y: date.getUTCFullYear(), m: date.getUTCMonth() + 1, d: date.getUTCDate() };
  }
  if (value instanceof Date) {
    return { y: value.getUTCFullYear(), m: value.getUTCMonth() + 1, d: value.getUTCDate() };
  }
  if (typeof value === 'number') {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return { y: date.getUTCFullYear(), m: date.getUTCMonth() + 1, d: date.getUTCDate() };
    }
    return null;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    const match = /^(-?\d{1,4})-(\d{1,2})-(\d{1,2})$/.exec(trimmed);
    if (match) {
      return {
        y: Number(match[1]),
        m: Number(match[2]),
        d: Number(match[3]),
      };
    }
    const parsed = new Date(trimmed);
    if (!Number.isNaN(parsed.getTime())) {
      return {
        y: parsed.getUTCFullYear(),
        m: parsed.getUTCMonth() + 1,
        d: parsed.getUTCDate(),
      };
    }
  }
  return null;
}

function shiftDateParts(parts, deltaDays) {
  const date = new Date(Date.UTC(parts.y, parts.m - 1, parts.d));
  date.setUTCDate(date.getUTCDate() + deltaDays);
  return {
    y: date.getUTCFullYear(),
    m: date.getUTCMonth() + 1,
    d: date.getUTCDate(),
  };
}

function incrementDateParts(parts) {
  return shiftDateParts(parts, 1);
}

function decrementDateParts(parts) {
  return shiftDateParts(parts, -1);
}

function currentLocalDateParts(timeZone) {
  try {
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    const parts = fmt.formatToParts(new Date());
    const y = Number(parts.find((p) => p.type === 'year')?.value);
    const m = Number(parts.find((p) => p.type === 'month')?.value);
    const d = Number(parts.find((p) => p.type === 'day')?.value);
    if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
      throw new Error('Invalid local date parts');
    }
    return { y, m, d };
  } catch (err) {
    functions.logger.warn('Failed to resolve timezone date, defaulting to UTC', err);
    const now = new Date();
    return { y: now.getUTCFullYear(), m: now.getUTCMonth() + 1, d: now.getUTCDate() };
  }
}

function formatDateKey(parts) {
  return `${parts.y.toString().padStart(4, '0')}-${parts.m
    .toString()
    .padStart(2, '0')}-${parts.d.toString().padStart(2, '0')}`;
}

function localWeekdayCode(parts, timeZone) {
  try {
    const fmt = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short' });
    const code = fmt
      .format(new Date(Date.UTC(parts.y, parts.m - 1, parts.d)))
      .slice(0, 2)
      .toUpperCase();
    return WEEKDAY_MAP[code] || code;
  } catch (err) {
    functions.logger.warn('Failed to compute weekday; falling back to UTC', err);
    const date = new Date(Date.UTC(parts.y, parts.m - 1, parts.d));
    return ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'][date.getUTCDay()];
  }
}


// Rewrites every member's ticked chapters so each lands on the new day that
// holds the same reference. Eager and cross-member: the admin SDK bypasses
// the per-member progress rules so we can repair everyone's data in one
// shot, where the client-side path (Phase 5a) only repairs the caller's
// own ticks.
exports.remapGroupProgress = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');
  }

  const { groupId, days } = req.data || {};
  if (!groupId || typeof groupId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'groupId required');
  }
  if (!Array.isArray(days)) {
    throw new functions.https.HttpsError('invalid-argument', 'days must be an array');
  }

  const db = admin.firestore();
  const groupRef = db.collection('groups').doc(groupId);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Group not found');
  }

  const uid = req.auth.uid;
  const isOwner = groupSnap.data().ownerUid === uid;
  const memberSnap = await groupRef.collection('members').doc(uid).get();
  const role = memberSnap.exists ? memberSnap.data().role : undefined;
  const isAdmin = role === 'admin' || role === 'owner';
  if (!isOwner && !isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Owner/admin only');
  }

  // Cap the synchronous path so a giant plan does not time out halfway. The
  // client falls back to per-member self-repair (Phase 5a) when this throws.
  const memberCountSnap = await groupRef.collection('members').get();
  const memberCount = memberCountSnap.size;
  if (days.length * memberCount > 500 * 25) {
    throw new functions.https.HttpsError(
      'resource-exhausted',
      'This plan is too large to rebuild automatically.',
    );
  }

  // Read the existing schedule so we know what to delete.
  const oldScheduleSnap = await groupRef.collection('schedule').get();
  const oldDays = oldScheduleSnap.docs.map((d) => ({
    dateId: d.id,
    chapters: Array.isArray(d.data().chapters) ? d.data().chapters : [],
  }));

  // Read every member's ticked indices across every progress date.
  const progressSnap = await groupRef.collection('progress').get();
  const completedByUid = {};
  const progressDays = []; // [{ dateId, entries: [{ uid, indices, count }] }]
  for (const dayDoc of progressSnap.docs) {
    const dateId = dayDoc.id;
    const entriesSnap = await dayDoc.ref.collection('entries').get();
    const entries = [];
    for (const entryDoc of entriesSnap.docs) {
      const entryUid = entryDoc.id;
      const data = entryDoc.data();
      const count = (data.count | 0) || 0;
      let indices = [];
      if (count > 0) {
        const itemsSnap = await entryDoc.ref.collection('items').get();
        indices = itemsSnap.docs.map((it) => parseInt(it.id, 10));
      } else if (data.done === true) {
        // Legacy "whole day done" — empty set means every chapter.
        indices = [];
        indices.__legacyAll = true;
      }
      if (count > 0 || data.done === true) {
        entries.push({ uid: entryUid, indices, count });
        if (!completedByUid[entryUid]) completedByUid[entryUid] = {};
        completedByUid[entryUid][dateId] = indices;
      }
    }
    progressDays.push({ dateId, entries });
  }

  const remap = remapProgress({
    oldDays,
    newDays: days,
    completedByDate: completedByUid,
  });

  // 1. Write the new schedule first so a mid-flight failure leaves a
  //    *superset* schedule, never a hole.
  const WRITE_BATCH = 450;
  for (let i = 0; i < days.length; i += WRITE_BATCH) {
    const batch = db.batch();
    const end = Math.min(i + WRITE_BATCH, days.length);
    for (let j = i; j < end; j++) {
      const day = days[j];
      const [y, m, d] = day.dateId.split('-').map((v) => parseInt(v, 10));
      batch.set(groupRef.collection('schedule').doc(day.dateId), {
        date: admin.firestore.Timestamp.fromDate(new Date(Date.UTC(y, m - 1, d))),
        chapters: day.chapters,
      });
    }
    await batch.commit();
  }

  // 2. Delete days that no longer belong to the plan.
  const keepIds = new Set(days.map((d) => d.dateId));
  const toDelete = oldScheduleSnap.docs
    .map((d) => d.id)
    .filter((id) => !keepIds.has(id));
  for (let i = 0; i < toDelete.length; i += WRITE_BATCH) {
    const batch = db.batch();
    const end = Math.min(i + WRITE_BATCH, toDelete.length);
    for (let j = i; j < end; j++) {
      batch.delete(groupRef.collection('schedule').doc(toDelete[j]));
    }
    await batch.commit();
  }

  // 3. Rewrite every member's items under the new dates.
  for (const [moveUid, byDate] of Object.entries(remap.byDate)) {
    let ops = [];
    for (const [dateId, indices] of Object.entries(byDate)) {
      if (!indices || indices.length === 0) continue;
      const entryRef = groupRef
        .collection('progress')
        .doc(dateId)
        .collection('entries')
        .doc(moveUid);
      for (const idx of indices) {
        ops.push({
          type: 'set',
          ref: entryRef.collection('items').doc(String(idx)),
          data: { done: true, ts: admin.firestore.FieldValue.serverTimestamp() },
        });
      }
      ops.push({
        type: 'set',
        ref: entryRef,
        data: {
          done: true,
          uid: moveUid,
          groupId: groupId,
          dateId: dateId,
          count: indices.length,
          ts: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    }
    for (let i = 0; i < ops.length; i += WRITE_BATCH) {
      const batch = db.batch();
      const end = Math.min(i + WRITE_BATCH, ops.length);
      for (let j = i; j < end; j++) {
        const op = ops[j];
        if (op.type === 'set') batch.set(op.ref, op.data);
      }
      await batch.commit();
    }
  }

  // 4. Delete the old progress entries that the remap emptied out.
  const oldEntryRefs = [];
  for (const day of progressDays) {
    for (const entry of day.entries) {
      const stillHas = remap.byDate[entry.uid]
        && remap.byDate[entry.uid][day.dateId]
        && remap.byDate[entry.uid][day.dateId].length > 0;
      if (!stillHas) {
        oldEntryRefs.push(
          groupRef
            .collection('progress')
            .doc(day.dateId)
            .collection('entries')
            .doc(entry.uid),
        );
      }
    }
  }
  for (let i = 0; i < oldEntryRefs.length; i += WRITE_BATCH) {
    const batch = db.batch();
    const end = Math.min(i + WRITE_BATCH, oldEntryRefs.length);
    for (let j = i; j < end; j++) {
      batch.delete(oldEntryRefs[j]);
    }
    await batch.commit();
  }

  // 5. Set every member's progressSummary absolutely (not increment) — also
  //    repairs the pre-existing drift between count and summary.
  const summaryOps = [];
  for (const [moveUid, byDate] of Object.entries(remap.byDate)) {
    const total = Object.values(byDate).reduce(
      (sum, indices) => sum + (indices ? indices.length : 0),
      0,
    );
    summaryOps.push({
      ref: groupRef
        .collection('progressSummary')
        .doc('data')
        .collection('entries')
        .doc(moveUid),
      data: { uid: moveUid, completed: total },
    });
  }
  // Members that had progress but no surviving ticks should be set to 0
  // rather than left stale.
  for (const oldUid of Object.keys(completedByUid)) {
    if (!(oldUid in remap.byDate)) {
      summaryOps.push({
        ref: groupRef
          .collection('progressSummary')
          .doc('data')
          .collection('entries')
          .doc(oldUid),
        data: { uid: oldUid, completed: 0 },
      });
    }
  }
  for (let i = 0; i < summaryOps.length; i += WRITE_BATCH) {
    const batch = db.batch();
    const end = Math.min(i + WRITE_BATCH, summaryOps.length);
    for (let j = i; j < end; j++) {
      batch.set(summaryOps[j].ref, summaryOps[j].data);
    }
    await batch.commit();
  }

  // 6. Bump revision and stamp every member's remappedRevision.
  const planConfigSnap = await groupRef.get();
  const currentRevision = (planConfigSnap.data().planConfig?.revision | 0) || 0;
  const nextRevision = currentRevision + 1;
  await groupRef.set(
    {
      planConfig: {
        ...(planConfigSnap.data().planConfig || {}),
        revision: nextRevision,
      },
    },
    { merge: true },
  );

  const memberSnapAll = await groupRef.collection('members').get();
  for (let i = 0; i < memberSnapAll.docs.length; i += WRITE_BATCH) {
    const batch = db.batch();
    const end = Math.min(i + WRITE_BATCH, memberSnapAll.docs.length);
    for (let j = i; j < end; j++) {
      batch.set(
        memberSnapAll.docs[j].ref,
        { remappedRevision: nextRevision },
        { merge: true },
      );
    }
    await batch.commit();
  }

  return {
    success: true,
    revision: nextRevision,
    moved: Object.keys(remap.byDate).length,
  };
});

// Pure JS port of lib/services/progress_remap.dart. Inputs/outputs match.
function remapProgress({ oldDays, newDays, completedByDate }) {
  const oldByDateId = {};
  for (const day of oldDays) {
    oldByDateId[day.dateId] = day.chapters;
  }
  const newByRef = {};
  for (const day of newDays) {
    for (let i = 0; i < day.chapters.length; i++) {
      newByRef[day.chapters[i]] = { dateId: day.dateId, index: i };
    }
  }

  const byDate = {};
  const droppedRefs = {};
  const droppedByBook = {};

  for (const [uid, perDate] of Object.entries(completedByDate)) {
    const moved = {};
    const dropped = new Set();
    for (const [dateId, indices] of Object.entries(perDate)) {
      const chapters = oldByDateId[dateId];
      if (!chapters) continue;
      // An empty set / a set with __legacyAll means "every chapter on that day".
      const effective = (Array.isArray(indices) && indices.length === 0)
        ? chapters.map((_, i) => i)
        : indices;
      for (const index of effective) {
        if (index < 0 || index >= chapters.length) continue;
        const ref = chapters[index];
        const pos = newByRef[ref];
        if (pos) {
          if (!moved[pos.dateId]) moved[pos.dateId] = new Set();
          moved[pos.dateId].add(pos.index);
        } else {
          dropped.add(ref);
        }
      }
    }
    if (Object.keys(moved).length > 0) {
      byDate[uid] = {};
      for (const [dateId, idxs] of Object.entries(moved)) {
        byDate[uid][dateId] = Array.from(idxs);
      }
    }
    if (dropped.size > 0) {
      droppedRefs[uid] = Array.from(dropped);
      const byBook = {};
      for (const ref of dropped) {
        const space = ref.indexOf(' ');
        const book = space > 0 ? ref.substring(0, space) : ref;
        byBook[book] = (byBook[book] || 0) + 1;
      }
      droppedByBook[uid] = byBook;
    }
  }

  return { byDate, droppedRefs, droppedByBook };
}


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
