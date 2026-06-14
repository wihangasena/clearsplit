import dotenv from 'dotenv';

dotenv.config();

/**
 * Centralised, validated configuration. Reads from the environment once and
 * fails fast with a clear message if required values are missing, so the server
 * never starts in a half-configured state.
 */
function required(name) {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(
      `Missing required environment variable "${name}". ` +
        'Copy backend/.env.example to backend/.env and fill it in.',
    );
  }
  return value.trim();
}

function optional(name, fallback) {
  const value = process.env[name];
  return value && value.trim() !== '' ? value.trim() : fallback;
}

export const config = Object.freeze({
  mongoUri: required('MONGODB_URI'),
  mongoDb: optional('MONGO_DB', 'clearsplit'),
  mongoCollection: optional('MONGO_COLLECTION', 'app_states'),
  port: Number.parseInt(optional('BACKEND_PORT', '8081'), 10),
  host: optional('BACKEND_HOST', '0.0.0.0'),
  corsOrigin: optional('CORS_ORIGIN', '*'),
});
