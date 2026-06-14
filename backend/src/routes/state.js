import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { requireBody } from '../middleware/validate.js';
import { getState, saveState } from '../db/stateStore.js';
import { seedForAccount } from '../domain/seed.js';
import { validateExpenseSplits } from '../domain/expenses.js';

const router = Router();

// Fetch persisted state for a user.
router.get(
  '/state/:userId',
  asyncHandler(async (req, res) => {
    const state = await getState(req.params.userId);
    if (!state) throw new AppError(404, 'State not found');
    res.json({ state });
  }),
);

// Overwrite persisted state for a user.
router.put(
  '/state/:userId',
  asyncHandler(async (req, res) => {
    const body = requireBody(req.body);
    if (!body.state || typeof body.state !== 'object') {
      throw new AppError(400, 'Field "state" (object) is required');
    }
    // Reject persistence of any expense with an invalid split so no broken
    // ledger ever reaches storage, regardless of which path created it.
    for (const expense of body.state.expenses ?? []) {
      const check = validateExpenseSplits(expense);
      if (!check.valid) {
        throw new AppError(400, `Invalid split for "${expense.title ?? expense.id}": ${check.error}`);
      }
    }
    const saved = await saveState(req.params.userId, body.state);
    res.json({ state: saved });
  }),
);

// Re-seed a user's state to the initial demo data (AccountScreen reset).
router.post(
  '/state/:userId/reset',
  asyncHandler(async (req, res) => {
    const fresh = seedForAccount(req.params.userId);
    const saved = await saveState(req.params.userId, fresh);
    res.json({ state: saved });
  }),
);

export default router;
