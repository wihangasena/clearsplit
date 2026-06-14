/**
 * Hardcoded demo accounts and extra contacts (REQUIREMENTS §12). These eliminate
 * auth infrastructure for the prototype. All accounts share the password below.
 */
export const DEMO_PASSWORD = 'demo123';

export const DEMO_ACCOUNTS = [
  { id: 'you', displayName: 'Riley', email: 'you@clearsplit.app', avatar: '🙂', color: '#2563EB' },
  { id: 'alex', displayName: 'Alex', email: 'alex@clearsplit.app', avatar: '🧑', color: '#10B981' },
  { id: 'maya', displayName: 'Maya', email: 'maya@clearsplit.app', avatar: '👩', color: '#8B5CF6' },
  { id: 'jordan', displayName: 'Jordan', email: 'jordan@clearsplit.app', avatar: '🧔', color: '#EF4444' },
];

/** Contacts that participate in expenses/groups but cannot sign in. */
export const EXTRA_CONTACTS = [
  { id: 'chloe', name: 'Chloe', avatar: '👧', color: '#F59E0B' },
  { id: 'sam', name: 'Sam', avatar: '🧒', color: '#0EA5E9' },
];

/** Public view of an account (password stripped) for the /accounts endpoint. */
export function publicAccount(account) {
  return {
    id: account.id,
    displayName: account.displayName,
    email: account.email,
    avatar: account.avatar,
    color: account.color,
  };
}

export function findAccountByEmail(email) {
  const normalized = String(email).trim().toLowerCase();
  return DEMO_ACCOUNTS.find((a) => a.email.toLowerCase() === normalized) ?? null;
}

const ACCOUNT_NAME_BY_ID = Object.fromEntries(
  DEMO_ACCOUNTS.map((a) => [a.id, a.displayName]),
);

/**
 * Retro-fixes states seeded before the primary account had a real name: it used
 * to be literally named "You", which read as a mess once the app also shows
 * "You" for whoever is signed in. Renames *only* that stale literal to the
 * account's canonical name, so a user's own custom profile name is never
 * clobbered. Mutates and returns the state.
 */
export function normalizeLegacyNames(state) {
  if (!state || !Array.isArray(state.people)) return state;
  for (const person of state.people) {
    if (person.name === 'You') {
      person.name = ACCOUNT_NAME_BY_ID[person.id] ?? 'Riley';
    }
  }
  return state;
}
