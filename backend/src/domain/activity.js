/**
 * Pure activity-feed helpers (ClearSplit business-logic spec). No I/O, no side
 * effects — safe to unit test and to mirror in the Dart client so both sides
 * agree on the event shape and wording.
 *
 * The activity log is an append-only audit trail of everything that touches a
 * group's ledger: an expense added, edited, deleted, or marked settled. Each
 * event is fanned out to every group member (exactly like the expense itself)
 * so each user sees the records relevant to them — and, crucially, a *deleted*
 * expense still leaves a permanent trace nobody can quietly erase.
 *
 * Settlements (payments) are not duplicated here — they already fan out as
 * `settlements` and the Activity feed renders them straight from that list.
 */

/** Activity event kinds. */
export const ACTIVITY_TYPES = Object.freeze({
  EXPENSE_ADDED: 'expense_added',
  EXPENSE_EDITED: 'expense_edited',
  EXPENSE_DELETED: 'expense_deleted',
  EXPENSE_SETTLED: 'expense_settled',
});

/**
 * Builds one append-only activity event. `title`/`amount` are snapshots taken
 * at event time so a deleted expense still renders in the feed after the
 * expense record itself is gone. `description` carries the human-readable
 * detail for edits (e.g. "amount from 2500 to 3000").
 */
export function makeActivityEvent({
  id,
  type,
  actor,
  groupId = null,
  expenseId = null,
  title = null,
  amount = null,
  description = '',
  at = new Date(),
}) {
  return {
    id,
    type,
    actor,
    groupId,
    expenseId,
    title,
    amount,
    description,
    timestamp: at instanceof Date ? at.toISOString() : at,
  };
}

/**
 * Appends [event] to a state's activity log, creating the list if absent and
 * skipping a duplicate id (so a re-fanned event lands at most once per member).
 */
export function appendActivity(state, event) {
  state.activity ??= [];
  if (!state.activity.some((a) => a.id === event.id)) {
    state.activity.push(structuredClone(event));
  }
  return state;
}

/**
 * One-time migration for states seeded before the activity log existed: when a
 * state has no `activity` array at all, derives an "added" event per existing
 * expense so the Activity feed isn't blank for established accounts. States that
 * already carry an activity array (even an empty one) are left untouched.
 * Mutates [state] in place; returns `true` when it changed something.
 */
export function backfillActivity(state) {
  if (!state || Array.isArray(state.activity)) return false;
  const expenses = Array.isArray(state.expenses) ? state.expenses : [];
  state.activity = expenses.map((e) =>
    makeActivityEvent({
      id: `act-${e.id}-add`,
      type: ACTIVITY_TYPES.EXPENSE_ADDED,
      actor: e.createdBy ?? e.paidBy,
      groupId: e.groupId ?? null,
      expenseId: e.id,
      title: e.title,
      amount: e.amount,
      at: e.date,
    }),
  );
  return true;
}
