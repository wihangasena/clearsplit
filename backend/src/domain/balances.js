/**
 * Pure balance + settlement algorithms (REQUIREMENTS §11). No I/O, no side
 * effects — safe to unit test and to mirror exactly in the Dart client so both
 * sides agree on every figure.
 *
 * Money is kept in integer cents internally to avoid floating-point drift, then
 * rounded back to 2-decimal dollars on output.
 *
 * NOTE on per-person balances: the literal formula in REQUIREMENTS §11
 * (`perPerson[id] = balances[id] - balances[me]`) is incorrect — for a simple
 * "I paid $36, split with Alex" it yields -$36 instead of Alex owing me +$18.
 * We instead compute the correct *pairwise* net between `me` and each person.
 * This is consistent: the sum of all pairwise nets equals my own multilateral
 * net balance, so the "you are owed / you owe" aggregates still reconcile.
 */

const toCents = (dollars) => Math.round(dollars * 100);
const toDollars = (cents) => Math.round(cents) / 100;

/**
 * Resolves a participant's share of an expense based on its split method.
 *
 * Equal splits are penny-accurate: remainder cents that don't divide evenly are
 * handed one-at-a-time to the first participants (largest-remainder), so the
 * shares always sum back to the exact total — just like Splitwise. Without this,
 * a $100 split 3 ways leaves a stray cent and the group never reconciles to 0.
 */
export function getParticipantShare(expense, personId) {
  if (!expense.participants.includes(personId)) return 0;
  switch (expense.splitMethod) {
    case 'amount':
      return expense.splits?.[personId] ?? 0;
    case 'percentage':
      return (expense.amount * (expense.splits?.[personId] ?? 0)) / 100;
    case 'equal':
    default: {
      const n = expense.participants.length;
      if (n === 0) return 0;
      const totalCents = Math.round(expense.amount * 100);
      const base = Math.floor(totalCents / n);
      const remainder = totalCents - base * n; // cents to distribute
      const index = expense.participants.indexOf(personId);
      const cents = base + (index < remainder ? 1 : 0);
      return cents / 100;
    }
  }
}

/**
 * Multilateral net ledger in cents for every person: positive = others owe them
 * overall. Optionally filtered to a single group. Used for group debt
 * simplification.
 */
function rawBalances(state, groupId = null) {
  const balances = {};
  const add = (id, cents) => {
    balances[id] = (balances[id] ?? 0) + cents;
  };

  for (const expense of state.expenses) {
    if (expense.settled) continue;
    if (groupId !== null && expense.groupId !== groupId) continue;
    add(expense.paidBy, toCents(expense.amount));
    for (const personId of expense.participants) {
      add(personId, -toCents(getParticipantShare(expense, personId)));
    }
  }

  for (const settlement of state.settlements) {
    if (groupId !== null && settlement.groupId !== groupId) continue;
    add(settlement.from, toCents(settlement.amount));
    add(settlement.to, -toCents(settlement.amount));
  }

  return balances;
}

/**
 * Pairwise net in cents between `me` and every other person.
 * Result[x] > 0 → x owes me; < 0 → I owe x.
 */
function pairwiseBalances(state) {
  const me = state.me;
  const perPerson = {};
  const add = (id, cents) => {
    perPerson[id] = (perPerson[id] ?? 0) + cents;
  };

  for (const expense of state.expenses) {
    if (expense.settled) continue;
    const meParticipates = expense.participants.includes(me);
    if (expense.paidBy === me) {
      // Each other participant owes me their share.
      for (const personId of expense.participants) {
        if (personId === me) continue;
        add(personId, toCents(getParticipantShare(expense, personId)));
      }
    } else if (meParticipates) {
      // I owe the payer my share.
      add(expense.paidBy, -toCents(getParticipantShare(expense, me)));
    }
  }

  for (const s of state.settlements) {
    if (s.from === me) add(s.to, toCents(s.amount)); // I paid them → reduces my debt
    else if (s.to === me) add(s.from, -toCents(s.amount)); // they paid me → reduces their debt
  }

  return perPerson;
}

/**
 * BalanceSummary relative to the signed-in user (state.me).
 * perPerson[id] > 0 → they owe me; < 0 → I owe them.
 */
export function computeBalances(state) {
  const raw = pairwiseBalances(state);

  const perPerson = {};
  let owedCents = 0;
  let oweCents = 0;

  for (const person of state.people) {
    if (person.id === state.me) continue;
    const cents = raw[person.id] ?? 0;
    perPerson[person.id] = toDollars(cents);
    if (cents > 0) owedCents += cents;
    else if (cents < 0) oweCents += -cents;
  }

  return {
    owed: toDollars(owedCents),
    owe: toDollars(oweCents),
    net: toDollars(owedCents - oweCents),
    perPerson,
  };
}

/**
 * Greedy debt simplification for a group (REQUIREMENTS §11): the minimum set of
 * payments to clear all balances. Returns { debtorId: [{ to, amount }, ...] }.
 */
export function computeGroupSettlements(state, groupId) {
  const balances = rawBalances(state, groupId);

  const creditors = [];
  const debtors = [];
  for (const [id, cents] of Object.entries(balances)) {
    if (cents > 0) creditors.push({ id, cents });
    else if (cents < 0) debtors.push({ id, cents: -cents });
  }
  creditors.sort((a, b) => b.cents - a.cents);
  debtors.sort((a, b) => b.cents - a.cents);

  const payments = {};
  let ci = 0;
  let di = 0;
  while (ci < creditors.length && di < debtors.length) {
    const creditor = creditors[ci];
    const debtor = debtors[di];
    const transfer = Math.min(creditor.cents, debtor.cents);

    if (transfer > 0) {
      (payments[debtor.id] ??= []).push({ to: creditor.id, amount: toDollars(transfer) });
    }
    creditor.cents -= transfer;
    debtor.cents -= transfer;
    if (creditor.cents === 0) ci += 1;
    if (debtor.cents === 0) di += 1;
  }

  return payments;
}
