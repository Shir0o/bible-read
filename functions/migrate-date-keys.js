const admin = require('firebase-admin');
let db;

function padKey(id) {
  const [y, m, d] = id.split('-').map(v => parseInt(v, 10));
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

async function migrateUser(uid) {
  const userRef = db.collection('users').doc(uid);

  const dayDocs = await userRef.collection('reading').listDocuments();
  for (const oldRef of dayDocs) {
    const oldKey = oldRef.id;
    const newKey = padKey(oldKey);
    if (oldKey === newKey) continue;
    const data = (await oldRef.get()).data();
    await userRef.collection('reading').doc(newKey).set(data || {});
    await oldRef.delete();
  }

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
  for (const oldDoc of logDocs) {
    const oldKey = oldDoc.id;
    const newKey = padKey(oldKey);
    if (oldKey === newKey) continue;

    const data = (await oldDoc.get()).data();
    const newDoc = db.collection('read_logs').doc(newKey);
    if (data) await newDoc.set(data);

    const entries = await oldDoc.collection('entries').get();
    for (const entry of entries.docs) {
      const entryRef = newDoc.collection('entries').doc(entry.id);
      await entryRef.set(entry.data());

      for (const sub of ['likes', 'comments']) {
        const subSnap = await entry.ref.collection(sub).get();
        for (const s of subSnap.docs) {
          await entryRef.collection(sub).doc(s.id).set(s.data());
        }
      }
    }
    await oldDoc.delete();
  }

  const rewards = await db.collection('daily_rewards').listDocuments();
  for (const oldRef of rewards) {
    const oldKey = oldRef.id;
    const newKey = padKey(oldKey);
    if (oldKey === newKey) continue;
    const data = (await oldRef.get()).data();
    if (data) await db.collection('daily_rewards').doc(newKey).set(data);
    await oldRef.delete();
  }
}

async function main() {
  admin.initializeApp();
  db = admin.firestore();
  const users = await db.collection('users').listDocuments();
  for (const user of users) await migrateUser(user.id);
  await migrateReadLogs();
  console.log('Migration complete');
}

if (require.main === module) {
  main().catch(err => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = { padKey, migrateUser, migrateReadLogs, main };
