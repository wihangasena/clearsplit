import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  isGroupAdmin,
  groupAdmins,
  addAdmin,
  removeAdmin,
  canRemoveMember,
  canAssignAdmin,
  canRevokeAdmin,
} from '../src/domain/groups.js';

const group = () => ({ id: 'g', members: ['kasun', 'nimal', 'amal'], admins: ['kasun'] });

// ---- Admin resolution ------------------------------------------------------

test('isGroupAdmin: honours the explicit admins list', () => {
  assert.equal(isGroupAdmin(group(), 'kasun'), true);
  assert.equal(isGroupAdmin(group(), 'nimal'), false);
});

test('groupAdmins: falls back to the first member when no admins list', () => {
  assert.deepEqual(groupAdmins({ members: ['kasun', 'nimal'] }), ['kasun']);
  assert.deepEqual(groupAdmins({ members: ['kasun'], admins: ['nimal'] }), ['nimal']);
});

test('addAdmin / removeAdmin: pure, dedupe', () => {
  assert.deepEqual(addAdmin(['kasun'], 'nimal'), ['kasun', 'nimal']);
  assert.deepEqual(addAdmin(['kasun'], 'kasun'), ['kasun']);
  assert.deepEqual(removeAdmin(['kasun', 'nimal'], 'kasun'), ['nimal']);
});

// ---- Remove member ---------------------------------------------------------

test('canRemoveMember: allows a settled non-admin member', () => {
  assert.deepEqual(canRemoveMember(group(), 'nimal', 0), { valid: true, error: null });
});

test('canRemoveMember: rejects a non-member', () => {
  const result = canRemoveMember(group(), 'stranger', 0);
  assert.equal(result.valid, false);
  assert.match(result.error, /not a member/);
});

test('canRemoveMember: blocks a member with an outstanding balance', () => {
  const result = canRemoveMember(group(), 'nimal', 1500);
  assert.equal(result.valid, false);
  assert.match(result.error, /settled up/);
});

test('canRemoveMember: blocks removing the last admin', () => {
  const result = canRemoveMember(group(), 'kasun', 0);
  assert.equal(result.valid, false);
  assert.match(result.error, /last admin/);
});

test('canRemoveMember: allows removing an admin when another admin remains', () => {
  const g = { id: 'g', members: ['kasun', 'nimal'], admins: ['kasun', 'nimal'] };
  assert.equal(canRemoveMember(g, 'kasun', 0).valid, true);
});

// ---- Roles -----------------------------------------------------------------

test('canAssignAdmin: only a member can be promoted', () => {
  assert.equal(canAssignAdmin(group(), 'nimal').valid, true);
  assert.equal(canAssignAdmin(group(), 'stranger').valid, false);
});

test('canRevokeAdmin: blocks revoking the last admin', () => {
  const result = canRevokeAdmin(group(), 'kasun');
  assert.equal(result.valid, false);
  assert.match(result.error, /at least one admin/);
});

test('canRevokeAdmin: allows revoking when another admin remains', () => {
  const g = { id: 'g', members: ['kasun', 'nimal'], admins: ['kasun', 'nimal'] };
  assert.equal(canRevokeAdmin(g, 'kasun').valid, true);
});
