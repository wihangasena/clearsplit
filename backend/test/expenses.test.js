import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  validateExpenseSplits,
  isGroupAdmin,
  canModifyExpense,
  pickEditableFields,
  makeHistoryEntry,
  describeExpenseChange,
  makeComment,
} from '../src/domain/expenses.js';

// ---- Split validation ------------------------------------------------------

test('validateExpenseSplits: equal split is always valid', () => {
  const e = { amount: 3000, participants: ['a', 'b', 'c'], splitMethod: 'equal' };
  assert.deepEqual(validateExpenseSplits(e), { valid: true, error: null });
});

test('validateExpenseSplits: exact amounts must sum to the total', () => {
  const ok = {
    amount: 3000,
    participants: ['a', 'b', 'c'],
    splitMethod: 'amount',
    splits: { a: 500, b: 1000, c: 1500 },
  };
  assert.equal(validateExpenseSplits(ok).valid, true);

  const bad = { ...ok, splits: { a: 500, b: 1000, c: 1000 } };
  const result = validateExpenseSplits(bad);
  assert.equal(result.valid, false);
  assert.match(result.error, /add up to 3000/);
});

test('validateExpenseSplits: percentages must sum to 100', () => {
  const ok = {
    amount: 3000,
    participants: ['a', 'b', 'c'],
    splitMethod: 'percentage',
    splits: { a: 20, b: 30, c: 50 },
  };
  assert.equal(validateExpenseSplits(ok).valid, true);

  const bad = { ...ok, splits: { a: 20, b: 30, c: 40 } };
  const result = validateExpenseSplits(bad);
  assert.equal(result.valid, false);
  assert.match(result.error, /add up to 100/);
});

test('validateExpenseSplits: tolerates sub-cent rounding', () => {
  const e = {
    amount: 100,
    participants: ['a', 'b', 'c'],
    splitMethod: 'amount',
    splits: { a: 33.33, b: 33.33, c: 33.34 },
  };
  assert.equal(validateExpenseSplits(e).valid, true);
});

test('validateExpenseSplits: rejects an unknown split method', () => {
  const result = validateExpenseSplits({ amount: 10, participants: ['a'], splitMethod: 'shares' });
  assert.equal(result.valid, false);
});

// ---- Permissions -----------------------------------------------------------

const group = { id: 'g', members: ['kasun', 'nimal', 'amal'] };

test('isGroupAdmin: first member is admin by default', () => {
  assert.equal(isGroupAdmin(group, 'kasun'), true);
  assert.equal(isGroupAdmin(group, 'nimal'), false);
});

test('isGroupAdmin: honours an explicit admins list', () => {
  assert.equal(isGroupAdmin({ members: ['kasun', 'nimal'], admins: ['nimal'] }, 'nimal'), true);
  assert.equal(isGroupAdmin({ members: ['kasun', 'nimal'], admins: ['nimal'] }, 'kasun'), false);
});

test('canModifyExpense: creator may modify', () => {
  const expense = { createdBy: 'nimal', paidBy: 'amal' };
  assert.equal(canModifyExpense({ expense, group, userId: 'nimal' }), true);
});

test('canModifyExpense: group admin may modify', () => {
  const expense = { createdBy: 'nimal', paidBy: 'amal' };
  assert.equal(canModifyExpense({ expense, group, userId: 'kasun' }), true);
});

test('canModifyExpense: an unrelated member may not', () => {
  const expense = { createdBy: 'nimal', paidBy: 'amal' };
  assert.equal(canModifyExpense({ expense, group, userId: 'amal' }), false);
});

test('canModifyExpense: legacy expense falls back to payer as creator', () => {
  const expense = { paidBy: 'amal' };
  assert.equal(canModifyExpense({ expense, group, userId: 'amal' }), true);
});

// ---- Patch + history + comments -------------------------------------------

test('pickEditableFields: keeps only whitelisted fields', () => {
  const out = pickEditableFields({ amount: 50, history: ['x'], id: 'hack', title: 'New' });
  assert.deepEqual(out, { amount: 50, title: 'New' });
});

test('makeHistoryEntry: records user, action, ISO timestamp', () => {
  const entry = makeHistoryEntry('kasun', 'edited Dinner', new Date('2026-06-13T00:00:00.000Z'));
  assert.deepEqual(entry, {
    user: 'kasun',
    action: 'edited Dinner',
    timestamp: '2026-06-13T00:00:00.000Z',
  });
});

test('describeExpenseChange: summarises an amount change', () => {
  const before = { title: 'Dinner', amount: 2500, category: 'food', splitMethod: 'equal' };
  const after = { title: 'Dinner', amount: 3000, category: 'food', splitMethod: 'equal' };
  assert.equal(describeExpenseChange(before, after), 'edited Dinner amount from 2500 to 3000');
});

test('describeExpenseChange: no-op edit still names the expense', () => {
  const e = { title: 'Dinner', amount: 3000, category: 'food', splitMethod: 'equal' };
  assert.equal(describeExpenseChange(e, { ...e }), 'edited Dinner');
});

test('makeComment: builds a comment with all spec fields', () => {
  const c = makeComment({
    id: 'c1',
    expenseId: 'e1',
    userId: 'kasun',
    message: 'nice!',
    at: new Date('2026-06-13T00:00:00.000Z'),
  });
  assert.deepEqual(c, {
    id: 'c1',
    expenseId: 'e1',
    userId: 'kasun',
    message: 'nice!',
    timestamp: '2026-06-13T00:00:00.000Z',
  });
});
