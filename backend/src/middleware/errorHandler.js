import { AppError } from '../utils/AppError.js';

/** 404 fallback for unmatched routes. */
export function notFound(req, res) {
  res.status(404).json({ message: `Not found: ${req.method} ${req.path}` });
}

/**
 * Central error handler. Known AppErrors map to their status code; anything else
 * is treated as an unexpected 500 (and logged for diagnosis).
 */
// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({ message: err.message });
  }
  console.error('Unexpected error:', err);
  res.status(500).json({ message: 'Internal server error' });
}
