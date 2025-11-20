const admin = require('firebase-admin');

const pad = (value) => String(value).padStart(2, '0');
const formatDateKey = (date) =>
  `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
const formatMonthKey = (date) => `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}`;

const getPreviousMonthRange = (now = new Date()) => {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  return { start, end };
};

const getSummarySnapshot = async (db, uid) =>
  db.collection('users').doc(uid).collection('summary').doc('data').get();

const collectReadDatesFromSummary = async (db, uid, start, end) => {
  const snap = await getSummarySnapshot(db, uid);
  if (!snap.exists) {
    return { dates: new Set(), graceUsed: null };
  }

  const data = typeof snap.data === 'function' ? snap.data() : snap.data;
  const rawDates = Array.isArray(data?.pastMonthReadDates) ? data.pastMonthReadDates : [];
  const dates = new Set();
  const startTime = start.getTime();
  const endTime = end.getTime();

  for (const value of rawDates) {
    const parsed = new Date(value);
    const ts = parsed.getTime();
    if (Number.isNaN(ts)) continue;
    if (ts >= startTime && ts < endTime) {
      dates.add(formatDateKey(parsed));
    }
  }

  const targetMonthKey = formatMonthKey(start);
  const graceUsed =
    data?.graceCreditsMonth === targetMonthKey && typeof data?.graceCreditsUsed === 'number'
      ? data.graceCreditsUsed
      : null;

  return { dates, graceUsed };
};

const queryReadDatesFromReading = async (db, uid, start, end) => {
  const startKey = formatDateKey(start);
  const lastDay = new Date(end.getTime());
  lastDay.setUTCDate(lastDay.getUTCDate() - 1);
  const endKey = formatDateKey(lastDay);

  const snapshot = await db
    .collection('users')
    .doc(uid)
    .collection('reading')
    .where(admin.firestore.FieldPath.documentId(), '>=', startKey)
    .where(admin.firestore.FieldPath.documentId(), '<=', endKey)
    .get();

  const dates = new Set();
  snapshot.forEach((doc) => {
    const data = typeof doc.data === 'function' ? doc.data() : doc.data;
    if (data?.read) {
      dates.add(doc.id);
    }
  });
  return dates;
};

const queryReadDatesFromReadLogs = async (db, uid, start, end, existingDates = new Set()) => {
  const dates = new Set(existingDates);
  const cursor = new Date(start.getTime());
  while (cursor.getTime() < end.getTime()) {
    const key = formatDateKey(cursor);
    if (!dates.has(key)) {
      try {
        const entrySnap = await db.collection('read_logs').doc(key).collection('entries').doc(uid).get();
        if (entrySnap.exists) {
          dates.add(key);
        }
      } catch (err) {
        // ignore read_log gaps
      }
    }
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return dates;
};

const createLedger = (monthStart) => {
  const base = new Date(Date.UTC(monthStart.getUTCFullYear(), monthStart.getUTCMonth(), monthStart.getUTCDate()));
  const credits = [
    { earnedOn: base, used: false },
    { earnedOn: base, used: false },
  ];

  return {
    used: 0,
    addBonusCredit(date) {
      credits.push({ earnedOn: new Date(date.getTime()), used: false });
    },
    trySpend(date) {
      for (const credit of credits) {
        if (credit.used) continue;
        if (credit.earnedOn.getTime() > date.getTime()) continue;
        credit.used = true;
        this.used += 1;
        return true;
      }
      return false;
    },
  };
};

const computeMonthlyCoverage = (dates, start, end, presetGraceUsed = null) => {
  const ledger = createLedger(start);
  const streakSegments = [];
  let streak = 0;
  let graceUsed = 0;
  let activeSegment = null;

  const cursor = new Date(start.getTime());
  while (cursor.getTime() < end.getTime()) {
    const dateKey = formatDateKey(cursor);
    const readToday = dates.has(dateKey);
    const usedGrace = !readToday && streak > 0 && ledger.trySpend(cursor);
    const covered = readToday || usedGrace;

    if (covered) {
      streak += 1;
      if (readToday && streak % 15 === 0) {
        ledger.addBonusCredit(cursor);
      }
      if (!activeSegment) {
        activeSegment = { start: dateKey, end: dateKey, length: 1, graceDays: usedGrace ? 1 : 0 };
      } else {
        activeSegment.end = dateKey;
        activeSegment.length += 1;
        if (usedGrace) {
          activeSegment.graceDays += 1;
        }
      }
      if (usedGrace) {
        graceUsed += 1;
      }
    } else if (activeSegment) {
      streakSegments.push(activeSegment);
      activeSegment = null;
      streak = 0;
    } else {
      streak = 0;
    }

    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }

  if (activeSegment) {
    streakSegments.push(activeSegment);
  }

  return { streakSegments, graceDaysUsed: presetGraceUsed ?? graceUsed };
};

const getPreviousMonthStats = async (db, uid, now = new Date()) => {
  const { start, end } = getPreviousMonthRange(now);
  const summaryResult = await collectReadDatesFromSummary(db, uid, start, end);

  let readDates = summaryResult.dates;
  if (readDates.size === 0) {
    readDates = await queryReadDatesFromReading(db, uid, start, end);
  }

  readDates = await queryReadDatesFromReadLogs(db, uid, start, end, readDates);
  const coverage = computeMonthlyCoverage(readDates, start, end, summaryResult.graceUsed);

  return {
    monthKey: formatMonthKey(start),
    daysRead: readDates.size,
    streakSegments: coverage.streakSegments,
    graceDaysUsed: coverage.graceDaysUsed,
  };
};

module.exports = {
  computeMonthlyCoverage,
  collectReadDatesFromSummary,
  getPreviousMonthRange,
  getPreviousMonthStats,
  queryReadDatesFromReadLogs,
  queryReadDatesFromReading,
};
