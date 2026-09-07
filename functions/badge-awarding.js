const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
// Badge awarding.
//
// Badges live at `users/{uid}/achievements/{id}` and are awarded only here,
// server-side — the security rules deny every client write to that collection
// (see firestore.rules). Two triggers feed this module:
//
//   * awardReadThroughBadges — onCreate of users/{uid}/read_throughs/{id};
//     badges follow the read-through ledger's totals, exactly as the client
//     implementation did, and a deletion only ever lowers a count, which
//     never takes a badge away.
//   * awardFirstBookBadge — onCreate of users/{uid}/bible_books/{book};
//     that collection only ever holds completed books.
//
// A badge is created once: batch.create fails when the document already
// exists, so a re-run (or an at-least-once redelivery) never re-awards a
// badge or moves its unlock time. The member's latest badge is mirrored into
// groups/{g}/badges/{uid} for each of their groups — the path co-members can
// read (ADR-0004).
// ---------------------------------------------------------------------------

// The award-side catalogue for the read-through family, matching the client's
// `BadgeDefinition.all`. Badge documents carry the id and the unlock time;
// display resolves client-side. `rank` breaks ties when several badges unlock
// in the same batch: the mirror shows the biggest.
const READ_THROUGH_BADGES = [
  { id: 'first_ot', type: 'read_through', rank: 1, oldTestaments: 1 },
  { id: 'first_nt', type: 'read_through', rank: 1, newTestaments: 1 },
  { id: 'first_bible', type: 'read_through', rank: 2, wholeBibles: 1 },
  { id: 'bible_5', type: 'read_through', rank: 3, wholeBibles: 5 },
  { id: 'bible_10', type: 'read_through', rank: 4, wholeBibles: 10 },
];

/**
 * Awards every badge in [earned] that [uid] does not hold yet, then mirrors
 * the biggest one into each of the reader's groups.
 * @param {FirebaseFirestore.Firestore} db Firestore handle.
 * @param {string} uid Reader id.
 * @param {Array<{id: string, type: string, rank: number}>} earned Badges due.
 */
async function awardBadges(db, uid, earned) {
  if (earned.length === 0) return;
  const achievements = db
    .collection('users')
    .doc(uid)
    .collection('achievements');
  const held = await achievements.get();
  const heldIds = new Set(held.docs.map((d) => d.id));
  const missing = earned.filter((b) => !heldIds.has(b.id));
  if (missing.length === 0) return;

  const batch = db.batch();
  for (const badge of missing) {
    batch.create(achievements.doc(badge.id), {
      type: badge.type,
      dateUnlocked: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  await mirrorLatestBadge(db, uid, missing);
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
 * Settles the read-through badge family for [uid] against the ledger's
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
  const earned = READ_THROUGH_BADGES.filter((badge) => {
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
    { id: 'first_book', type: 'achievement', rank: 0 },
  ]);
}

module.exports = { settleReadThroughBadges, settleFirstBookBadge };
