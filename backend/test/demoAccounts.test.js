import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normalizeDeprecatedDemoContacts, normalizeLegacyNames } from '../src/domain/demoAccounts.js';

test('normalizeLegacyNames: renames the stale "You" person to the canonical name', () => {
  const state = {
    me: 'you',
    people: [
      { id: 'you', name: 'You' },
      { id: 'alex', name: 'Ushani' },
    ],
  };
  normalizeLegacyNames(state);
  assert.equal(state.people[0].name, 'Chenuri');
  assert.equal(state.people[1].name, 'Ushani'); // untouched
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

test('normalizeDeprecatedDemoContacts: remaps removed demo contacts to current accounts', () => {
  const state = {
    people: [
      { id: 'you', name: 'Chenuri' },
      { id: 'alex', name: 'Ushani' },
      { id: 'chloe', name: 'Chloe' },
      { id: 'sam', name: 'Sam' },
    ],
    groups: [
      { id: 'g1', members: ['you', 'alex', 'chloe'], admins: ['chloe'] },
    ],
    expenses: [
      {
        id: 'e1',
        paidBy: 'chloe',
        createdBy: 'sam',
        participants: ['you', 'chloe', 'sam'],
        splits: { you: 10, chloe: 20, sam: 30 },
        history: [{ user: 'sam', action: 'added', timestamp: '2026-01-01T00:00:00.000Z' }],
        comments: [{ id: 'c1', expenseId: 'e1', userId: 'chloe', message: 'ok', timestamp: '2026-01-01T00:00:00.000Z' }],
      },
    ],
    settlements: [{ id: 's1', from: 'chloe', to: 'sam', amount: 40, date: '2026-01-02T00:00:00.000Z' }],
    activity: [{ id: 'a1', actor: 'sam', timestamp: '2026-01-01T00:00:00.000Z' }],
  };

  assert.equal(normalizeDeprecatedDemoContacts(state), true);
  assert.deepEqual(state.people.map((p) => p.id), ['you', 'alex', 'maya']);
  assert.deepEqual(state.groups[0].members, ['you', 'alex']);
  assert.deepEqual(state.groups[0].admins, ['alex']);
  assert.equal(state.expenses[0].paidBy, 'alex');
  assert.equal(state.expenses[0].createdBy, 'maya');
  assert.deepEqual(state.expenses[0].participants, ['you', 'alex', 'maya']);
  assert.deepEqual(state.expenses[0].splits, { you: 10, alex: 20, maya: 30 });
  assert.equal(state.expenses[0].history[0].user, 'maya');
  assert.equal(state.expenses[0].comments[0].userId, 'alex');
  assert.deepEqual(state.settlements[0], { id: 's1', from: 'alex', to: 'maya', amount: 40, date: '2026-01-02T00:00:00.000Z' });
  assert.equal(state.activity[0].actor, 'maya');
});
