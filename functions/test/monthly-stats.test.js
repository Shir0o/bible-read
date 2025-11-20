const { describe, it } = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');
const { getPreviousMonthStats } = require('../monthly-stats');

admin.firestore = Object.assign(admin.firestore || (() => ({})), {
  FieldPath: { documentId: () => 'documentId' },
});

describe('getPreviousMonthStats', () => {
  const mayDate = new Date(Date.UTC(2024, 4, 15));

  const createDb = ({ summaryData, readingDocs = [], readLogDates = new Set() }) => ({
    collection(name) {
      if (name === 'users') {
        return {
          doc(uid) {
            return {
              collection(sub) {
                if (sub === 'summary') {
                  return {
                    doc(id) {
                      return {
                        async get() {
                          return summaryData
                            ? { exists: true, data: () => summaryData }
                            : { exists: false };
                        },
                      };
                    },
                  };
                }
                if (sub === 'reading') {
                  return {
                    where() {
                      return this;
                    },
                    async get() {
                      return {
                        forEach: (cb) => readingDocs.forEach(cb),
                      };
                    },
                  };
                }
                return {};
              },
            };
          },
        };
      }

      if (name === 'read_logs') {
        return {
          doc(dateKey) {
            return {
              collection(sub) {
                if (sub !== 'entries') return {};
                return {
                  doc(uid) {
                    return {
                      async get() {
                        return { exists: readLogDates.has(dateKey), data: () => ({ uid }) };
                      },
                    };
                  },
                };
              },
            };
          },
        };
      }

      return {};
    },
  });

  it('prefers summary data for the previous month when present', async () => {
    const db = createDb({
      summaryData: {
        pastMonthReadDates: ['2024-04-02'],
        graceCreditsMonth: '2024-04',
        graceCreditsUsed: 2,
      },
    });

    const stats = await getPreviousMonthStats(db, 'user123', mayDate);
    assert.equal(stats.daysRead, 1);
    assert.equal(stats.graceDaysUsed, 2);
    assert.deepEqual(stats.streakSegments.map((s) => s.length), [3]);
  });

  it('falls back to the reading collection when summary data is empty', async () => {
    const readingDocs = [
      { id: '2024-04-01', data: () => ({ read: true }) },
      { id: '2024-04-02', data: () => ({ read: true }) },
    ];
    const db = createDb({ summaryData: null, readingDocs });

    const stats = await getPreviousMonthStats(db, 'user123', mayDate);
    assert.equal(stats.daysRead, 2);
    assert.equal(stats.graceDaysUsed, 2);
    assert.deepEqual(stats.streakSegments.map((s) => s.length), [4]);
  });

  it('reads from read_logs when neither summary nor reading documents cover the month', async () => {
    const db = createDb({ summaryData: null, readingDocs: [], readLogDates: new Set(['2024-04-03']) });
    const stats = await getPreviousMonthStats(db, 'user123', mayDate);

    assert.equal(stats.daysRead, 1);
    assert.equal(stats.graceDaysUsed, 2);
    assert.deepEqual(stats.streakSegments.map((s) => s.length), [3]);
  });
});
