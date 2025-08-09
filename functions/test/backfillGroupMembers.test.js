const { after, describe, it } = require('mocha');
const assert = require('node:assert');
const admin = require('firebase-admin');

const originalInit = admin.initializeApp;
const originalApp = admin.app;
admin.initializeApp = () => {};
admin.app = () => ({ options: { projectId: 'demo' } });

const functionsTest = require('firebase-functions-test')({ projectId: 'demo' });
const myFunctions = require('../index');

process.env.ADMIN_UID = 'admin1';

describe('backfillGroupMembers', () => {
  it('rejects non-admin', async () => {
    const wrapped = functionsTest.wrap(myFunctions.backfillGroupMembers);
    try {
      await wrapped({ data: {} });
      assert.fail('expected error');
    } catch (err) {
      assert.equal(err.code, 'permission-denied');
    }
  });

  it('updates missing fields', async () => {
    const originalFirestore = admin.firestore;
    const writes = [];

    const fakeMembers = [
      { id: 'm1', data: () => ({}), ref: { path: 'groups/g1/members/m1' } },
      { id: 'm2', data: () => ({ uid: 'm2', role: 'member' }), ref: { path: 'groups/g1/members/m2' } },
      { id: 'm3', data: () => ({ uid: 'm3' }), ref: { path: 'groups/g1/members/m3' } },
    ];

    function fakeFirestore() {
      return {
        collection: () => ({
          get: async () => ({
            docs: [
              {
                ref: {
                  collection: () => ({
                    get: async () => ({ docs: fakeMembers }),
                  }),
                },
              },
            ],
          }),
        }),
        batch: () => ({
          set: (ref, data) => writes.push({ ref, data }),
          commit: async () => {},
        }),
      };
    }
    fakeFirestore.FieldValue = { serverTimestamp: () => 'ts' };
    Object.defineProperty(admin, 'firestore', { value: fakeFirestore, configurable: true, writable: true });

    const wrapped = functionsTest.wrap(myFunctions.backfillGroupMembers);
    const res = await wrapped({ data: {}, auth: { uid: 'admin1' } });
    assert.equal(writes.length, 2);
    assert.deepEqual(writes[0].data, { uid: 'm1', role: 'member', joinedAt: 'ts' });
    assert.deepEqual(writes[1].data, { uid: 'm3', role: 'member', joinedAt: 'ts' });
    assert.equal(res.updated, 2);

    Object.defineProperty(admin, 'firestore', { value: originalFirestore, writable: true });
  });
});

after(() => {
  admin.initializeApp = originalInit;
  admin.app = originalApp;
  functionsTest.cleanup();
});
