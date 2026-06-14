import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { requireBody, requireString } from '../middleware/validate.js';
import { DEMO_PASSWORD, findAccountByEmail, publicAccount } from '../domain/demoAccounts.js';
import {
  validateRegistration,
  verifyPassword,
  memberAsAccount,
  colorForSeed,
} from '../domain/members.js';
import {
  getMemberByEmail,
  createMember,
  emailTaken,
} from '../db/memberStore.js';
import { seedForAccount, seedForNewMember } from '../domain/seed.js';
import { getState, saveState } from '../db/stateStore.js';

const router = Router();

// AUTH-01/04: authenticate and return the account's persisted state, seeding a
// fresh one on first login. Supports both hardcoded demo accounts (shared
// password) and registered members (own hashed password).
router.post(
  '/auth/login',
  asyncHandler(async (req, res) => {
    const body = requireBody(req.body);
    const email = requireString(body.email, 'email');
    const password = requireString(body.password, 'password');

    // 1) Demo account fast-path (shared password, full demo world).
    const demo = findAccountByEmail(email);
    if (demo) {
      if (password !== DEMO_PASSWORD) throw new AppError(401, 'Invalid credentials');
      let state = await getState(demo.id);
      if (!state) {
        state = seedForAccount(demo.id);
        await saveState(demo.id, state);
      }
      res.json({ account: publicAccount(demo), state });
      return;
    }

    // 2) Registered member.
    const member = await getMemberByEmail(email);
    if (!member || !verifyPassword(password, member.passwordHash)) {
      throw new AppError(401, 'Invalid credentials');
    }
    let state = await getState(member._id);
    if (!state) {
      state = seedForNewMember({ ...member, id: member._id });
      await saveState(member._id, state);
    }
    res.json({ account: memberAsAccount({ ...member, id: member._id }), state });
  }),
);

// AUTH-06: register a new member. Creates the directory entry + an empty
// starter state, then returns the same { account, state } shape as login so the
// client can sign the user straight in.
router.post(
  '/auth/register',
  asyncHandler(async (req, res) => {
    const body = requireBody(req.body);
    const { valid, error, value } = validateRegistration({
      name: body.name,
      email: body.email,
      password: body.password,
    });
    if (!valid) throw new AppError(400, error);

    if (await emailTaken(value.email)) {
      throw new AppError(409, 'An account with this email already exists');
    }

    const avatar = typeof body.avatar === 'string' && body.avatar ? body.avatar : '🙂';
    const color =
      typeof body.color === 'string' && body.color ? body.color : colorForSeed(value.email);

    const member = await createMember({ ...value, avatar, color });
    const state = seedForNewMember(member);
    await saveState(member.id, state);

    res.status(201).json({ account: memberAsAccount(member), state });
  }),
);

// AUTH-05: no-op logout (client clears local state).
router.post('/auth/logout', (req, res) => {
  res.json({ status: 'ok' });
});

export default router;
