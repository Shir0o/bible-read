// One-off emulator verification for the achievements backfill (#805).
//
// Seeds realistic fixtures into the running Firestore emulator, runs the
// backfill pass twice, and asserts with the Admin SDK against REAL Firestore
// semantics — serverTimestamp fields, collectionGroup discovery, batch.create
// uniqueness — that:
//   1. every derivable family lands (completion, consistency, plan);
//   2. the unlock stamps are real Timestamps of the backfill run;
//   3. the group mirror is written;
//   4. the second run is a no-op: nothing re-awarded, no stamp moved;
//   5. no notification documents exist after either run.
//
// Run with the emulator up: node verify-backfill-emulator.js
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.GOOGLE_CLOUD_PROJECT = 'demo-bible-read';
admin.initializeApp({ projectId: 'demo-bible-read' });
const db = admin.firestore();

const { main, backfillUser } = require('./backfill-achievements');

let failures = 0;
function check(label, ok, detail) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${ok || !detail ? '' : ` — ${detail}`}`);
  if (!ok) failures++;
}

async function badgeIds(uid) {
  const snap = await db.collection('users').doc(uid).collection('achievements').get();
  return snap.docs.map((d) => d.id).sort();
}

async function badgeDoc(uid, id) {
  const snap = await db.collection('users').doc(uid).collection('achievements').doc(id).get();
  return snap.exists ? snap.data() : null;
}

async function notificationCount(uid) {
  const snap = await db.collection('users').doc(uid).collection('notifications').get();
  return snap.size;
}

async function wipe() {
  // A verify run needs a clean slate: badges from a previous run would make
  // run 1 a no-op and the stamp assertions meaningless.
  for (const uid of ['alice', 'bob', 'carol']) {
    await admin.firestore().recursiveDelete(db.collection('users').doc(uid));
  }
  await admin.firestore().recursiveDelete(db.collection('groups'));
  await admin.firestore().recursiveDelete(db.collection('custom_plans'));
}

async function main_verify() {
  await wipe();
  // ---- Fixtures ----------------------------------------------------------
  // alice: read-throughs + Showing-up 52 days + a finished plan + a group.
  await db.doc('users/alice').set({ name: 'Alice' });
  await db.doc('users/alice/read_throughs/nt-1').set({ scope: 'nt', source: 'manual' });
  await db.doc('users/alice/read_throughs/ot-1').set({ scope: 'ot', source: 'manual' });
  await db.doc('users/alice/summary/data').set({
    totalReadDays: 52,
    streak: 9,
    pastMonthReadDates: [],
    pastWeekReadDates: [],
  });
  await db.doc('custom_plans/plan-alice').set({
    title: 'Gospel of John',
    durationDays: 2,
    schedule: [
      { day: 1, readings: ['John 1'] },
      { day: 2, readings: ['John 2'] },
    ],
  });
  await db.doc('users/alice/plan_progress/plan-alice').set({
    planId: 'plan-alice',
    userId: 'alice',
    startDate: admin.firestore.Timestamp.fromDate(new Date('2026-01-01')),
    completedDays: [1, 2],
    isArchived: false,
  });
  await db.doc('groups/g-alpha').set({ name: 'Alpha', ownerUid: 'alice' });
  await db.doc('groups/g-alpha/members/alice').set({ uid: 'alice', role: 'owner' });

  // bob: one completed book only — first_book, and nothing else.
  await db.doc('users/bob').set({ name: 'Bob' });
  await db.doc('users/bob/bible_books/Genesis').set({ completed: true, timestamp: admin.firestore.FieldValue.serverTimestamp() });

  // carol: mid-progress plan (not finished) + 3 days showing up.
  await db.doc('users/carol/summary/data').set({ totalReadDays: 3 });
  await db.doc('custom_plans/plan-carol').set({ title: 'Psalms', durationDays: 10 });
  await db.doc('users/carol/plan_progress/plan-carol').set({
    planId: 'plan-carol',
    userId: 'carol',
    startDate: admin.firestore.Timestamp.fromDate(new Date('2026-08-01')),
    completedDays: [1, 2, 3, 4],
    isArchived: false,
  });

  // ---- Run 1 -------------------------------------------------------------
  const before = Date.now();
  const result = await main(db);
  const after = Date.now();
  check('run 1 reports the three readers with history', result.users === 3, JSON.stringify(result));

  const alice1 = await badgeIds('alice');
  check('alice holds completion + consistency + plan badges', JSON.stringify(alice1) ===
    JSON.stringify(['days_30', 'days_50', 'days_7', 'first_bible', 'first_nt', 'first_ot', 'plan_finished']),
    JSON.stringify(alice1));

  const bob1 = await badgeIds('bob');
  check('bob holds first_book only', JSON.stringify(bob1) === JSON.stringify(['first_book']), JSON.stringify(bob1));

  // 3 days shown up crosses no tier (the first sits at 7) — nothing awarded.
  const carol1 = await badgeIds('carol');
  check('carol crosses no tier and holds no badges', carol1.length === 0, JSON.stringify(carol1));

  // Stamps are real timestamps of this run — not fabricated past dates.
  const stamp = (await badgeDoc('alice', 'days_50')).dateUnlocked;
  check('unlock stamp is a Firestore Timestamp', stamp && typeof stamp.toMillis === 'function', String(stamp));
  check('unlock stamp falls inside the run window',
    stamp.toMillis() >= before - 1000 && stamp.toMillis() <= after + 1000,
    `${stamp.toDate().toISOString()} vs ${new Date(before).toISOString()}..${new Date(after).toISOString()}`);

  const mirror = await db.doc('groups/g-alpha/badges/alice').get();
  check('the group mirror points at the biggest badge', mirror.exists && mirror.data().badgeId === 'plan_finished',
    mirror.exists ? mirror.data().badgeId : 'missing');

  check('no notification burst after run 1', (await notificationCount('alice')) === 0
    && (await notificationCount('bob')) === 0 && (await notificationCount('carol')) === 0);

  // ---- Run 2 — idempotency ----------------------------------------------
  await new Promise((r) => setTimeout(r, 1100)); // ensure a re-stamp would differ in ms
  await main(db);

  const alice2 = await badgeIds('alice');
  check('run 2 awards nothing new', JSON.stringify(alice2) === JSON.stringify(alice1), JSON.stringify(alice2));
  const stamp2 = (await badgeDoc('alice', 'days_50')).dateUnlocked;
  check('run 2 does not move the unlock time', stamp.toMillis() === stamp2.toMillis(),
    `${stamp.toMillis()} !== ${stamp2.toMillis()}`);
  check('run 2 writes no notifications', (await notificationCount('alice')) === 0);

  console.log(failures === 0 ? '\nEMULATOR VERIFICATION PASSED' : `\nEMULATOR VERIFICATION FAILED (${failures})`);
  process.exit(failures === 0 ? 0 : 1);
}

main_verify().catch((err) => {
  console.error(err);
  process.exit(1);
});