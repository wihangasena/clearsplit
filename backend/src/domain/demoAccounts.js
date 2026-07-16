/**
 * Hardcoded demo accounts and extra contacts (REQUIREMENTS §12). These eliminate
 * auth infrastructure for the prototype. All accounts share the password below.
 */
export const DEMO_PASSWORD = 'demo123';

export const DEMO_ACCOUNTS = [
  { id: 'you', displayName: 'Chenuri', email: 'chenuri@gmail.com', avatar: '🙂', color: '#2563EB' },
  { id: 'alex', displayName: 'Ushani', email: 'ushani@gmail.com', avatar: '🧑', color: '#10B981' },
  { id: 'maya', displayName: 'Nimsara', email: 'nimsara@gmail.com', avatar: '👩', color: '#8B5CF6' },
  { id: 'jordan', displayName: 'Janidu', email: 'janidu@gmail.com', avatar: '🧔', color: '#EF4444' },
];

const DEMO_NAME_BY_ID = Object.fromEntries(
  DEMO_ACCOUNTS.map((a) => [a.id, a.displayName]),
);

const DEPRECATED_DEMO_ID_MAP = {
  chloe: 'alex',
  sam: 'maya',
};

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

function remapId(id) {
  return DEPRECATED_DEMO_ID_MAP[id] ?? id;
}

function remapIdList(list) {
  if (!Array.isArray(list)) return list;
  const seen = new Set();
  const next = [];
  let changed = false;
  for (const id of list) {
    const mapped = remapId(id);
    if (mapped !== id) changed = true;
    if (seen.has(mapped)) {
      changed = true;
      continue;
    }
    seen.add(mapped);
    next.push(mapped);
  }
  return changed ? next : list;
}

function remapSplits(splits) {
  if (!splits || typeof splits !== 'object') return splits;
  const next = {};
  let changed = false;
  for (const [id, value] of Object.entries(splits)) {
    const mapped = remapId(id);
    next[mapped] = (next[mapped] ?? 0) + value;
    if (mapped !== id) changed = true;
  }
  return changed ? next : splits;
}

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
      person.name = ACCOUNT_NAME_BY_ID[person.id] ?? 'Chenuri';
    }
  }
  return state;
}

/**
 * Migrates old demo states that still reference the removed Sam/Chloe demo
 * contacts. Mutates and returns whether anything changed.
 */
export function normalizeDeprecatedDemoContacts(state) {
  if (!state || !Array.isArray(state.people)) return false;

  let changed = false;

  for (const person of state.people) {
    const mappedId = remapId(person.id);
    if (mappedId !== person.id) {
      person.id = mappedId;
      changed = true;
    }
    const expectedName = DEMO_NAME_BY_ID[person.id];
    if (expectedName && person.name !== expectedName) {
      person.name = expectedName;
      changed = true;
    }
  }

  const uniquePeople = [];
  const seenPeople = new Set();
  for (const person of state.people) {
    if (seenPeople.has(person.id)) {
      changed = true;
      continue;
    }
    seenPeople.add(person.id);
    uniquePeople.push(person);
  }
  if (uniquePeople.length !== state.people.length) {
    state.people = uniquePeople;
  }

  if (Array.isArray(state.groups)) {
    for (const group of state.groups) {
      const members = remapIdList(group.members);
      const admins = remapIdList(group.admins);
      if (members !== group.members) {
        group.members = members;
        changed = true;
      }
      if (admins !== group.admins) {
        group.admins = admins;
        changed = true;
      }
    }
  }

  if (Array.isArray(state.expenses)) {
    for (const expense of state.expenses) {
      const paidBy = remapId(expense.paidBy);
      if (paidBy !== expense.paidBy) {
        expense.paidBy = paidBy;
        changed = true;
      }
      const createdBy = remapId(expense.createdBy);
      if (createdBy !== expense.createdBy) {
        expense.createdBy = createdBy;
        changed = true;
      }
      const participants = remapIdList(expense.participants);
      if (participants !== expense.participants) {
        expense.participants = participants;
        changed = true;
      }
      const splits = remapSplits(expense.splits);
      if (splits !== expense.splits) {
        expense.splits = splits;
        changed = true;
      }
      if (Array.isArray(expense.history)) {
        for (const entry of expense.history) {
          const user = remapId(entry.user);
          if (user !== entry.user) {
            entry.user = user;
            changed = true;
          }
        }
      }
      if (Array.isArray(expense.comments)) {
        for (const comment of expense.comments) {
          const userId = remapId(comment.userId);
          if (userId !== comment.userId) {
            comment.userId = userId;
            changed = true;
          }
        }
      }
    }
  }

  if (Array.isArray(state.settlements)) {
    for (const settlement of state.settlements) {
      const from = remapId(settlement.from);
      const to = remapId(settlement.to);
      if (from !== settlement.from) {
        settlement.from = from;
        changed = true;
      }
      if (to !== settlement.to) {
        settlement.to = to;
        changed = true;
      }
    }
  }

  if (Array.isArray(state.activity)) {
    for (const event of state.activity) {
      const actor = remapId(event.actor);
      if (actor !== event.actor) {
        event.actor = actor;
        changed = true;
      }
    }
  }

  return changed;
}
