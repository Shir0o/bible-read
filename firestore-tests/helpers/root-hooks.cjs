'use strict';

const { getTestEnv } = require('./env');

exports.mochaHooks = {
  afterAll: [
    async function cleanupTestEnvironment() {
      const env = await getTestEnv();
      await env.cleanup();
    },
  ],
};
