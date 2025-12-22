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
const { sendEmail, getSendgridSettings } = require("./sendgrid-utils");

admin.initializeApp();

const sendFeedbackEmail = async (type, snapshot, params) => {
  if (!snapshot) {
    functions.logger.error('Feedback email aborted: missing snapshot');
    return;
  }

  const data = typeof snapshot.data === 'function' ? snapshot.data() || {} : {};
  const normalizeText = (value, fallback) => {
    if (typeof value === 'string') {
      const trimmed = value.trim();
      return trimmed.length > 0 ? trimmed : fallback;
    }
    if (value !== undefined && value !== null) {
      const stringified = String(value).trim();
      return stringified.length > 0 ? stringified : fallback;
    }
    return fallback;
  };

  const title = normalizeText(data.title, 'No title provided');
  const description = normalizeText(data.description, 'No description provided');
  const reporterName = normalizeText(data.reporterName || data.reporter?.name, 'Unknown reporter');
  const reporterEmail = normalizeText(data.reporterEmail || data.reporter?.email, 'Unknown email');
  const docPath = snapshot?.ref?.path || '';

  const { from, to } = getSendgridSettings();

  const subject = `[Feedback] ${type}: ${title}`;
  const text = [
    `A new ${type.toLowerCase()} was submitted.`,
    '',
    `Title: ${title}`,
    `Description: ${description}`,
    `Reporter: ${reporterName} <${reporterEmail}>`,
    `Document Path: ${docPath}`,
    params ? `Parameters: ${JSON.stringify(params)}` : undefined,
  ].filter(Boolean).join('\n');

  const htmlLines = [
    `<p>A new ${type.toLowerCase()} was submitted.</p>`,
    `<p><strong>Title:</strong> ${title}</p>`,
    `<p><strong>Description:</strong><br>${description.replace(/\n/g, '<br>')}</p>`,
    `<p><strong>Reporter:</strong> ${reporterName} &lt;${reporterEmail}&gt;</p>`,
    docPath ? `<p><strong>Document Path:</strong> ${docPath}</p>` : '',
  ].filter(Boolean);

  try {
    await sendEmail({
      subject,
      text,
      html: htmlLines.join('\n'),
      to,
      from,
      messageData: { params },
    });
    functions.logger.info('Feedback email sent', { type, docPath });
  } catch (err) {
    functions.logger.error('Failed to send feedback email', err);
    try {
      const db = typeof admin.firestore === 'function' ? admin.firestore() : null;
      if (db?.collection) {
        await db.collection('feedbackEmailErrors').add({
          type,
          docPath,
          error: err instanceof Error ? err.message : String(err),
          occurredAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    } catch (logErr) {
      functions.logger.error('Failed to record feedback email error', logErr);
    }
  }
};

exports.onBugReportCreated = onDocumentCreated('bugReports/{reportId}', async (event) => {
  if (!event?.data) {
    functions.logger.error('Bug report creation event missing data');
    return;
  }

  await sendFeedbackEmail('Bug Report', event.data, event.params);
});

exports.onFeatureRequestCreated = onDocumentCreated('featureRequests/{requestId}', async (event) => {
  if (!event?.data) {
    functions.logger.error('Feature request creation event missing data');
    return;
  }

  await sendFeedbackEmail('Feature Request', event.data, event.params);
});

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

exports.generateScheduleDays = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');
  }

  const { groupId, days } = req.data || {};
  if (!groupId || typeof groupId !== 'string' || groupId.trim().length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'groupId required');
  }

  const requestedDays = Number(days ?? 1);
  if (!Number.isInteger(requestedDays) || requestedDays <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'days must be a positive integer');
  }
  if (requestedDays > 31) {
    throw new functions.https.HttpsError('invalid-argument', 'days must be 31 or fewer');
  }

  const db = admin.firestore();
  const groupRef = db.collection('groups').doc(groupId);
  const groupSnap = await groupRef.get();
  if (!groupSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Group not found');
  }

  const uid = req.auth.uid;
  const isOwner = groupSnap.data()?.ownerUid === uid;
  const memberSnap = await groupRef.collection('members').doc(uid).get();
  const role = memberSnap.exists ? memberSnap.data()?.role : undefined;
  const isAdmin = role === 'admin' || role === 'owner';
  if (!isOwner && !isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Owner/admin only');
  }

  const templatesSnap = await groupRef
    .collection('scheduleTemplates')
    .where('active', '==', true)
    .get();

  if (templatesSnap.empty) {
    return { success: true, dates: [] };
  }

  const scheduleUpdates = new Map();
  const generatedDates = new Set();
  const templateUpdates = [];

  templatesSnap.forEach((doc) => {
    const data = doc.data() || {};
    const timeZone = (data.timezone || 'UTC').toString();
    const rawWeekdays = Array.isArray(data.weekdays)
      ? data.weekdays
        .map((value) => (typeof value === 'string' ? value.toUpperCase() : ''))
        .filter((value) => value && WEEKDAY_MAP[value])
      : null;
    const allowedDays = rawWeekdays && rawWeekdays.length > 0 ? rawWeekdays : null;

    const plan = (data.plan || '').toString();
    const canon = canonForPlan(plan);
    const chaptersPerDay = Number(data.chaptersPerDay || 0);

    const lastDate =
      parseDateValue(data.lastMaterializedDate)
      || parseDateValue(data.lastMaterializedAt)
      || parseDateValue(data.lastGeneratedAt)
      || parseDateValue(data.lastGenerated);

    const baseline = lastDate
      || decrementDateParts(currentLocalDateParts(timeZone));

    let cursorRef = null;
    if (chaptersPerDay > 0 && canon) {
      const defaultRef = `${canon[0][0]} 1`;
      cursorRef = (data.cursorRef || data.startRef || defaultRef).toString();
    }

    const scheduledDates = [];
    let working = baseline;
    const maxIterations = requestedDays * 14 + 14;
    let attempts = 0;
    while (scheduledDates.length < requestedDays && attempts < maxIterations) {
      working = incrementDateParts(working);
      attempts += 1;
      if (allowedDays) {
        const weekday = localWeekdayCode(working, timeZone);
        if (!allowedDays.includes(weekday)) {
          continue;
        }
      }
      scheduledDates.push(working);
    }

    if (scheduledDates.length < requestedDays) {
      functions.logger.warn('Unable to satisfy requested days due to constraints', {
        template: doc.ref.path,
        requestedDays,
        generated: scheduledDates.length,
      });
    }

    scheduledDates.forEach((parts) => {
      const dateKey = formatDateKey(parts);
      generatedDates.add(dateKey);
      let entry = scheduleUpdates.get(dateKey);
      if (!entry) {
        entry = {
          date: new Date(Date.UTC(parts.y, parts.m - 1, parts.d)),
          chapters: new Set(),
        };
        scheduleUpdates.set(dateKey, entry);
      }

      if (chaptersPerDay > 0 && canon && cursorRef) {
        const { chapters, nextCursor } = advanceCursor(cursorRef, chaptersPerDay, canon);
        chapters.forEach((chapter) => entry.chapters.add(chapter));
        cursorRef = nextCursor;
      }
    });

    const updateData = {};
    if (chaptersPerDay > 0 && canon && cursorRef) {
      updateData.cursorRef = cursorRef;
    }
    const finalDate = scheduledDates[scheduledDates.length - 1];
    if (finalDate) {
      updateData.lastMaterializedDate = timestampFromParts(finalDate);
    }

    if (Object.keys(updateData).length > 0) {
      templateUpdates.push({ ref: doc.ref, data: updateData });
    }
  });

  const sortedDates = Array.from(generatedDates).sort();
  for (const dateKey of sortedDates) {
    const scheduleRef = groupRef.collection('schedule').doc(dateKey);
    const snap = await scheduleRef.get();
    const entry = scheduleUpdates.get(dateKey);
    const chapterArray = Array.from(entry?.chapters ?? []);

    if (!snap.exists) {
      await scheduleRef.set({
        date: entry
          ? admin.firestore.Timestamp.fromDate(entry.date)
          : admin.firestore.Timestamp.fromDate(new Date(dateKey)),
        chapters: chapterArray,
        _source: 'auto',
      });
    } else {
      const existing = Array.isArray(snap.data()?.chapters) ? snap.data().chapters : [];
      const merged = Array.from(new Set(existing.concat(chapterArray)));
      const update = { chapters: merged };
      if (!snap.data()?._source) {
        update._source = 'auto';
      }
      await scheduleRef.set(update, { merge: true });
    }
  }

  for (const update of templateUpdates) {
    await update.ref.set(update.data, { merge: true });
  }

  return { success: true, dates: sortedDates };
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

const monthlyStats = require('./monthly-stats');

const formatMonthLabel = (date) => date.toLocaleString('en-US', {
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});

exports.sendMonthlyStatsEmail = onSchedule({
  schedule: '0 9 1 * *',
  timeZone: 'Etc/UTC',
  region: 'us-central1',
  maxInstances: 1,
}, async () => {
  const db = admin.firestore();
  const auth = typeof admin.auth === 'function' ? admin.auth() : null;
  const { start, end } = monthlyStats.getPreviousMonthRange();
  const label = formatMonthLabel(start);
  const userSnapshot = await db.collection('users').get();

  if (userSnapshot.empty) {
    functions.logger.info('No users found for monthly stats email');
    return;
  }

  for (const userDoc of userSnapshot.docs) {
    const data = typeof userDoc.data === 'function' ? userDoc.data() : userDoc.data;
    const emailPrefs = data?.emailPrefs;
    const monthlySummaryEnabled =
      typeof emailPrefs?.monthlySummary === 'boolean' ? emailPrefs.monthlySummary : true;
    if (!monthlySummaryEnabled) {
      functions.logger.info('Skipping monthly stats email: opted out', { uid: userDoc.id });
      continue;
    }

    let email = data?.email || data?.emailAddress;
    const displayName = data?.displayName || data?.name || 'there';
    let emailVerified = false;

    if (auth?.getUser) {
      try {
        const userRecord = await auth.getUser(userDoc.id);
        emailVerified = userRecord?.emailVerified === true;
        email = userRecord?.email || email;
      } catch (err) {
        functions.logger.warn('Skipping monthly stats email: failed to load auth user', {
          uid: userDoc.id,
          error: err instanceof Error ? err.message : String(err),
        });
        continue;
      }
    }

    if (!emailVerified || !email) {
      functions.logger.warn('Skipping monthly stats email without verified recipient', {
        uid: userDoc.id,
        emailVerified,
        hasEmail: Boolean(email),
      });
      continue;
    }

    try {
      const stats = await monthlyStats.getPreviousMonthStats(db, userDoc.id, end);
      const longestStreak = stats.streakSegments.reduce(
        (max, segment) => Math.max(max, segment.length),
        0,
      );
      const subject = `Your ${label} reading summary`;
      const textLines = [
        `Hi ${displayName},`,
        `Here are your ${label} reading stats:`,
        `- Days read: ${stats.daysRead}`,
        `- Streaks: ${longestStreak || 0}-day max across ${stats.streakSegments.length} segments`,
        `- Grace days used: ${stats.graceDaysUsed}`,
        '',
        'Keep up the great work! 🕊️',
      ];

      const htmlLines = [
        `<p>Hi ${displayName},</p>`,
        `<p>Here are your ${label} reading stats:</p>`,
        '<ul>',
        `<li>Days read: <strong>${stats.daysRead}</strong></li>`,
        `<li>Streaks: <strong>${longestStreak || 0}</strong>-day max across ${stats.streakSegments.length} segments</li>`,
        `<li>Grace days used: <strong>${stats.graceDaysUsed}</strong></li>`,
        '</ul>',
        '<p>Keep up the great work! 🕊️</p>',
      ];

      await sendEmail({
        subject,
        text: textLines.join('\n'),
        html: htmlLines.join('\n'),
        to: email,
      });
    } catch (err) {
      functions.logger.error('Failed to send monthly stats email', {
        uid: userDoc.id,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }
});

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
