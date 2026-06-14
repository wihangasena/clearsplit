import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { searchMembers } from '../db/memberStore.js';

const router = Router();

// Member directory search (demo accounts + registered members). Used by the
// client when adding people to a group or expense.
//   GET /members?q=<query>&excludeId=<id>
router.get(
  '/members',
  asyncHandler(async (req, res) => {
    const q = typeof req.query.q === 'string' ? req.query.q : '';
    const excludeId =
      typeof req.query.excludeId === 'string' ? req.query.excludeId : undefined;
    const members = await searchMembers(q, { excludeId });
    res.json({ members });
  }),
);

export default router;
