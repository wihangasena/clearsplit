import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { requireBody, requireString } from '../middleware/validate.js';
import { DEMO_PASSWORD, findAccountByEmail, publicAccount } from '../domain/demoAccounts.js';
import { seedForAccount } from '../domain/seed.js';
import { getState, saveState } from '../db/stateStore.js';

const router = Router();

// AUTH-01/04: authenticate and return the account's persisted state, seeding a
// fresh one on first login.
router.post(
  '/auth/login',
  asyncHandler(async (req, res) => {
    const body = requireBody(req.body);
    const email = requireString(body.email, 'email');
    const password = requireString(body.password, 'password');

    const account = findAccountByEmail(email);
    if (!account || password !== DEMO_PASSWORD) {
      throw new AppError(401, 'Invalid credentials');
    }

    let state = await getState(account.id);
    if (!state) {
      state = seedForAccount(account.id);
      await saveState(account.id, state);
    }

    res.json({ account: publicAccount(account), state });
  }),
);

// AUTH-05: no-op logout (client clears local state).
router.post('/auth/logout', (req, res) => {
  res.json({ status: 'ok' });
});

export default router;
