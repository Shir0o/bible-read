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
      await sendNotification(token, { title, body });
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
      title: "📖 Time to Read!",
      body: `${fromName} nudged you to read today.`,
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
    });
  } catch (err) {
    functions.logger.error('Failed to send signup notification', err);
  }
});

/**
 * Daily job: create today's schedule documents for groups that have
 * auto-schedule enabled via `groups/{groupId}/scheduleTemplates/default`.
 *
 * The created schedule is an empty chapter list for the date key (YYYY-MM-DD).
 * This is idempotent: if the doc already exists, it is skipped.
 */
exports.materializeDailySchedules = functions.pubsub
  .schedule('0 4 * * *') // 04:00 UTC daily
  .timeZone('UTC')
  .onRun(async () => {
    const db = admin.firestore();

    // Helper to compute local date parts in a given IANA timezone.
    function localDateParts(date, timeZone) {
      try {
        const fmt = new Intl.DateTimeFormat('en-US', {
          timeZone,
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
        });
        const parts = fmt.formatToParts(date);
        const y = Number(parts.find((p) => p.type === 'year')?.value);
        const m = Number(parts.find((p) => p.type === 'month')?.value);
        const d = Number(parts.find((p) => p.type === 'day')?.value);
        if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
          throw new Error('Invalid local parts');
        }
        return { y, m, d };
      } catch (err) {
        functions.logger.warn(
          `Invalid timezone "${timeZone}"; defaulting to UTC`,
          err
        );
        const z = new Date();
        return { y: z.getUTCFullYear(), m: z.getUTCMonth() + 1, d: z.getUTCDate() };
      }
    }
    // Load active templates. Prefer collection group for efficiency, but
    // gracefully fall back to per-group queries if an index is required.
    async function loadActiveTemplates() {
      try {
        const cg = await db
          .collectionGroup('scheduleTemplates')
          .where('active', '==', true)
          .get();
        return cg.docs; // Array<QueryDocumentSnapshot>
      } catch (err) {
        // Firestore returns FAILED_PRECONDITION (code 9) when a composite
        // index is required. Fall back to per-group fetching to avoid hard
        // failure in production runs.
        functions.logger.warn(
          'collectionGroup index unavailable; falling back to per-group scan',
          err
        );
        const groups = await db.collection('groups').get();
        const docs = [];
        for (const g of groups.docs) {
          try {
            // eslint-disable-next-line no-await-in-loop
            const snap = await g.ref
              .collection('scheduleTemplates')
              .where('active', '==', true)
              .get();
            docs.push(...snap.docs);
          } catch (e) {
            functions.logger.warn('Failed loading templates for group', {
              group: g.ref.path,
              error: e,
            });
          }
        }
        return docs;
      }
    }
    const templateDocs = await loadActiveTemplates();

    // Canon maps: short names and chapter counts
    const OT = [
      ['Gen', 50], ['Ex', 40], ['Lev', 27], ['Num', 36], ['Deut', 34],
      ['Josh', 24], ['Judg', 21], ['Ruth', 4], ['1Sam', 31], ['2Sam', 24],
      ['1Kgs', 22], ['2Kgs', 25], ['1Chr', 29], ['2Chr', 36], ['Ezra', 10],
      ['Neh', 13], ['Esth', 10], ['Job', 42], ['Psalm', 150], ['Prov', 31],
      ['Eccl', 12], ['Song', 8], ['Isa', 66], ['Jer', 52], ['Lam', 5],
      ['Ezek', 48], ['Dan', 12], ['Hos', 14], ['Joel', 3], ['Amos', 9],
      ['Obad', 1], ['Jonah', 4], ['Mic', 7], ['Nah', 3], ['Hab', 3],
      ['Zeph', 3], ['Hag', 2], ['Zech', 14], ['Mal', 4],
    ];
    const NT = [
      ['Matt', 28], ['Mark', 16], ['Luke', 24], ['John', 21], ['Acts', 28],
      ['Rom', 16], ['1Cor', 16], ['2Cor', 13], ['Gal', 6], ['Eph', 6],
      ['Phil', 4], ['Col', 4], ['1Thess', 5], ['2Thess', 3], ['1Tim', 6],
      ['2Tim', 4], ['Titus', 3], ['Phlm', 1], ['Heb', 13], ['Jas', 5],
      ['1Pet', 5], ['2Pet', 3], ['1John', 5], ['2John', 1], ['3John', 1],
      ['Jude', 1], ['Rev', 22],
    ];
    const PSALMS = [['Psalm', 150]];

    function parseRef(ref, canon) {
      // Expect formats like "Gen 1"
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

    function formatRef(idx, chap, canon) {
      return `${canon[idx][0]} ${chap}`;
    }

    function nextChapters(startRef, count, canon) {
      const start = parseRef(startRef, canon) || { idx: 0, chap: 1 };
      let i = start.idx;
      let c = start.chap;
      const out = [];
      for (let k = 0; k < count; k++) {
        out.push(formatRef(i, c, canon));
        c += 1;
        const max = canon[i][1];
        if (c > max) {
          i += 1;
          if (i >= canon.length) break; // End of canon
          c = 1;
        }
      }
      return out;
    }

    function weekdayCode(d) {
      // JS: 0=Sun..6=Sat -> RFC: SU..SA
      return ['SU','MO','TU','WE','TH','FR','SA'][d];
    }

    const tasks = [];
    templateDocs.forEach((doc) => {
      const data = doc.data() || {};
      const timeZone = (data.timezone || 'UTC').toString();
      const { y, m, d } = localDateParts(new Date(), timeZone);
      const dateKey = `${y.toString().padStart(4, '0')}-${m
        .toString()
        .padStart(2, '0')}-${d.toString().padStart(2, '0')}`;
      const utcMidnight = new Date(Date.UTC(y, m - 1, d));
      const groupRef = doc.ref.parent.parent; // groups/{groupId}
      if (!groupRef) return;
      // Respect weekdays if provided (e.g., ['MO','TU','WE','TH','FR','SA'])
      const allowedDays = Array.isArray(data.weekdays) ? data.weekdays : null;
      if (allowedDays) {
        const code = weekdayCode(new Date(Date.UTC(y, m - 1, d)).getUTCDay());
        // Convert local weekday to code by recomputing in timeZone
        try {
          const wdFmt = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short' });
          const wd = wdFmt.format(new Date(Date.UTC(y, m - 1, d))).slice(0,2).toUpperCase();
          const map = { SU:'SU', MO:'MO', TU:'TU', WE:'WE', TH:'TH', FR:'FR', SA:'SA' };
          const localCode = map[wd] || code;
          if (!allowedDays.includes(localCode)) return; // skip non-scheduled day
        } catch (_) {
          if (!allowedDays.includes(code)) return;
        }
      }
      const templateRef = doc.ref;
      const scheduleRef = groupRef.collection('schedule').doc(dateKey);
      tasks.push(db.runTransaction(async (tx) => {
        const tSnap = await tx.get(templateRef);
        const tData = tSnap.data() || {};
        const plan = (tData.plan || '').toString();
        const perDay = Number(tData.chaptersPerDay || 0);
        let chapters = [];
        if (perDay > 0 && (plan === 'sequential_ot' || plan === 'sequential_nt' || plan === 'psalms')) {
          const canon = plan === 'sequential_nt' ? NT : (plan === 'psalms' ? PSALMS : OT);
          // Use per-template cursorRef if present; otherwise startRef.
          let startRef = (tData.cursorRef || tData.startRef || 'Gen 1').toString();
          chapters = nextChapters(startRef, perDay, canon);
          // Compute next cursor after today's assignment
          const last = chapters[chapters.length - 1];
          const p = parseRef(last, canon);
          if (p) {
            const max = canon[p.idx][1];
            const next = p.chap < max ? formatRef(p.idx, p.chap + 1, canon)
              : (p.idx + 1 < canon.length ? formatRef(p.idx + 1, 1, canon) : last);
            tx.update(templateRef, { cursorRef: next });
          }
        }

        const sSnap = await tx.get(scheduleRef);
        if (!sSnap.exists) {
          tx.set(scheduleRef, {
            date: admin.firestore.Timestamp.fromDate(utcMidnight),
            chapters,
            _source: 'auto',
          });
        } else if (Array.isArray(chapters) && chapters.length > 0) {
          const existing = Array.isArray(sSnap.data().chapters)
            ? sSnap.data().chapters : [];
          const merged = existing.concat(chapters).filter((v, i, a) => a.indexOf(v) === i);
          tx.update(scheduleRef, { chapters: merged });
        }
      }).catch((err) => {
        functions.logger.warn('Txn failed for schedule/template', {
          group: groupRef.path,
          template: templateRef.path,
          dateKey,
          error: err,
        });
      }));
    });

    // Limit concurrency to avoid overwhelming Firestore (simple chunking)
    const chunkSize = 25;
    for (let i = 0; i < tasks.length; i += chunkSize) {
      const chunk = tasks.slice(i, i + chunkSize);
      // eslint-disable-next-line no-await-in-loop
      await Promise.all(chunk);
    }

    return null;
  });

/** Callable: materialize today's schedule for a group (optionally a single template). */
exports.materializeToday = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');
  }
  const db = admin.firestore();
  const { groupId, templateId } = req.data || {};
  if (!groupId) {
    throw new functions.https.HttpsError('invalid-argument', 'groupId required');
  }
  const uid = req.auth.uid;
  const groupRef = db.collection('groups').doc(groupId);
  const group = await groupRef.get();
  if (!group.exists) {
    throw new functions.https.HttpsError('not-found', 'Group not found');
  }
  const isOwner = group.data()?.ownerUid === uid;
  const member = await groupRef.collection('members').doc(uid).get();
  const role = member.data()?.role;
  const isAdmin = role === 'admin' || role === 'owner';
  if (!isOwner && !isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Owner/admin only');
  }

  let templates;
  if (templateId) {
    const t = await groupRef.collection('scheduleTemplates').doc(templateId).get();
    if (!t.exists) throw new functions.https.HttpsError('not-found', 'Template not found');
    templates = [{ ref: t.ref, data: t.data() }];
  } else {
    const snap = await groupRef.collection('scheduleTemplates').where('active', '==', true).get();
    templates = snap.docs.map((d) => ({ ref: d.ref, data: d.data() }));
  }

  // Reuse logic from scheduler: local date, weekdays, canon, cursor update
  const now = new Date();
  function localDateParts(date, timeZone) {
    try {
      const fmt = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
      const parts = fmt.formatToParts(date);
      const y = Number(parts.find((p) => p.type === 'year')?.value);
      const m = Number(parts.find((p) => p.type === 'month')?.value);
      const d = Number(parts.find((p) => p.type === 'day')?.value);
      return { y, m, d };
    } catch {
      return { y: now.getUTCFullYear(), m: now.getUTCMonth() + 1, d: now.getUTCDate() };
    }
  }
  const OT = [['Gen',50],['Ex',40],['Lev',27],['Num',36],['Deut',34],['Josh',24],['Judg',21],['Ruth',4],['1Sam',31],['2Sam',24],['1Kgs',22],['2Kgs',25],['1Chr',29],['2Chr',36],['Ezra',10],['Neh',13],['Esth',10],['Job',42],['Psalm',150],['Prov',31],['Eccl',12],['Song',8],['Isa',66],['Jer',52],['Lam',5],['Ezek',48],['Dan',12],['Hos',14],['Joel',3],['Amos',9],['Obad',1],['Jonah',4],['Mic',7],['Nah',3],['Hab',3],['Zeph',3],['Hag',2],['Zech',14],['Mal',4]];
  const NT = [['Matt',28],['Mark',16],['Luke',24],['John',21],['Acts',28],['Rom',16],['1Cor',16],['2Cor',13],['Gal',6],['Eph',6],['Phil',4],['Col',4],['1Thess',5],['2Thess',3],['1Tim',6],['2Tim',4],['Titus',3],['Phlm',1],['Heb',13],['Jas',5],['1Pet',5],['2Pet',3],['1John',5],['2John',1],['3John',1],['Jude',1],['Rev',22]];
  const PSALMS = [['Psalm',150]];
  function parseRef(ref, canon){ if(!ref||typeof ref!=='string')return null; const parts=ref.trim().split(/\s+/); if(parts.length<2)return null; const book=parts[0]; const chap=Number(parts[1]); if(!Number.isFinite(chap))return null; const idx=canon.findIndex(([n])=>n===book); if(idx===-1)return null; return {idx,chap}; }
  function formatRef(idx,chap,canon){ return `${canon[idx][0]} ${chap}`; }
  function nextChapters(startRef,count,canon){ const start=parseRef(startRef,canon)||{idx:0,chap:1}; let i=start.idx; let c=start.chap; const out=[]; for(let k=0;k<count;k++){ out.push(formatRef(i,c,canon)); c+=1; const max=canon[i][1]; if(c>max){ i+=1; if(i>=canon.length)break; c=1; } } return out; }
  function weekdayCode(d){ return ['SU','MO','TU','WE','TH','FR','SA'][d]; }

  const results = [];
  for (const t of templates) {
    const data = t.data || {};
    const tz = (data.timezone || 'UTC').toString();
    const allowedDays = Array.isArray(data.weekdays) ? data.weekdays : null;
    const { y, m, d } = localDateParts(now, tz);
    // Check weekday
    if (allowedDays) {
      try {
        const wdFmt = new Intl.DateTimeFormat('en-US', { timeZone: tz, weekday: 'short' });
        const wd = wdFmt.format(new Date(Date.UTC(y, m - 1, d))).slice(0,2).toUpperCase();
        const map = { SU:'SU', MO:'MO', TU:'TU', WE:'WE', TH:'TH', FR:'FR', SA:'SA' };
        if (!allowedDays.includes(map[wd] || wd)) continue;
      } catch {}
    }
    const dateKey = `${y.toString().padStart(4,'0')}-${m.toString().padStart(2,'0')}-${d.toString().padStart(2,'0')}`;
    const scheduleRef = groupRef.collection('schedule').doc(dateKey);
    const plan = (data.plan || '').toString();
    const perDay = Number(data.chaptersPerDay || 0);
    const canon = plan === 'sequential_nt' ? NT : (plan === 'psalms' ? PSALMS : OT);
    let chapters = [];
    if (perDay > 0 && (plan === 'sequential_ot' || plan === 'sequential_nt' || plan === 'psalms')) {
      const startRef = (data.cursorRef || data.startRef || (canon[0][0] + ' 1')).toString();
      chapters = nextChapters(startRef, perDay, canon);
      const last = chapters[chapters.length - 1];
      const p = parseRef(last, canon);
      if (p) {
        const max = canon[p.idx][1];
        const next = p.chap < max ? formatRef(p.idx, p.chap + 1, canon)
          : (p.idx + 1 < canon.length ? formatRef(p.idx + 1, 1, canon) : last);
        await t.ref.set({ cursorRef: next }, { merge: true });
      }
    }
    const sSnap = await scheduleRef.get();
    if (!sSnap.exists) {
      await scheduleRef.set({
        date: admin.firestore.Timestamp.fromDate(new Date(Date.UTC(y, m - 1, d))),
        chapters,
        _source: 'auto',
      });
    } else if (chapters.length > 0) {
      const existing = Array.isArray(sSnap.data().chapters) ? sSnap.data().chapters : [];
      const merged = existing.concat(chapters).filter((v, i, a) => a.indexOf(v) === i);
      await scheduleRef.set({ chapters: merged }, { merge: true });
    }
    results.push({ template: t.ref.id, dateKey });
  }
  return { success: true, results };
});

/** Callable: reset a plan's next chapter (cursor) to a specific ref. */
exports.resetPlanCursor = onCall({ region: 'us-central1' }, async (req) => {
  if (!req.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign in required');
  }
  const { groupId, templateId, cursorRef } = req.data || {};
  if (!groupId || !templateId || !cursorRef) {
    throw new functions.https.HttpsError('invalid-argument', 'groupId, templateId, cursorRef required');
  }
  const db = admin.firestore();
  const uid = req.auth.uid;
  const groupRef = db.collection('groups').doc(groupId);
  const group = await groupRef.get();
  if (!group.exists) throw new functions.https.HttpsError('not-found', 'Group not found');
  const isOwner = group.data()?.ownerUid === uid;
  const member = await groupRef.collection('members').doc(uid).get();
  const role = member.data()?.role;
  const isAdmin = role === 'admin' || role === 'owner';
  if (!isOwner && !isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Owner/admin only');
  }
  await groupRef.collection('scheduleTemplates').doc(templateId)
    .set({ cursorRef: cursorRef.toString() }, { merge: true });
  return { success: true };
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
