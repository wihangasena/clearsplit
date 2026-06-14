import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normalizeLegacyNames } from '../src/domain/demoAccounts.js';

test('normalizeLegacyNames: renames the stale "You" person to the canonical name', () => {
  const state = {
    me: 'you',
    people: [
      { id: 'you', name: 'You' },
      { id: 'alex', name: 'Alex' },
    ],
  };
  normalizeLegacyNames(state);
  assert.equal(state.people[0].name, 'Riley');
  assert.equal(state.people[1].name, 'Alex'); // untouched
});

test('normalizeLegacyNames: never clobbers a real/custom name', () => {
  const state = {
    me: 'you',
    people: [{ id: 'you', name: 'Winnie' }], // user renamed themselves
  };
  normalizeLegacyNames(state);
  assert.equal(state.people[0].name, 'Winnie');
});

test('normalizeLegacyNames: tolerates empty/malformed state', () => {
  assert.doesNotThrow(() => normalizeLegacyNames(null));
  assert.doesNotThrow(() => normalizeLegacyNames({}));
});
