import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { requireBody } from '../middleware/validate.js';
import { getState, fanOut } from '../db/stateStore.js';

const router = Router();

// PROF-01..04: update profile fields and reflect them to every group member's
// copy of this person.
router.patch(
  '/profile/:userId',
  asyncHandler(async (req, res) => {
    const { userId } = req.params;
    const body = requireBody(req.body);

    const patch = {};
    if (body.displayName !== undefined) {
      if (typeof body.displayName !== 'string' || body.displayName.trim() === '') {
        throw new AppError(400, 'Field "displayName" must be a non-empty string');
      }
      patch.name = body.displayName.trim();
    }
    if (body.avatar !== undefined) patch.avatar = String(body.avatar);
    if (body.color !== undefined) patch.color = String(body.color);

    const state = await getState(userId);
    if (!state) throw new AppError(404, 'State not found');

    // Reflect to self + everyone who shares a group with this user.
    const audience = new Set([userId]);
    for (const group of state.groups) {
      if (group.members.includes(userId)) {
        for (const m of group.members) audience.add(m);
      }
    }

    const updated = await fanOut([...audience], userId, (s) => {
      const person = s.people.find((p) => p.id === userId);
      if (person) Object.assign(person, patch);
      return s;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

export default router;
