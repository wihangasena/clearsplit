import { DEMO_ACCOUNTS, EXTRA_CONTACTS } from './demoAccounts.js';

/**
 * Builds the shared demo world (people, groups, expenses) used to seed a fresh
 * account on first login (REQUIREMENTS §12). Every account is seeded with the
 * same world so members see a consistent ledger; only `me` differs per account.
 *
 * Dates are ISO strings relative to "now" so the activity feed always has a
 * realistic TODAY / EARLIER spread.
 */
function daysAgo(days) {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString();
}

function people() {
  const fromAccounts = DEMO_ACCOUNTS.map((a) => ({
    id: a.id,
    name: a.displayName,
    avatar: a.avatar,
    color: a.color,
  }));
  const contacts = EXTRA_CONTACTS.map((c) => ({
    id: c.id,
    name: c.name,
    avatar: c.avatar,
    color: c.color,
  }));
  return [...fromAccounts, ...contacts];
}

function groups() {
  return [
    { id: 'beach-house', name: 'Beach House', emoji: '🏖️', members: ['you', 'alex', 'maya', 'jordan'], admins: ['you'] },
    { id: 'apartment-crew', name: 'Apartment Crew', emoji: '🏠', members: ['you', 'alex', 'chloe'], admins: ['you'] },
    { id: 'road-trip', name: 'Road Trip 2026', emoji: '🚗', members: ['you', 'maya', 'sam'], admins: ['you'] },
  ];
}

function expense({
  id,
  title,
  amount,
  paidBy,
  participants,
  groupId = null,
  category,
  date,
  note = null,
  splitMethod = 'equal',
  splits = {},
  createdBy = paidBy,
}) {
  return {
    id,
    title,
    amount,
    paidBy,
    participants,
    groupId,
    category,
    date,
    note,
    splitMethod,
    splits,
    settled: false,
    createdBy,
    history: [{ user: createdBy, action: `added ${title}`, timestamp: date }],
    comments: [],
  };
}

function expenses() {
  return [
    // Beach House (equal splits)
    expense({ id: 'exp-1', title: 'Groceries', amount: 120, paidBy: 'you', participants: ['you', 'alex', 'maya', 'jordan'], groupId: 'beach-house', category: 'food', date: daysAgo(0) }),
    expense({ id: 'exp-2', title: 'Beach house rent', amount: 800, paidBy: 'alex', participants: ['you', 'alex', 'maya', 'jordan'], groupId: 'beach-house', category: 'home', date: daysAgo(2) }),
    expense({ id: 'exp-3', title: 'Gas for the drive', amount: 60, paidBy: 'maya', participants: ['you', 'maya', 'jordan'], groupId: 'beach-house', category: 'transport', date: daysAgo(3) }),

    // Apartment Crew (one percentage split)
    expense({ id: 'exp-4', title: 'Internet bill', amount: 75, paidBy: 'you', participants: ['you', 'alex', 'chloe'], groupId: 'apartment-crew', category: 'utilities', date: daysAgo(1) }),
    expense({ id: 'exp-5', title: 'Cleaning supplies', amount: 45, paidBy: 'chloe', participants: ['you', 'alex', 'chloe'], groupId: 'apartment-crew', category: 'home', date: daysAgo(5), splitMethod: 'percentage', splits: { you: 40, alex: 40, chloe: 20 } }),

    // Road Trip (one exact-amount split)
    expense({ id: 'exp-6', title: 'Fuel', amount: 90, paidBy: 'you', participants: ['you', 'maya', 'sam'], groupId: 'road-trip', category: 'transport', date: daysAgo(0) }),
    expense({ id: 'exp-7', title: 'Hotel night', amount: 240, paidBy: 'maya', participants: ['you', 'maya', 'sam'], groupId: 'road-trip', category: 'travel', date: daysAgo(4), splitMethod: 'amount', splits: { you: 80, maya: 80, sam: 80 } }),
    expense({ id: 'exp-8', title: 'Road snacks', amount: 30, paidBy: 'sam', participants: ['you', 'maya', 'sam'], groupId: 'road-trip', category: 'food', date: daysAgo(6) }),

    // Non-group (friend) expenses
    expense({ id: 'exp-9', title: 'Movie tickets', amount: 36, paidBy: 'you', participants: ['you', 'alex'], category: 'entertainment', date: daysAgo(1) }),
    expense({ id: 'exp-10', title: 'Dinner out', amount: 64, paidBy: 'maya', participants: ['you', 'maya'], category: 'food', date: daysAgo(2) }),
  ];
}

/** Produces a complete AppData snapshot for the given account id. */
export function seedForAccount(accountId) {
  return {
    me: accountId,
    people: people(),
    groups: groups(),
    expenses: expenses(),
    settlements: [],
  };
}

/**
 * Produces an empty starter state for a freshly registered member: just
 * themselves, no demo world. They build up their ledger by adding real members
 * (searched from the directory) to groups and expenses.
 */
export function seedForNewMember(member) {
  return {
    me: member.id,
    people: [
      {
        id: member.id,
        name: member.name,
        avatar: member.avatar ?? '🙂',
        color: member.color ?? '#2563EB',
      },
    ],
    groups: [],
    expenses: [],
    settlements: [],
  };
}
