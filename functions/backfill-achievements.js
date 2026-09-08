const admin = require('firebase-admin');
const {
  BADGES,
  awardBadges,
  settleReadThroughBadges,
  settleConsistencyBadges,
  settlePlanFinishedBadge,
} = require('./badge-awarding');

// ---------------------------------------------------------------------------
// One-off, re-runnable backfill of Badges for existing readers (#805).
//
// The Firestore triggers in badge-awarding.js only fire on new writes, so
// readers with history predating them hold no badges at all. This pass walks
// every user and re-derives each badge family from the same sources the
// triggers use:
//
//   * completion  — the read_throughs ledger (first_ot/nt/bible tiers)
//                   and the bible_books ledger (first_book);
//   * consistency — the Showing-up summary's totalReadDays;
//   * plan        — every plan_progress document checked against its plan.
//
// It calls the same settle functions the triggers call, so a backfilled badge
// and a trigger-awarded one are indistinguishable. Idempotency is inherited
// from awardBadges: a badge document is written with batch.create, which
// fails when the document already exists, so a second run re-derives the same
// earned set, finds every badge already held, and writes nothing.
//
// Timestamps: awardBadges stamps dateUnlocked with a server timestamp — the
// backfill run's date, not a fabricated one. Where a crossing date cannot be
// recovered (the general case: consistency totals and read-through ledgers
// record state, not history), a real backfill date beats an invented past one.
//
// Silent by design (chosen on #805): awardBadges' unlock notifications are
// suppressed here via a process-level flag read in badge-awarding.js. A
// backfill burst would drop a stack of stale "Badge unlocked" notifications
// on long-standing readers for milestones earned long ago; the badges simply
// appear where badges are shown.
// ---------------------------------------------------------------------------

const BACKFILL_QUIET = Symbol.for('backfill-achievements.quiet');

/**
 * Runs [fn] with awardBadges' notification writes suppressed. Implemented as
 * a process-global flag because the settle functions are shared with the
 * Firestore triggers and their signatures must not grow a backfill-only
 * parameter that every trigger call site would have to pass.
 * @param {() => Promise<void>} fn Per-user settle calls.
 */
async function quietly(fn) {
  globalThis[BACKFILL_QUIET] = true;
  try {
    await fn();
  } finally {
    delete globalThis[BACKFILL_QUIET];
  }
}

/**
 * Backfills every derivable badge for one user. Each family settles
 * independently, so a failure reading one source still lets the others land;
 * the error then rejects to the caller.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 */
async function backfillUser(db, uid) {
  const userRef = db.collection('users').doc(uid);

  const [readThroughs, books, summary, progress] = await Promise.all([
    userRef.collection('read_throughs').get(),
    userRef.collection('bible_books').get(),
    userRef.collection('summary').doc('data').get(),
    userRef.collection('plan_progress').get(),
  ]);

  await quietly(async () => {
    if (!readThroughs.empty) {
      await settleReadThroughBadges(db, uid);
    }

    // Unlike the onCreate trigger — where "the write just made" the first
    // book — the backfill can see the whole ledger: any completed book is a
    // first book someone once earned.
    if (books.size > 0) {
      await awardFirstBook(db, uid);
    }

    const days = summary.data()?.totalReadDays;
    if (typeof days === 'number' && Number.isFinite(days)) {
      await settleConsistencyBadges(db, uid, days);
    }

    for (const doc of progress.docs) {
      await settlePlanFinishedBadge(db, uid, doc.id);
    }
  });
}

/**
 * The first-book settle, derived over the whole completed-books ledger. The
 * trigger version fires only while the collection holds exactly one book —
 * true when the onCreate it just handled was the first — which cannot express
 * "this reader completed books long ago". Here the catalogue rule is applied
 * directly: one or more completed books means first_book was earned.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 */
async function awardFirstBook(db, uid) {
  await awardBadges(db, uid, [
    BADGES.find((badge) => badge.id === 'first_book'),
  ]);
}

/**
 * The uids worth visiting: anyone holding at least one document in the
 * collections the badges derive from. Discovered from the sources rather
 * than the `users` collection, because a document that exists only as the
 * ancestor of subcollection documents does not appear in a parent
 * collection's listing — a reader could hold history yet have no profile
 * document of their own.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @returns {Promise<string[]>} Deduplicated reader ids.
 */
async function discoverUsers(db) {
  const uids = new Set();
  const sources = ['read_throughs', 'bible_books', 'plan_progress', 'summary'];
  for (const name of sources) {
    const snap = await db.collectionGroup(name).get();
    for (const doc of snap.docs) {
      const parts = doc.ref.path.split('/');
      if (parts[0] === 'users') uids.add(parts[1]);
    }
  }
  return [...uids];
}

/**
 * Backfills every reader with derivable history. Intended to be run once
 * against the emulator with seeded fixtures, then once against production;
 * re-running is always safe. Users are processed one at a time: a one-off
 * sweep has no deadline to meet, and a controlled pace is kinder to the
 * live database than a fan-out.
 * @param {FirebaseFirestore.Firestore} [db] Firestore handle; defaults to the
 *   Admin SDK's, so the script runs as-is via `node backfill-achievements.js`.
 * @returns {Promise<{users: number}>} Counters for the run log.
 */
async function main(db) {
  if (!db) {
    admin.initializeApp();
    db = admin.firestore();
  }
  const uids = await discoverUsers(db);
  for (const uid of uids) {
    await backfillUser(db, uid);
  }
  console.log(`Backfill complete: ${uids.length} users processed.`);
  return { users: uids.length };
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { backfillUser, main, quietly, BACKFILL_QUIET };