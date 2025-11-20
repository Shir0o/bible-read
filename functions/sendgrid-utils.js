const functions = require("firebase-functions/v1");
const sgMail = require("@sendgrid/mail");

let configuredSendgridKey;

const getSendgridSettings = () => {
  let config = {};
  if (typeof functions.config === 'function') {
    try {
      config = functions.config();
    } catch (err) {
      functions.logger.debug('Failed to read functions config', err);
    }
  }
  const sendgridConfig = config.sendgrid || {};
  return {
    apiKey: sendgridConfig.apikey || process.env.SENDGRID_API_KEY || '',
    from: sendgridConfig.from || process.env.SENDGRID_FROM || '',
    to: sendgridConfig.to || process.env.SENDGRID_TO || '',
  };
};

const normalizeRecipients = (recipients) => {
  if (!recipients) return [];

  if (Array.isArray(recipients)) {
    return recipients.filter(Boolean).map((value) => String(value).trim()).filter(Boolean);
  }

  return String(recipients)
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
};

const ensureSendgridConfigured = (apiKey) => {
  if (!apiKey) {
    return false;
  }

  if (configuredSendgridKey === apiKey) {
    return true;
  }

  sgMail.setApiKey(apiKey);
  configuredSendgridKey = apiKey;
  return true;
};

const sendEmail = async ({ subject, text, html, to, from, messageData = {} }) => {
  const { apiKey, from: defaultFrom, to: defaultTo } = getSendgridSettings();
  const recipients = normalizeRecipients(to || defaultTo);
  const sender = from || defaultFrom;
  const isConfigured = ensureSendgridConfigured(apiKey);

  if (!isConfigured || !sender || recipients.length === 0) {
    functions.logger.error('SendGrid configuration incomplete; skipping email', {
      fromConfigured: Boolean(sender),
      recipientsCount: recipients.length,
    });
    return null;
  }

  const msg = {
    to: recipients,
    from: sender,
    subject,
    text,
    html,
    ...messageData,
  };

  await sgMail.send(msg);
  functions.logger.info('SendGrid message sent', { subject, recipientsCount: recipients.length });
  return msg;
};

const resetSendgridCache = () => {
  configuredSendgridKey = undefined;
};

module.exports = {
  getSendgridSettings,
  normalizeRecipients,
  ensureSendgridConfigured,
  sendEmail,
  resetSendgridCache,
};
