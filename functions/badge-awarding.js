const admin = require('firebase-admin');
const {
  getFcmToken,
  isNotificationEnabled,
  sendNotification,
} = require('./notification-utils');

// ---------------------------------------------------------------------------
// Badge awarding.
//
// Badges live at `users/{uid}/achievements/{id}` and are awarded only here,
// server-side — the security rules deny every client write to that collection
// (see firestore.rules). One trigger feeds each family:
//
//   * awardReadThroughBadges — onCreate of users/{uid}/read_throughs/{id};
//     badges follow the read-through ledger's totals, exactly as the client
//     implementation did, and a deletion only ever lowers a count, which
//     never takes a badge away.
//   * awardFirstBookBadge — onCreate of users/{uid}/bible_books/{book};
//     that collection only ever holds completed books.
//   * awardConsistencyBadges — onWrite of users/{uid}/summary/data; the
//     Showing-up summary's `totalReadDays` counts days shown up however the
//     reader marked them, with or without a Plan.
//   * awardPlanFinishedBadge — onWrite of users/{uid}/plan_progress/{planId};
//     a Plan is finished when its progress covers every day of its schedule.
//
// A badge is created once: batch.create fails when the document already
// exists, so a re-run (or an at-least-once redelivery) never re-awards a
// badge or moves its unlock time. The unlock notification document is written
// in the same batch, so an awarded badge is always announced exactly once.
// The member's latest badge is mirrored into groups/{g}/badges/{uid} for each
// of their groups — the path co-members can read (ADR-0004).
// ---------------------------------------------------------------------------
// The achievements backfill (backfill-achievements.js) reuses awardBadges
// but must stay silent: awarding a reader milestones they earned long ago
// must not drop a stack of stale "Badge unlocked" notifications on them. It
// sets this flag for the duration of its settle calls; trigger paths never
// touch it and always announce.
const BACKFILL_QUIET = Symbol.for('backfill-achievements.quiet');
function isBackfillQuiet() {
  return globalThis[BACKFILL_QUIET] === true;
}

/**
 * Awards every badge in [earned] that [uid] does not hold yet — announcing
 * each in the reader's notifications in the same batch — then mirrors the
 * biggest one into each of the reader's groups. Any refusal of the durable
 * write rejects: nothing here is swallowed.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 * @param {Array<{id: string, type: string, rank: number, title: string}>} earned Badges due.
 */
async function awardBadges(db, uid, earned) {
  if (earned.length === 0) return;
  const userDoc = db.collection('users').doc(uid);
  const achievements = userDoc.collection('achievements');
  const held = await achievements.get();
  const heldIds = new Set(held.docs.map((d) => d.id));
  const missing = earned.filter((b) => !heldIds.has(b.id));
  if (missing.length === 0) return;

  const batch = db.batch();
  const notifications = userDoc.collection('notifications');
  for (const badge of missing) {
    batch.create(achievements.doc(badge.id), {
      type: badge.type,
      dateUnlocked: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (!isBackfillQuiet()) {
      batch.set(notifications.doc(), {
        type: 'badge',
        read: false,
        message: `Badge unlocked — ${badge.title}.`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
  await batch.commit();

  await mirrorLatestBadge(db, uid, missing);
  if (!isBackfillQuiet()) {
    await pushBadgeUnlock(db, uid, missing);
  }
}

// The catalogue — every badge the server can award, as data. `type` is the
// family stored on the achievement document; `rank` breaks ties when several
// badges unlock in the same batch: the mirror shows the biggest. Display
// resolves client-side against the reader-facing Badge catalogue.
const BADGES = [
  // Completion — a first book and finished Testaments.
  {
    id: 'first_book',
    family: 'completion',
    type: 'achievement',
    rank: 0,
    title: 'First Book',
  },
  {
    id: 'first_ot',
    family: 'completion',
    type: 'read_through',
    rank: 1,
    oldTestaments: 1,
    title: 'First Old Testament',
  },
  {
    id: 'first_nt',
    family: 'completion',
    type: 'read_through',
    rank: 1,
    newTestaments: 1,
    title: 'First New Testament',
  },
  {
    id: 'first_bible',
    family: 'completion',
    type: 'read_through',
    rank: 2,
    wholeBibles: 1,
    title: 'First Whole Bible',
  },
  {
    id: 'bible_5',
    family: 'completion',
    type: 'read_through',
    rank: 3,
    wholeBibles: 5,
    title: 'Five Whole Bibles',
  },
  {
    id: 'bible_10',
    family: 'completion',
    type: 'read_through',
    rank: 4,
    wholeBibles: 10,
    title: 'Ten Whole Bibles',
  },
  // Consistency — days shown up, with or without a Plan.
  {
    id: 'days_7',
    family: 'consistency',
    type: 'consistency',
    rank: 1,
    daysShownUp: 7,
    title: '7 Days of Showing Up',
  },
  {
    id: 'days_30',
    family: 'consistency',
    type: 'consistency',
    rank: 2,
    daysShownUp: 30,
    title: '30 Days of Showing Up',
  },
  {
    id: 'days_50',
    family: 'consistency',
    type: 'consistency',
    rank: 3,
    daysShownUp: 50,
    title: '50 Days of Showing Up',
  },
  {
    id: 'days_100',
    family: 'consistency',
    type: 'consistency',
    rank: 4,
    daysShownUp: 100,
    title: '100 Days of Showing Up',
  },
  {
    id: 'days_365',
    family: 'consistency',
    type: 'consistency',
    rank: 5,
    daysShownUp: 365,
    title: '365 Days of Showing Up',
  },
  // Plan — finished a Plan.
  {
    id: 'plan_finished',
    family: 'plan',
    type: 'plan',
    rank: 6,
    title: 'Finished a Plan',
  },
];

/**
 * Awards every badge in [earned] that [uid] does not hold yet — announcing
 * each in the reader's notifications in the same batch — then mirrors the
 * biggest one into each of the reader's groups. Any refusal of the durable
 * write rejects: nothing here is swallowed.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 * @param {Array<{id: string, type: string, rank: number, title: string}>} earned Badges due.
 */
async function awardBadges(db, uid, earned) {
  if (earned.length === 0) return;
  const userDoc = db.collection('users').doc(uid);
  const achievements = userDoc.collection('achievements');
  const held = await achievements.get();
  const heldIds = new Set(held.docs.map((d) => d.id));
  const missing = earned.filter((b) => !heldIds.has(b.id));
  if (missing.length === 0) return;

  const batch = db.batch();
  const notifications = userDoc.collection('notifications');
  for (const badge of missing) {
    batch.create(achievements.doc(badge.id), {
      type: badge.type,
      dateUnlocked: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (!isBackfillQuiet()) {
      batch.set(notifications.doc(), {
        type: 'badge',
        read: false,
        message: `Badge unlocked — ${badge.title}.`,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
  await batch.commit();

  await mirrorLatestBadge(db, uid, missing);
  if (!isBackfillQuiet()) {
    await pushBadgeUnlock(db, uid, missing);
  }
}

/**
 * Best-effort FCM push about the unlocked badges. The durable notification
 * documents are already written by [awardBadges]; a push failure is logged,
 * not surfaced — the reader is still notified in the app.
 */
async function pushBadgeUnlock(db, uid, badges) {
  try {
    const [enabled, token] = await Promise.all([
      isNotificationEnabled(uid, 'badge'),
      getFcmToken(uid),
    ]);
    if (!enabled || !token) return;
    const title =
      badges.length === 1 ? 'Badge unlocked' : `${badges.length} badges unlocked`;
    await sendNotification(token, {
      title,
      body: badges.map((b) => b.title).join(', '),
      data: { type: 'badge' },
    });
  } catch (err) {
    console.error('Failed to push badge unlock notification', err);
  }
}

/**
 * Points groups/{g}/badges/{uid} at the biggest badge just awarded — the
 * read-time answer to "latest" for the member's co-members.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 * @param {Array<{id: string, type: string, rank: number}>} missing New badges.
 */
async function mirrorLatestBadge(db, uid, missing) {
  const latest = missing.reduce((a, b) => (b.rank > a.rank ? b : a));
  const memberships = await db
    .collectionGroup('members')
    .where('uid', '==', uid)
    .get();
  await Promise.all(
    memberships.docs.map((doc) => {
      const groupId = doc.ref.parent.parent.id;
      return db
        .collection('groups')
        .doc(groupId)
        .collection('badges')
        .doc(uid)
        .set({
          badgeId: latest.id,
          type: latest.type,
          dateUnlocked: admin.firestore.FieldValue.serverTimestamp(),
        });
    })
  );
}

/**
 * Settles the completion family for [uid] against the read-through ledger's
 * current totals. Whole-Bible counts derive as min(OT, NT).
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 */
async function settleReadThroughBadges(db, uid) {
  const rows = await db
    .collection('users')
    .doc(uid)
    .collection('read_throughs')
    .get();
  const counts = { oldTestaments: 0, newTestaments: 0 };
  for (const row of rows.docs) {
    const scope = row.data().scope;
    if (scope === 'ot') counts.oldTestaments += 1;
    if (scope === 'nt') counts.newTestaments += 1;
  }
  const wholeBibles = Math.min(counts.oldTestaments, counts.newTestaments);
  const earned = BADGES.filter((badge) => {
    if (badge.family !== 'completion' || !badge.type.match(/read_through/))
      return false;
    if (badge.wholeBibles) return wholeBibles >= badge.wholeBibles;
    if (badge.oldTestaments) return counts.oldTestaments >= badge.oldTestaments;
    return counts.newTestaments >= badge.newTestaments;
  });
  await awardBadges(db, uid, earned);
}

/**
 * Awards first_book when [uid]'s newly completed book is their first. The
 * collection only ever holds completed books, so one document means first.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 */
async function settleFirstBookBadge(db, uid) {
  const books = await db
    .collection('users')
    .doc(uid)
    .collection('bible_books')
    .get();
  if (books.size !== 1) return;
  await awardBadges(db, uid, [
    BADGES.find((badge) => badge.id === 'first_book'),
  ]);
}

/**
 * Settles the consistency family for [uid] against the Showing-up summary's
 * cumulative total — days shown up count however the day was marked, with or
 * without a Plan.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 * @param {number} daysShownUp Total days shown up.
 */
async function settleConsistencyBadges(db, uid, daysShownUp) {
  if (typeof daysShownUp !== 'number' || !Number.isFinite(daysShownUp)) return;
  const earned = BADGES.filter(
    (badge) =>
      badge.family === 'consistency' && daysShownUp >= badge.daysShownUp,
  );
  await awardBadges(db, uid, earned);
}

/**
 * Settles the plan family for [uid] and [planId]: a Plan is finished when
 * its progress covers every day of the plan's schedule. When the plan
 * definition cannot be read, completion cannot be verified — nothing is
 * awarded rather than guessing.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 * @param {string} planId Plan document id.
 */
async function settlePlanFinishedBadge(db, uid, planId) {
  const progressSnap = await db
    .collection('users')
    .doc(uid)
    .collection('plan_progress')
    .doc(planId)
    .get();
  if (!progressSnap.exists) return;
  const completedDays = progressSnap.data().completedDays ?? [];

  const planSnap = await db.collection('custom_plans').doc(planId).get();
  if (!planSnap.exists) return;
  const plan = planSnap.data() ?? {};
  const totalDays =
    Array.isArray(plan.schedule) && plan.schedule.length > 0
      ? plan.schedule.length
      : (plan.durationDays ?? 0);
  if (!totalDays) return;
  if (completedDays.length < totalDays) return;

  await awardBadges(db, uid, [
    BADGES.find((badge) => badge.id === 'plan_finished'),
  ]);
}

module.exports = {
  BADGES,
  awardBadges,
  isBackfillQuiet,
  settleReadThroughBadges,
  settleFirstBookBadge,
  settleConsistencyBadges,
  settlePlanFinishedBadge,
};
