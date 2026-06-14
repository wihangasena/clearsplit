import { AppError } from '../utils/AppError.js';

/** Ensures `body` is a non-null object, else throws 400. */
export function requireBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError(400, 'Request body must be a JSON object');
  }
  return body;
}

/** Ensures `value` is a non-empty string, else throws 400. */
export function requireString(value, field) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(400, `Field "${field}" must be a non-empty string`);
  }
  return value;
}

/** Ensures `value` is a finite number strictly greater than zero, else throws 400. */
export function requirePositiveNumber(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new AppError(400, `Field "${field}" must be a number greater than zero`);
  }
  return value;
}
