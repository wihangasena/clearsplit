import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  getParticipantShare,
  computeBalances,
  computeGroupSettlements,
} from '../src/domain/balances.js';
import { seedForAccount } from '../src/domain/seed.js';

function tripState() {
  return {
    me: 'you',
    people: [
      { id: 'you', name: 'Riley' },
      { id: 'alex', name: 'Alex' },
      { id: 'maya', name: 'Maya' },
    ],
    groups: [{ id: 'trip', name: 'Trip', emoji: '🚗', members: ['you', 'alex', 'maya'] }],
    expenses: [
      {
        id: 'e1',
        title: 'Fuel',
        amount: 90,
        paidBy: 'you',
        participants: ['you', 'alex', 'maya'],
        groupId: 'trip',
        category: 'transport',
        date: '2026-01-01T00:00:00.000Z',
        splitMethod: 'equal',
        splits: {},
        settled: false,
      },
    ],
    settlements: [],
  };
}

test('getParticipantShare: equal split', () => {
  const e = tripState().expenses[0];
  assert.equal(getParticipantShare(e, 'alex'), 30);
});

test('getParticipantShare: uneven equal split reconciles to the exact total', () => {
  // $100 split 3 ways: 33.34 / 33.33 / 33.33 — must sum back to 100, not 99.99.
  const e = {
    amount: 100,
    participants: ['you', 'alex', 'maya'],
    splitMethod: 'equal',
    splits: {},
  };
  const shares = e.participants.map((p) => getParticipantShare(e, p));
  assert.deepEqual(shares, [33.34, 33.33, 33.33]);
  assert.equal(shares.reduce((s, v) => s + v, 0), 100);
});

test('computeGroupSettlements: uneven equal split leaves no residual debt', () => {
  const state = tripState();
  state.expenses[0].amount = 100; // 100 / 3 doesn't divide evenly
  const payments = computeGroupSettlements(state, 'trip');
  const flat = Object.values(payments).flat();
  // Everyone is paid back to the cent — total transfers equal the two debts
  // (you paid 100, your own share is 33.34, so the other two repay 66.66).
  assert.equal(flat.reduce((s, p) => s + p.amount, 0), 66.66);
  assert.ok(flat.every((p) => p.to === 'you'));
});

test('getParticipantShare: percentage split', () => {
  const e = {
    amount: 45,
    participants: ['you', 'alex'],
    splitMethod: 'percentage',
    splits: { you: 60, alex: 40 },
  };
  assert.equal(getParticipantShare(e, 'alex'), 18);
});

test('getParticipantShare: exact amount split', () => {
  const e = {
    amount: 100,
    participants: ['you', 'alex'],
    splitMethod: 'amount',
    splits: { you: 70, alex: 30 },
  };
  assert.equal(getParticipantShare(e, 'alex'), 30);
});

test('computeBalances: payer is owed by each participant', () => {
  const summary = computeBalances(tripState());
  assert.equal(summary.perPerson.alex, 30);
  assert.equal(summary.perPerson.maya, 30);
  assert.equal(summary.owed, 60);
  assert.equal(summary.owe, 0);
  assert.equal(summary.net, 60);
});

test('computeBalances: settlement reduces what a friend owes', () => {
  const state = tripState();
  state.settlements.push({ id: 's1', groupId: 'trip', from: 'alex', to: 'you', amount: 30, date: '2026-01-02' });
  const summary = computeBalances(state);
  assert.equal(summary.perPerson.alex, 0);
  assert.equal(summary.owed, 30); // only maya now
});

test('computeBalances: settled expenses are ignored', () => {
  const state = tripState();
  state.expenses[0].settled = true;
  const summary = computeBalances(state);
  assert.equal(summary.owed, 0);
});

test('computeGroupSettlements: minimal transfers to the creditor', () => {
  const payments = computeGroupSettlements(tripState(), 'trip');
  const flat = Object.values(payments).flat();
  assert.equal(flat.length, 2);
  assert.ok(flat.every((p) => p.to === 'you'));
  assert.equal(flat.reduce((s, p) => s + p.amount, 0), 60);
});

test('computeGroupSettlements: transitive chain collapses to one payment (proposal example)', () => {
  // A owes B 500 and B owes C 500 → the app should suggest a single
  // A → C 500 payment; B nets to zero and drops out entirely.
  const state = {
    me: 'a',
    people: [
      { id: 'a', name: 'A' },
      { id: 'b', name: 'B' },
      { id: 'c', name: 'C' },
    ],
    groups: [{ id: 'g', name: 'G', emoji: '👥', members: ['a', 'b', 'c'] }],
    expenses: [
      // B paid 500 solely for A → A owes B 500.
      {
        id: 'e1', title: 'Lunch', amount: 500, paidBy: 'b', participants: ['a'],
        groupId: 'g', category: 'food', date: '2026-01-01T00:00:00.000Z',
        splitMethod: 'amount', splits: { a: 500 }, settled: false,
      },
      // C paid 500 solely for B → B owes C 500.
      {
        id: 'e2', title: 'Tickets', amount: 500, paidBy: 'c', participants: ['b'],
        groupId: 'g', category: 'fun', date: '2026-01-02T00:00:00.000Z',
        splitMethod: 'amount', splits: { b: 500 }, settled: false,
      },
    ],
    settlements: [],
  };
  const payments = computeGroupSettlements(state, 'g');
  assert.deepEqual(payments, { a: [{ to: 'c', amount: 500 }] });
});

test('computeGroupSettlements: empty when fully settled', () => {
  const state = tripState();
  state.expenses[0].settled = true;
  const payments = computeGroupSettlements(state, 'trip');
  assert.deepEqual(payments, {});
});

test('seedForAccount: produces the full demo world', () => {
  const state = seedForAccount('you');
  assert.equal(state.me, 'you');
  assert.equal(state.people.length, 6);
  assert.equal(state.groups.length, 3);
  assert.equal(state.expenses.length, 10);
  assert.deepEqual(state.settlements, []);
});

test('seedForAccount: percentage + amount splits resolve correctly', () => {
  const state = seedForAccount('you');
  const pct = state.expenses.find((e) => e.splitMethod === 'percentage');
  const exact = state.expenses.find((e) => e.splitMethod === 'amount');
  assert.ok(pct && exact);
  // percentage shares sum to the full amount
  const pctTotal = pct.participants.reduce((s, p) => s + getParticipantShare(pct, p), 0);
  assert.ok(Math.abs(pctTotal - pct.amount) < 0.01);
  const exactTotal = exact.participants.reduce((s, p) => s + getParticipantShare(exact, p), 0);
  assert.ok(Math.abs(exactTotal - exact.amount) < 0.01);
});
