const admin = require('firebase-admin');
let db;

// Helper to delete a document and all of its subcollections recursively
async function deleteDocDeep(ref) {
  // Prefer recursive delete to avoid leaving subcollections behind
  if (admin.firestore && typeof admin.firestore().recursiveDelete === 'function') {
    await admin.firestore().recursiveDelete(ref);
  } else {
    // Fallback: best-effort single doc delete
    await ref.delete();
  }
}

function padKey(id) {
  const [y, m, d] = id.split('-').map(v => parseInt(v, 10));
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

async function migrateUser(uid) {
  const userRef = db.collection('users').doc(uid);

  const dayDocs = await userRef.collection('reading').listDocuments();
  await Promise.all(dayDocs.map(async (oldRef) => {
    const oldKey = oldRef.id;
    const newKey = padKey(oldKey);
    if (oldKey === newKey) return;
    const data = (await oldRef.get()).data();
    await userRef.collection('reading').doc(newKey).set(data || {});
    await oldRef.delete();
  }));

  const summaryRef = userRef.collection('summary').doc('data');
  const snap = await summaryRef.get();
  if (snap.exists) {
    const data = snap.data() || {};
    const fix = arr => Array.from(new Set((arr || []).map(padKey)));
    await summaryRef.update({
      pastWeekReadDates: fix(data.pastWeekReadDates),
      pastMonthReadDates: fix(data.pastMonthReadDates),
    });
  }
}

async function migrateReadLogs() {
  const logDocs = await db.collection('read_logs').listDocuments();
  await Promise.all(logDocs.map(async (oldDoc) => {
    const oldKey = oldDoc.id;
    const newKey = padKey(oldKey);
    if (oldKey === newKey) return;

    const data = (await oldDoc.get()).data();
    const newDoc = db.collection('read_logs').doc(newKey);
    if (data) await newDoc.set(data);

    const entries = await oldDoc.collection('entries').get();
    await Promise.all(entries.docs.map(async (entry) => {
      const entryRef = newDoc.collection('entries').doc(entry.id);
      await entryRef.set(entry.data());

      await Promise.all(['likes', 'comments'].map(async (sub) => {
        const subSnap = await entry.ref.collection(sub).get();
        await Promise.all(subSnap.docs.map(s =>
          entryRef.collection(sub).doc(s.id).set(s.data())
        ));
      }));
    }));
    await deleteDocDeep(oldDoc);
  }));

  const rewards = await db.collection('daily_rewards').listDocuments();
  await Promise.all(rewards.map(async (oldRef) => {
    const oldKey = oldRef.id;
    const newKey = padKey(oldKey);
    if (oldKey === newKey) return;
    const data = (await oldRef.get()).data();
    if (data) await db.collection('daily_rewards').doc(newKey).set(data);
    await deleteDocDeep(oldRef);
  }));
}

// Defensive cleanup to remove any lingering non–zero-padded docs
async function cleanupNonPaddedDates(collectionName) {
  const docs = await db.collection(collectionName).listDocuments();
  const padded = /^\d{4}-\d{2}-\d{2}$/;
  await Promise.all(docs.map(async (docRef) => {
    if (!padded.test(docRef.id)) {
      await deleteDocDeep(docRef);
    }
  }));
}

async function main() {
  admin.initializeApp();
  db = admin.firestore();
  const users = await db.collection('users').listDocuments();
  await Promise.all(users.map(user => migrateUser(user.id)));
  await migrateReadLogs();
  await cleanupNonPaddedDates('read_logs');
  await cleanupNonPaddedDates('daily_rewards');
  console.log('Migration complete');
}

if (require.main === module) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { padKey, migrateUser, migrateReadLogs, main };
