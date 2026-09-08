/**
 * One-off cleanup: drop the retired friend graph (ADR-0003, #800).
 *
 * The friend graph was announced and retired; Group is now the only
 * relationship primitive. This script deletes, for every user:
 *   - users/{uid}/friends
 *   - users/{uid}/friendRequestsSent
 *   - users/{uid}/friendRequestsReceived
 *   - users/{uid}/friendStreakInvites
 *   - users/{uid}/friendStreakLinks
 * and removes any `friendRequest` notifications still in their inbox.
 *
 * The `nudges` subcollection is NOT touched — it is the live nudge ledger.
 *
 * Usage (announce to users before running):
 *   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
 *     node drop-friend-graph.js
 */
const admin = require('firebase-admin');

let db;

const RETIRED_SUBCOLLECTIONS = [
  'friends',
  'friendRequestsSent',
  'friendRequestsReceived',
  'friendStreakInvites',
  'friendStreakLinks',
];

async function deleteDocDeep(ref) {
  if (admin.firestore && typeof admin.firestore().recursiveDelete === 'function') {
    await admin.firestore().recursiveDelete(ref);
  } else {
    await ref.delete();
  }
}

async function dropFriendGraphForUser(uid) {
  const userRef = db.collection('users').doc(uid);

  for (const name of RETIRED_SUBCOLLECTIONS) {
    const docs = await userRef.collection(name).listDocuments();
    await Promise.all(docs.map(deleteDocDeep));
  }

  // Prune any friendRequest notifications left in the inbox.
  const notifs = await userRef
    .collection('notifications')
    .where('type', '==', 'friendRequest')
    .get();
  await Promise.all(notifs.docs.map((d) => d.ref.delete()));
}

async function main() {
  admin.initializeApp();
  db = admin.firestore();
  const users = await db.collection('users').listDocuments();
  await Promise.all(users.map((u) => dropFriendGraphForUser(u.id)));
  console.log(`Friend graph dropped for ${users.length} users`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { RETIRED_SUBCOLLECTIONS, dropFriendGraphForUser, main };