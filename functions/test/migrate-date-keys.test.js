const {describe, it} = require('mocha');
const assert = require('node:assert');
const {padKey} = require('../migrate-date-keys');

describe('padKey', () => {
  it('pads single-digit month and day', () => {
    assert.equal(padKey('2023-6-3'), '2023-06-03');
  });

  it('leaves already padded values unchanged', () => {
    assert.equal(padKey('2023-06-03'), '2023-06-03');
  });

  it('handles double-digit month and day', () => {
    assert.equal(padKey('2023-11-12'), '2023-11-12');
  });
});
