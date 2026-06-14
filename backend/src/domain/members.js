import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

/**
 * Registered-member domain helpers: password hashing/verification, id + colour
 * generation, public projection, and input validation. Kept free of any DB or
 * HTTP concerns so it can be unit-tested in isolation (mirrors the rest of
 * `domain/`).
 */

const SCRYPT_KEYLEN = 64;

/** Hashes a plaintext password as "salt:hash" (hex), using scrypt. */
export function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const derived = scryptSync(password, salt, SCRYPT_KEYLEN).toString('hex');
  return `${salt}:${derived}`;
}

/** Verifies a plaintext password against a stored "salt:hash" string. */
export function verifyPassword(password, stored) {
  if (typeof stored !== 'string' || !stored.includes(':')) return false;
  const [salt, hash] = stored.split(':');
  const expected = Buffer.from(hash, 'hex');
  const actual = scryptSync(String(password), salt, SCRYPT_KEYLEN);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/** Palette new members are assigned a colour from (matches the client palette). */
const MEMBER_COLORS = [
  '#2563EB', '#10B981', '#8B5CF6', '#EF4444',
  '#F59E0B', '#0EA5E9', '#EC4899', '#14B8A6',
];

/** Deterministic-ish colour pick so a member keeps a stable colour. */
export function colorForSeed(seed) {
  let sum = 0;
  for (const ch of String(seed)) sum += ch.charCodeAt(0);
  return MEMBER_COLORS[sum % MEMBER_COLORS.length];
}

/** Builds a stable member id from a display name plus a short random suffix. */
export function makeMemberId(name) {
  const slug = String(name)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
    .slice(0, 20);
  const suffix = randomBytes(3).toString('hex');
  return `${slug || 'member'}-${suffix}`;
}

export function normalizeEmail(email) {
  return String(email).trim().toLowerCase();
}

/** Public projection of a member document — never leaks the password hash. */
export function publicMember(member) {
  return {
    id: member.id ?? member._id,
    name: member.name,
    avatar: member.avatar ?? '🙂',
    color: member.color ?? '#2563EB',
    email: member.email,
  };
}

/**
 * Account projection (matches `publicAccount` from demoAccounts) so the
 * register/login responses share one shape the client already understands.
 */
export function memberAsAccount(member) {
  return {
    id: member.id ?? member._id,
    displayName: member.name,
    email: member.email,
    avatar: member.avatar ?? '🙂',
    color: member.color ?? '#2563EB',
  };
}

/** Validates registration input. Returns { name, email, password } or throws. */
export function validateRegistration({ name, email, password }) {
  const errors = [];
  const cleanName = typeof name === 'string' ? name.trim() : '';
  const cleanEmail = typeof email === 'string' ? normalizeEmail(email) : '';
  const cleanPassword = typeof password === 'string' ? password : '';

  if (cleanName.length < 2) errors.push('Name must be at least 2 characters');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleanEmail)) {
    errors.push('Enter a valid email address');
  }
  if (cleanPassword.length < 6) {
    errors.push('Password must be at least 6 characters');
  }
  return {
    valid: errors.length === 0,
    error: errors.join('. '),
    value: { name: cleanName, email: cleanEmail, password: cleanPassword },
  };
}
