import { Router } from 'express';
import { DEMO_ACCOUNTS, DEMO_PASSWORD, publicAccount } from '../domain/demoAccounts.js';

const router = Router();

// Demo accounts list. Password is included intentionally for the demo so the
// login screen can show quick-tap tiles (AUTH-03).
router.get('/accounts', (req, res) => {
  res.json({
    accounts: DEMO_ACCOUNTS.map((a) => ({ ...publicAccount(a), password: DEMO_PASSWORD })),
  });
});

export default router;
