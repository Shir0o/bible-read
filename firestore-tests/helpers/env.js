'use strict';

const fs = require('node:fs');
const path = require('node:path');

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');

// demo-* project ids are never routed to production by the tooling.
const PROJECT_ID = 'demo-bible-read';
const RULES_FILE = path.resolve(__dirname, '..', '..', 'firestore.rules');

let envPromise;

function getTestEnv() {
  if (!envPromise) {
    envPromise = initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(RULES_FILE, 'utf8'),
        ...emulatorEndpoint(),
      },
    });
  }
  return envPromise;
}

// Honours FIRESTORE_EMULATOR_HOST; malformed values surface the SDK's own
// error instead of being masked here.
function emulatorEndpoint() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
  const split = raw.lastIndexOf(':');
  return { host: raw.slice(0, split), port: Number(raw.slice(split + 1)) };
}

async function seed(docPath, data) {
  const env = await getTestEnv();
  await env.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(docPath).set(data, { merge: true });
  });
}

async function asUser(uid, claims) {
  const env = await getTestEnv();
  return env.authenticatedContext(uid, claims).firestore();
}

async function asAdmin(uid) {
  return asUser(uid, { admin: true });
}

async function asUnauthenticated() {
  const env = await getTestEnv();
  return env.unauthenticatedContext().firestore();
}

module.exports = {
  asAdmin,
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  getTestEnv,
  seed,
};
