import { getDb } from './client.js';
import { config } from '../config.js';
import { DEMO_ACCOUNTS } from '../domain/demoAccounts.js';
import {
  hashPassword,
  makeMemberId,
  normalizeEmail,
  publicMember,
} from '../domain/members.js';

/**
 * Data-access for the global member directory — the set of people who can sign
 * in and be searched/added to groups. Backed by its own collection
 * (`members`), documents shaped `{ _id, name, email, avatar, color,
 * passwordHash, createdAt }`. Demo accounts live in code (not this collection)
 * but are folded into search results so they remain addable.
 */
function collection() {
  return getDb().collection(config.mongoMembersCollection);
}

/** Ensures a unique index on email so duplicate registrations can't race in. */
export async function ensureMemberIndexes() {
  await collection().createIndex({ email: 1 }, { unique: true });
}

/** Demo accounts projected as directory entries (no password leaves here). */
function demoDirectory() {
  return DEMO_ACCOUNTS.map((a) => ({
    id: a.id,
    name: a.displayName,
    email: a.email,
    avatar: a.avatar,
    color: a.color,
  }));
}

/** Looks up a registered member by email (case-insensitive), or null. */
export async function getMemberByEmail(email) {
  const doc = await collection().findOne({ email: normalizeEmail(email) });
  return doc ?? null;
}

/** Looks up a registered member by id, or null. */
export async function getMemberById(id) {
  const doc = await collection().findOne({ _id: id });
  return doc ?? null;
}

/** True when an email already belongs to a demo account or a registered member. */
export async function emailTaken(email) {
  const normalized = normalizeEmail(email);
  if (DEMO_ACCOUNTS.some((a) => a.email.toLowerCase() === normalized)) {
    return true;
  }
  return (await getMemberByEmail(normalized)) != null;
}

/**
 * Inserts a new member with a hashed password. Caller must have validated the
 * input and confirmed the email is free. Returns the public projection.
 */
export async function createMember({ name, email, password, avatar, color }) {
  const id = makeMemberId(name);
  const doc = {
    _id: id,
    name: name.trim(),
    email: normalizeEmail(email),
    avatar: avatar ?? '🙂',
    color: color ?? '#2563EB',
    passwordHash: hashPassword(password),
    createdAt: new Date().toISOString(),
  };
  await collection().insertOne(doc);
  return publicMember({ ...doc, id });
}

/**
 * Searches the directory (demo accounts + registered members) by name or email.
 * Empty query returns the first [limit] entries. Excludes [excludeId].
 */
export async function searchMembers(query, { excludeId, limit = 25 } = {}) {
  const q = String(query ?? '').trim().toLowerCase();

  const registered = await collection().find({}).limit(200).toArray();
  const all = [
    ...demoDirectory(),
    ...registered.map((m) => publicMember(m)),
  ];

  const seen = new Set();
  const out = [];
  for (const m of all) {
    if (m.id === excludeId) continue;
    if (seen.has(m.id)) continue;
    if (q && !m.name.toLowerCase().includes(q) && !m.email.toLowerCase().includes(q)) {
      continue;
    }
    seen.add(m.id);
    out.push(m);
    if (out.length >= limit) break;
  }
  return out;
}
