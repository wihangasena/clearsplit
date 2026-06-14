/**
 * Pure expense business rules (ClearSplit business-logic spec). No I/O, no side
 * effects — safe to unit test and to mirror in the Dart client so both sides
 * agree on validation, permissions, and history wording.
 *
 * Covers:
 *  - Split validation (fixed amounts sum to total; percentages sum to 100).
 *  - Edit/delete permission (creator OR group admin).
 *  - History entries (user / action / timestamp).
 *  - Comment construction (never affects balances).
 */

/** Money/percentage comparisons tolerate a 1-cent / 0.01% rounding gap. */
const SPLIT_TOLERANCE = 0.01;

/** Fields a client is allowed to change when editing an expense. */
export const EDITABLE_EXPENSE_FIELDS = [
  'title',
  'amount',
  'paidBy',
  'participants',
  'groupId',
  'category',
  'date',
  'note',
  'splitMethod',
  'splits',
];

/**
 * Validates an expense's split against its method.
 * Returns `{ valid, error }` — `error` is a human-readable reason when invalid.
 *  - equal:      always valid (shares derived from participant count).
 *  - amount:     per-person amounts must sum to the total.
 *  - percentage: per-person percentages must sum to 100.
 */
export function validateExpenseSplits(expense) {
  const method = expense.splitMethod ?? 'equal';
  const participants = expense.participants ?? [];
  if (method === 'equal') return { valid: true, error: null };

  const splits = expense.splits ?? {};
  let total = 0;
  for (const id of participants) total += Number(splits[id] ?? 0);

  if (method === 'amount') {
    if (Math.abs(total - expense.amount) > SPLIT_TOLERANCE) {
      return {
        valid: false,
        error: `Exact amounts must add up to ${expense.amount} (got ${total})`,
      };
    }
    return { valid: true, error: null };
  }

  if (method === 'percentage') {
    if (Math.abs(total - 100) > SPLIT_TOLERANCE) {
      return {
        valid: false,
        error: `Percentages must add up to 100 (got ${total})`,
      };
    }
    return { valid: true, error: null };
  }

  return { valid: false, error: `Unknown split method "${method}"` };
}

/**
 * Group admins. Roles aren't modelled yet, so the group creator — represented
 * by an explicit `admins` list when present, otherwise the first member — is
 * treated as admin.
 */
export function isGroupAdmin(group, userId) {
  if (!group) return false;
  const admins = group.admins ?? (group.members?.length ? [group.members[0]] : []);
  return admins.includes(userId);
}

/**
 * Edit/delete permission: only the expense creator or a group admin may modify
 * an expense. Legacy expenses without `createdBy` fall back to the payer.
 */
export function canModifyExpense({ expense, group, userId }) {
  if (!expense) return false;
  const creator = expense.createdBy ?? expense.paidBy;
  return userId === creator || isGroupAdmin(group, userId);
}

/** Keeps only the editable fields from a client-supplied patch. */
export function pickEditableFields(updates) {
  const out = {};
  for (const field of EDITABLE_EXPENSE_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(updates, field)) {
      out[field] = updates[field];
    }
  }
  return out;
}

/** A single audit-log entry: who did what, and when. */
export function makeHistoryEntry(user, action, at = new Date()) {
  return {
    user,
    action,
    timestamp: at instanceof Date ? at.toISOString() : at,
  };
}

/**
 * Human-readable summary of what changed between two expense snapshots,
 * e.g. `edited Dinner amount from 2500 to 3000`.
 */
export function describeExpenseChange(before, after) {
  const parts = [];
  if (before.title !== after.title) {
    parts.push(`title from "${before.title}" to "${after.title}"`);
  }
  if (before.amount !== after.amount) {
    parts.push(`amount from ${before.amount} to ${after.amount}`);
  }
  if (before.category !== after.category) {
    parts.push(`category from ${before.category} to ${after.category}`);
  }
  if (before.splitMethod !== after.splitMethod) {
    parts.push(`split from ${before.splitMethod} to ${after.splitMethod}`);
  }
  const name = after.title ?? before.title;
  return parts.length === 0 ? `edited ${name}` : `edited ${name} ${parts.join(', ')}`;
}

/** A comment on an expense. Comments never affect balances. */
export function makeComment({ id, expenseId, userId, message, at = new Date() }) {
  return {
    id,
    expenseId,
    userId,
    message,
    timestamp: at instanceof Date ? at.toISOString() : at,
  };
}
