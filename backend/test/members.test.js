import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  hashPassword,
  verifyPassword,
  validateRegistration,
  makeMemberId,
  publicMember,
  memberAsAccount,
} from '../src/domain/members.js';
import { seedForNewMember } from '../src/domain/seed.js';

test('hashPassword/verifyPassword: round-trips and rejects wrong passwords', () => {
  const stored = hashPassword('correct horse');
  assert.ok(stored.includes(':'));
  assert.equal(verifyPassword('correct horse', stored), true);
  assert.equal(verifyPassword('wrong', stored), false);
  assert.equal(verifyPassword('correct horse', 'not-a-valid-hash'), false);
});

test('hashPassword: same password yields different hashes (salted)', () => {
  assert.notEqual(hashPassword('pw123456'), hashPassword('pw123456'));
});

test('validateRegistration: accepts good input and normalizes email', () => {
  const r = validateRegistration({
    name: '  Zoe ',
    email: 'ZOE@Example.com ',
    password: 'secret1',
  });
  assert.equal(r.valid, true);
  assert.equal(r.value.name, 'Zoe');
  assert.equal(r.value.email, 'zoe@example.com');
});

test('validateRegistration: rejects short name, bad email, short password', () => {
  assert.equal(validateRegistration({ name: 'Z', email: 'a@b.co', password: 'secret1' }).valid, false);
  assert.equal(validateRegistration({ name: 'Zoe', email: 'nope', password: 'secret1' }).valid, false);
  assert.equal(validateRegistration({ name: 'Zoe', email: 'a@b.co', password: '123' }).valid, false);
});

test('makeMemberId: slugifies the name with a random suffix', () => {
  const id = makeMemberId('Zoe Smith!');
  assert.match(id, /^zoe-smith-[0-9a-f]{6}$/);
  assert.notEqual(makeMemberId('Zoe'), makeMemberId('Zoe')); // suffix differs
});

test('publicMember / memberAsAccount: never expose the password hash', () => {
  const doc = {
    _id: 'zoe-abc123',
    name: 'Zoe',
    email: 'zoe@example.com',
    avatar: '👩',
    color: '#10B981',
    passwordHash: 'salt:hash',
  };
  const pub = publicMember(doc);
  const acct = memberAsAccount(doc);
  assert.equal(pub.id, 'zoe-abc123');
  assert.equal(acct.displayName, 'Zoe');
  assert.ok(!('passwordHash' in pub));
  assert.ok(!('passwordHash' in acct));
});

test('seedForNewMember: starts empty with just the member as a person', () => {
  const state = seedForNewMember({ id: 'zoe-1', name: 'Zoe', avatar: '👩', color: '#10B981' });
  assert.equal(state.me, 'zoe-1');
  assert.deepEqual(state.people.map((p) => p.id), ['zoe-1']);
  assert.deepEqual(state.groups, []);
  assert.deepEqual(state.expenses, []);
  assert.deepEqual(state.settlements, []);
});
