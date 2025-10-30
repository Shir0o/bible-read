const {after, afterEach, beforeEach, describe, it} = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');
const sgMail = require('@sendgrid/mail');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({projectId: 'demo'});
const myFunctions = require('../index');

process.env.NODE_ENV = 'test';

describe('feedback email triggers', () => {
  let originalSend;
  let originalSetApiKey;
  let sentMessages;

  beforeEach(() => {
    process.env.SENDGRID_API_KEY = 'test-key';
    process.env.SENDGRID_FROM = 'noreply@example.com';
    process.env.SENDGRID_TO = 'team@example.com,ops@example.com';

    sentMessages = [];
    originalSend = sgMail.send;
    originalSetApiKey = sgMail.setApiKey;

    sgMail.setApiKey = () => {};
    sgMail.send = async (message) => {
      sentMessages.push(message);
      return [{ statusCode: 202 }];
    };
  });

  afterEach(() => {
    sgMail.send = originalSend;
    sgMail.setApiKey = originalSetApiKey;

    delete process.env.SENDGRID_API_KEY;
    delete process.env.SENDGRID_FROM;
    delete process.env.SENDGRID_TO;
  });

  it('sends an email when a bug report is created', async () => {
    const snap = {
      data: () => ({
        title: 'Crash on launch',
        description: 'The app crashes immediately after tapping the icon.',
        reporterName: 'Jane Doe',
        reporterEmail: 'jane@example.com',
      }),
      ref: { path: 'bugReports/bug123' },
    };

    await myFunctions.onBugReportCreated.run({
      data: snap,
      params: { reportId: 'bug123' },
    });

    assert.equal(sentMessages.length, 1);
    const [message] = sentMessages;
    assert.ok(message.subject.includes('Bug Report'));
    assert.match(message.text, /Crash on launch/);
    assert.match(message.text, /bugReports\/bug123/);
    assert.deepEqual(message.to, ['team@example.com', 'ops@example.com']);
  });

  it('sends an email when a feature request is created', async () => {
    const snap = {
      data: () => ({
        title: 'Reading streak reminders',
        description: 'Send a weekly reminder to review streak progress.',
        reporter: {
          name: 'John Smith',
          email: 'john@example.com',
        },
      }),
      ref: { path: 'featureRequests/req789' },
    };

    await myFunctions.onFeatureRequestCreated.run({
      data: snap,
      params: { requestId: 'req789' },
    });

    assert.equal(sentMessages.length, 1);
    const [message] = sentMessages;
    assert.ok(message.subject.includes('Feature Request'));
    assert.match(message.text, /Reading streak reminders/);
    assert.match(message.html, /John Smith/);
  });
});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
