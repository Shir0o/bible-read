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
        host: emulatorHost(),
        port: emulatorPort(),
      },
    });
  }
  return envPromise;
}

function emulatorHost() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST;
  if (!raw) return '127.0.0.1';
  const withoutPort = raw.replace(/:\d+$/, '');
  return withoutPort || '127.0.0.1';
}

function emulatorPort() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
  const port = Number(raw.split(':').pop());
  return Number.isFinite(port) && port > 0 ? port : 8080;
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
  PROJECT_ID,
  asAdmin,
  asUnauthenticated,
  asUser,
  assertFails,
  assertSucceeds,
  getTestEnv,
  seed,
};
