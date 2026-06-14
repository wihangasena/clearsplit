import { config } from '../config.js';

/**
 * Permissive CORS for the demo (NFR-04). Origin is overridable via CORS_ORIGIN
 * so production can restrict it to the frontend origin.
 */
export function cors(req, res, next) {
  res.set('Access-Control-Allow-Origin', config.corsOrigin);
  res.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(204);
  }
  next();
}
