import express from 'express';
import { cors } from './middleware/cors.js';
import { notFound, errorHandler } from './middleware/errorHandler.js';
import healthRoutes from './routes/health.js';
import accountRoutes from './routes/accounts.js';
import authRoutes from './routes/auth.js';
import stateRoutes from './routes/state.js';
import groupRoutes from './routes/groups.js';
import profileRoutes from './routes/profile.js';

/**
 * Builds the Express app (without starting the server or connecting to Mongo),
 * so it can be imported and exercised in tests.
 */
export function createApp() {
  const app = express();

  app.use(express.json({ limit: '1mb' }));
  app.use(cors);

  app.use(healthRoutes);
  app.use(accountRoutes);
  app.use(authRoutes);
  app.use(stateRoutes);
  app.use(groupRoutes);
  app.use(profileRoutes);

  app.use(notFound);
  app.use(errorHandler);

  return app;
}
