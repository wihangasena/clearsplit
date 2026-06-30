import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  makeActivityEvent,
  appendActivity,
  backfillActivity,
  ACTIVITY_TYPES,
} from '../src/domain/activity.js';
import {
  summarizeExpenseChanges,
  describeExpenseChange,
} from '../src/domain/expenses.js';

// ---- Event construction ----------------------------------------------------

test('makeActivityEvent builds a normalized event with an ISO timestamp', () => {
  const event = makeActivityEvent({
    id: 'a1',
    type: ACTIVITY_TYPES.EXPENSE_ADDED,
    actor: 'kasun',
    groupId: 'trip',
    expenseId: 'exp-1',
    title: 'Dinner',
    amount: 3000,
    at: new Date('2026-06-13T00:00:00.000Z'),
  });
  assert.deepEqual(event, {
    id: 'a1',
    type: 'expense_added',
    actor: 'kasun',
    groupId: 'trip',
    expenseId: 'exp-1',
    title: 'Dinner',
    amount: 3000,
    description: '',
    timestamp: '2026-06-13T00:00:00.000Z',
  });
});

test('makeActivityEvent defaults the optional snapshot fields', () => {
  const event = makeActivityEvent({
    id: 'a2',
    type: ACTIVITY_TYPES.EXPENSE_DELETED,
    actor: 'nimal',
    at: '2026-01-01T00:00:00.000Z',
  });
  assert.equal(event.groupId, null);
  assert.equal(event.expenseId, null);
  assert.equal(event.title, null);
  assert.equal(event.amount, null);
  assert.equal(event.description, '');
  assert.equal(event.timestamp, '2026-01-01T00:00:00.000Z'); // string passes through
});

// ---- Append (fan-out target) -----------------------------------------------

test('appendActivity adds the event and is idempotent on id', () => {
  const state = { activity: [] };
  const event = makeActivityEvent({ id: 'a3', type: ACTIVITY_TYPES.EXPENSE_SETTLED, actor: 'amal' });
  appendActivity(state, event);
  appendActivity(state, event); // a re-fanned event must not duplicate
  assert.equal(state.activity.length, 1);
  assert.equal(state.activity[0].id, 'a3');
});

test('appendActivity creates the list when missing and stores a clone', () => {
  const state = {};
  const event = makeActivityEvent({ id: 'a4', type: ACTIVITY_TYPES.EXPENSE_ADDED, actor: 'amal' });
  appendActivity(state, event);
  assert.equal(state.activity.length, 1);
  assert.notEqual(state.activity[0], event); // clone, so later mutation of `event` can't leak
  assert.deepEqual(state.activity[0], event);
});

// ---- Backfill (one-time migration of pre-activity states) ------------------

test('backfillActivity derives an "added" event per expense for legacy state', () => {
  const state = {
    expenses: [
      { id: 'exp-1', title: 'Groceries', amount: 120, paidBy: 'you', createdBy: 'you', groupId: 'beach', date: '2026-06-01T00:00:00.000Z' },
      { id: 'exp-9', title: 'Movie', amount: 36, paidBy: 'you', date: '2026-06-02T00:00:00.000Z' },
    ],
  };
  assert.equal(backfillActivity(state), true);
  assert.equal(state.activity.length, 2);
  assert.equal(state.activity[0].id, 'act-exp-1-add');
  assert.equal(state.activity[0].type, ACTIVITY_TYPES.EXPENSE_ADDED);
  assert.equal(state.activity[0].timestamp, '2026-06-01T00:00:00.000Z');
  // Legacy expense with no createdBy falls back to the payer.
  assert.equal(state.activity[1].actor, 'you');
});

test('backfillActivity leaves a state that already has an activity array alone', () => {
  const state = { expenses: [{ id: 'e1' }], activity: [] };
  assert.equal(backfillActivity(state), false);
  assert.equal(state.activity.length, 0);
});

// ---- Change summary (shared with the activity description) ------------------

test('summarizeExpenseChanges returns only the change clause', () => {
  const before = { title: 'Dinner', amount: 2500, category: 'food', splitMethod: 'equal' };
  const after = { title: 'Dinner', amount: 3000, category: 'food', splitMethod: 'equal' };
  assert.equal(summarizeExpenseChanges(before, after), 'amount from 2500 to 3000');
});

test('summarizeExpenseChanges is empty for a no-op edit', () => {
  const e = { title: 'Dinner', amount: 3000, category: 'food', splitMethod: 'equal' };
  assert.equal(summarizeExpenseChanges(e, { ...e }), '');
});

test('describeExpenseChange still prefixes the summary with "edited X"', () => {
  const before = { title: 'Dinner', amount: 2500, category: 'food', splitMethod: 'equal' };
  const after = { title: 'Dinner', amount: 3000, category: 'food', splitMethod: 'equal' };
  assert.equal(describeExpenseChange(before, after), 'edited Dinner amount from 2500 to 3000');
});
