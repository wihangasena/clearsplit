import { getDb } from './client.js';
import { config } from '../config.js';
import { normalizeLegacyNames, normalizeDeprecatedDemoContacts } from '../domain/demoAccounts.js';
import { backfillActivity } from '../domain/activity.js';

/**
 * Data-access layer for per-user app state. Documents are
 * `{ _id: userId, state: { ...AppData... } }`. This module is the only place
 * that talks to the collection, keeping persistence concerns out of the routes.
 */
function collection() {
  return getDb().collection(config.mongoCollection);
}

/** Returns the stored AppData for a user, or null if none exists. */
export async function getState(userId) {
  const doc = await collection().findOne({ _id: userId });
  if (!doc) return null;
  const hadLegacyName = (doc.state?.people ?? []).some((p) => p.name === 'You');
  const state = normalizeLegacyNames(doc.state);
  const deprecatedContactsMigrated = normalizeDeprecatedDemoContacts(state);
  const backfilled = backfillActivity(state);
  // Persist one-time migrations (legacy rename, activity backfill) so they
  // stick for every future read/viewer.
  if (hadLegacyName || deprecatedContactsMigrated || backfilled) await saveState(userId, state);
  return state;
}

/** Upserts the AppData for a user and returns it. */
export async function saveState(userId, state) {
  await collection().updateOne(
    { _id: userId },
    { $set: { state } },
    { upsert: true },
  );
  return state;
}

/** Loads states for several users at once as a Map(userId -> state). */
export async function getStates(userIds) {
  const docs = await collection()
    .find({ _id: { $in: userIds } })
    .toArray();
  const map = new Map();
  for (const doc of docs) {
    const state = normalizeLegacyNames(doc.state);
    const deprecatedContactsMigrated = normalizeDeprecatedDemoContacts(state);
    const backfilled = backfillActivity(state); // fan-out targets converge with their full feed
    if (deprecatedContactsMigrated || backfilled) await saveState(doc._id, state);
    map.set(doc._id, state);
  }
  return map;
}

/**
 * Applies a mutation to every given member's state and persists each one.
 * `mutate(state)` returns the new state (or mutates in place and returns it).
 * Members without an existing state are skipped. Returns the requester's
 * updated state.
 *
 * This is the single fan-out primitive reused by settlement + settle-expense
 * (REQUIREMENTS §10) so multi-user demo state stays consistent.
 */
export async function fanOut(memberIds, requesterId, mutate) {
  const states = await getStates(memberIds);
  let requesterState = null;

  await Promise.all(
    memberIds.map(async (memberId) => {
      const current = states.get(memberId);
      if (!current) return;
      const updated = mutate(structuredClone(current));
      await saveState(memberId, updated);
      if (memberId === requesterId) requesterState = updated;
    }),
  );

  return requesterState;
}
