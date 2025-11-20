const {after, afterEach, beforeEach, describe, it} = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');
const sgMail = require('@sendgrid/mail');
const { resetSendgridCache } = require('../sendgrid-utils');
const monthlyStats = require('../monthly-stats');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
const originalFirestore = admin.firestore;
const originalAuth = admin.auth;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const myFunctions = require('../index');

process.env.NODE_ENV = 'test';

describe('sendMonthlyStatsEmail', () => {
  let sentMessages;
  let originalSend;
  let originalSetApiKey;
  let originalGetStats;
  let fakeUserRecord;

  const fakeEntryDoc = {
    id: 'user123',
    data: () => ({ chapters: ['John 1', 'John 2'] }),
    ref: { parent: { parent: { id: '2024-05-01' } } },
  };

  const fakeUserDoc = {
    id: 'user123',
    data: () => ({ email: 'reader@example.com', displayName: 'Reader' }),
  };

  const entriesQuery = {
    where() {
      return this;
    },
    async get() {
      return {
        size: 1,
        forEach: (cb) => cb(fakeEntryDoc),
      };
    },
  };

  const fakeDb = {
    collection(name) {
      if (name === 'users') {
        return {
          async get() {
            return { empty: false, docs: [fakeUserDoc] };
          },
        };
      }
      return {};
    },
    collectionGroup(name) {
      if (name === 'entries') {
        return entriesQuery;
      }
      return entriesQuery;
    },
  };

  beforeEach(() => {
    process.env.SENDGRID_API_KEY = 'test-key';
    process.env.SENDGRID_FROM = 'noreply@example.com';
    resetSendgridCache();

    sentMessages = [];
    originalSend = sgMail.send;
    originalSetApiKey = sgMail.setApiKey;
    originalGetStats = monthlyStats.getPreviousMonthStats;
    fakeUserRecord = { email: 'reader@example.com', emailVerified: true };
    fakeUserDoc.data = () => ({ email: 'reader@example.com', displayName: 'Reader' });

    sgMail.setApiKey = () => {};
    sgMail.send = async (message) => {
      sentMessages.push(message);
      return [{ statusCode: 202 }];
    };

    monthlyStats.getPreviousMonthStats = async () => ({
      monthKey: '2024-04',
      daysRead: 1,
      streakSegments: [{ start: '2024-04-01', end: '2024-04-01', length: 1, graceDays: 0 }],
      graceDaysUsed: 0,
    });

    admin.firestore = Object.assign(() => fakeDb, {
      Timestamp: { fromDate: () => ({}) },
      FieldPath: { documentId: () => 'documentId' },
    });
    admin.app = () => ({
      options: { projectId: 'demo' },
      auth() {
        return { getUser: async (uid) => ({ uid, ...fakeUserRecord }) };
      },
    });
    admin.auth = () => ({
      async getUser(uid) {
        return { uid, ...fakeUserRecord };
      },
    });
  });

  afterEach(() => {
    sgMail.send = originalSend;
    sgMail.setApiKey = originalSetApiKey;
    monthlyStats.getPreviousMonthStats = originalGetStats;
    admin.firestore = originalFirestore;
    admin.auth = originalAuth;
    admin.app = originalApp;

    resetSendgridCache();

    delete process.env.SENDGRID_API_KEY;
    delete process.env.SENDGRID_FROM;
  });

  it('sends a monthly summary email to each user', async () => {
    await myFunctions.sendMonthlyStatsEmail.run();

    assert.equal(sentMessages.length, 1);
    const [message] = sentMessages;
    assert.ok(message.subject.includes('reading summary'));
    assert.deepEqual(message.to, ['reader@example.com']);
    assert.match(message.text, /Days read: 1/);
    assert.match(message.text, /Grace days used: 0/);
  });

  it('skips users who opt out of monthly summaries', async () => {
    fakeUserDoc.data = () => ({
      email: 'reader@example.com',
      displayName: 'Reader',
      emailPrefs: { monthlySummary: false },
    });

    await myFunctions.sendMonthlyStatsEmail.run();

    assert.equal(sentMessages.length, 0);
  });

  it('skips users without a verified email', async () => {
    fakeUserRecord = { email: 'reader@example.com', emailVerified: false };

    await myFunctions.sendMonthlyStatsEmail.run();

    assert.equal(sentMessages.length, 0);
  });
});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
});
