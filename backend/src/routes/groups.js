import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { requireBody, requireString, requirePositiveNumber } from '../middleware/validate.js';
import { getState, saveState, fanOut } from '../db/stateStore.js';
import {
  validateExpenseSplits,
  canModifyExpense,
  pickEditableFields,
  makeHistoryEntry,
  describeExpenseChange,
  summarizeExpenseChanges,
  makeComment,
} from '../domain/expenses.js';
import { makeActivityEvent, appendActivity, ACTIVITY_TYPES } from '../domain/activity.js';
import {
  isGroupAdmin,
  addAdmin,
  removeAdmin,
  canRemoveMember,
  canAssignAdmin,
  canRevokeAdmin,
} from '../domain/groups.js';
import { groupMemberNetCents } from '../domain/balances.js';

const router = Router();

/** Resolves a group's member ids from the requester's own state. */
async function groupMembers(requesterId, groupId) {
  const state = await getState(requesterId);
  if (!state) throw new AppError(404, 'State not found');
  const group = state.groups.find((g) => g.id === groupId);
  if (!group) throw new AppError(404, 'Group not found');
  return group.members;
}

/**
 * Loads the requester's state + group and enforces admin permission. Throws 404
 * when missing, 403 when the requester isn't a group admin. Returns
 * `{ state, group }` so the caller can mutate the canonical group.
 */
async function authorizeAdmin(requesterId, groupId) {
  const state = await getState(requesterId);
  if (!state) throw new AppError(404, 'State not found');
  const group = state.groups.find((g) => g.id === groupId);
  if (!group) throw new AppError(404, 'Group not found');
  if (!isGroupAdmin(group, requesterId)) {
    throw new AppError(403, 'Only a group admin can manage members and roles');
  }
  return { state, group };
}

/**
 * Fans the requester's canonical group (members **and** admins) + the member
 * Person records out to every member's state, so each one converges. When
 * [removedMemberId] is given, that user is also updated — the group is dropped
 * from their own list. Persons are only *added* when missing, so a member's own
 * edited profile is never clobbered. Returns the requester's updated state.
 */
async function propagateGroupMembership(requesterId, groupId, { removedMemberId = null } = {}) {
  const state = await getState(requesterId);
  if (!state) throw new AppError(404, 'State not found');
  const group = state.groups.find((g) => g.id === groupId);
  if (!group) throw new AppError(404, 'Group not found');

  const canonicalGroup = {
    id: group.id,
    name: group.name,
    emoji: group.emoji,
    members: [...group.members],
    admins: [...(group.admins ?? [])],
  };
  const memberPeople = group.members
    .map((id) => state.people.find((p) => p.id === id))
    .filter(Boolean)
    .map((p) => ({ id: p.id, name: p.name, avatar: p.avatar, color: p.color }));

  const targets = [...group.members];
  if (removedMemberId && !targets.includes(removedMemberId)) targets.push(removedMemberId);

  const updated = await fanOut(targets, requesterId, (s) => {
    if (s.me === removedMemberId) {
      // The removed member loses the group from their own ledger.
      s.groups = s.groups.filter((g) => g.id !== groupId);
      return s;
    }
    const existing = s.groups.find((g) => g.id === groupId);
    if (existing) {
      existing.members = [...canonicalGroup.members];
      existing.admins = [...canonicalGroup.admins];
    } else {
      s.groups.push(structuredClone(canonicalGroup));
    }
    for (const person of memberPeople) {
      if (!s.people.some((p) => p.id === person.id)) {
        s.people.push({ ...person });
      }
    }
    return s;
  });

  if (!updated) throw new AppError(404, 'State not found');
  return updated;
}

/**
 * Loads the requester's group + expense and enforces edit/delete permission.
 * Throws 404 when missing, 403 when the requester may not modify the expense.
 */
async function authorizeExpense(requesterId, groupId, expenseId) {
  const state = await getState(requesterId);
  if (!state) throw new AppError(404, 'State not found');
  const group = state.groups.find((g) => g.id === groupId);
  if (!group) throw new AppError(404, 'Group not found');
  const expense = state.expenses.find((e) => e.id === expenseId);
  if (!expense) throw new AppError(404, 'Expense not found');
  if (!canModifyExpense({ expense, group, userId: requesterId })) {
    throw new AppError(403, 'Only the expense creator or a group admin can modify this expense');
  }
  return { group, expense };
}

// SET-02/04: record a settlement and fan it out to all group members.
router.post(
  '/groups/:groupId/settlements',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');
    const settlement = body.settlement;
    if (!settlement || typeof settlement !== 'object') {
      throw new AppError(400, 'Field "settlement" (object) is required');
    }
    requireString(settlement.id, 'settlement.id');
    requireString(settlement.from, 'settlement.from');
    requireString(settlement.to, 'settlement.to');
    requirePositiveNumber(settlement.amount, 'settlement.amount'); // SET-05

    const record = {
      id: settlement.id,
      groupId,
      from: settlement.from,
      to: settlement.to,
      amount: settlement.amount,
      date: settlement.date ?? new Date().toISOString(),
    };

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      if (!state.settlements.some((s) => s.id === record.id)) {
        state.settlements.push(record);
      }
      return state;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

// EXP-05: mark an expense settled and fan out to all group members.
router.post(
  '/groups/:groupId/expenses/:expenseId/settle',
  asyncHandler(async (req, res) => {
    const { groupId, expenseId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');

    const state = await getState(requesterId);
    if (!state) throw new AppError(404, 'State not found');
    const group = state.groups.find((g) => g.id === groupId);
    if (!group) throw new AppError(404, 'Group not found');
    const target = state.expenses.find((e) => e.id === expenseId);

    const event = makeActivityEvent({
      id: `act-${expenseId}-settle-${Date.now()}`,
      type: ACTIVITY_TYPES.EXPENSE_SETTLED,
      actor: requesterId,
      groupId,
      expenseId,
      title: target?.title ?? null,
      amount: target?.amount ?? null,
    });

    const updated = await fanOut(group.members, requesterId, (s) => {
      const expense = s.expenses.find((e) => e.id === expenseId);
      if (expense) expense.settled = true;
      appendActivity(s, event);
      return s;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

// EXP-01: create a group expense (validated) and fan out to all members,
// stamping the creator and an "added" history entry.
router.post(
  '/groups/:groupId/expenses',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');
    const expense = body.expense;
    if (!expense || typeof expense !== 'object') {
      throw new AppError(400, 'Field "expense" (object) is required');
    }
    requireString(expense.id, 'expense.id');
    requireString(expense.title, 'expense.title');
    requirePositiveNumber(expense.amount, 'expense.amount');

    const check = validateExpenseSplits(expense);
    if (!check.valid) throw new AppError(400, check.error);

    const record = {
      ...expense,
      groupId,
      createdBy: requesterId,
      settled: false,
      history: [makeHistoryEntry(requesterId, `added ${expense.title}`)],
      comments: [],
    };

    const event = makeActivityEvent({
      id: `act-${record.id}-add`,
      type: ACTIVITY_TYPES.EXPENSE_ADDED,
      actor: requesterId,
      groupId,
      expenseId: record.id,
      title: record.title,
      amount: record.amount,
    });

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      if (!state.expenses.some((e) => e.id === record.id)) {
        state.expenses.push(structuredClone(record));
      }
      appendActivity(state, event);
      return state;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

// EXP-edit: edit a group expense (creator/admin only, validated), recording a
// history entry describing the change, then fan out to all members.
router.put(
  '/groups/:groupId/expenses/:expenseId',
  asyncHandler(async (req, res) => {
    const { groupId, expenseId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');
    if (!body.expense || typeof body.expense !== 'object') {
      throw new AppError(400, 'Field "expense" (object) is required');
    }

    const { expense: existing } = await authorizeExpense(requesterId, groupId, expenseId);
    const updates = pickEditableFields(body.expense);
    const merged = { ...existing, ...updates };
    if (typeof merged.amount === 'number') requirePositiveNumber(merged.amount, 'expense.amount');

    const check = validateExpenseSplits(merged);
    if (!check.valid) throw new AppError(400, check.error);

    const description = describeExpenseChange(existing, merged);
    const event = makeActivityEvent({
      id: `act-${expenseId}-edit-${Date.now()}`,
      type: ACTIVITY_TYPES.EXPENSE_EDITED,
      actor: requesterId,
      groupId,
      expenseId,
      title: merged.title,
      amount: merged.amount,
      description: summarizeExpenseChanges(existing, merged),
    });

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      const e = state.expenses.find((x) => x.id === expenseId);
      if (e) {
        Object.assign(e, updates);
        e.createdBy = e.createdBy ?? e.paidBy;
        (e.history ??= []).push(makeHistoryEntry(requesterId, description));
      }
      appendActivity(state, event);
      return state;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

// EXP-delete: delete a group expense (creator/admin only) and fan out.
router.delete(
  '/groups/:groupId/expenses/:expenseId',
  asyncHandler(async (req, res) => {
    const { groupId, expenseId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');

    const { expense } = await authorizeExpense(requesterId, groupId, expenseId);
    const event = makeActivityEvent({
      id: `act-${expenseId}-del-${Date.now()}`,
      type: ACTIVITY_TYPES.EXPENSE_DELETED,
      actor: requesterId,
      groupId,
      expenseId,
      title: expense.title,
      amount: expense.amount,
    });

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      state.expenses = state.expenses.filter((e) => e.id !== expenseId);
      appendActivity(state, event);
      return state;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

// CMT-01: add a comment to a group expense and fan out. Comments never affect
// balances — they are stored alongside the expense.
router.post(
  '/groups/:groupId/expenses/:expenseId/comments',
  asyncHandler(async (req, res) => {
    const { groupId, expenseId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');
    const message = requireString(body.message, 'message');
    const commentId =
      typeof body.commentId === 'string' && body.commentId.trim()
        ? body.commentId
        : `cmt-${Date.now()}`;

    const comment = makeComment({ id: commentId, expenseId, userId: requesterId, message });

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      const e = state.expenses.find((x) => x.id === expenseId);
      if (e && !(e.comments ?? []).some((c) => c.id === comment.id)) {
        (e.comments ??= []).push(comment);
      }
      return state;
    });

    if (!updated) throw new AppError(404, 'State not found');
    res.json({ state: updated });
  }),
);

// GRP-membership: propagate a group's current membership to every member's
// state. The requester has already updated their own state and saved it; this
// fans the canonical group (members + admins) and the member Person records out
// so each member converges. Persons are only *added* when missing, so a
// member's own edited profile is never clobbered.
router.post(
  '/groups/:groupId/sync',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');

    const updated = await propagateGroupMembership(requesterId, groupId);
    res.json({ state: updated });
  }),
);

// GRP-02: add a member to a group (admin only) and fan out. The member's Person
// record (from the directory) is registered on the requester's state first.
router.post(
  '/groups/:groupId/members',
  asyncHandler(async (req, res) => {
    const { groupId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');
    const member = body.member;
    if (!member || typeof member !== 'object') {
      throw new AppError(400, 'Field "member" (object) is required');
    }
    const memberId = requireString(member.id, 'member.id');

    const { state, group } = await authorizeAdmin(requesterId, groupId);
    if (!group.members.includes(memberId)) group.members.push(memberId);
    if (!state.people.some((p) => p.id === memberId)) {
      state.people.push({
        id: memberId,
        name: member.name ?? memberId,
        avatar: member.avatar ?? '🙂',
        color: member.color ?? '#2563EB',
      });
    }
    await saveState(requesterId, state);

    const updated = await propagateGroupMembership(requesterId, groupId);
    res.json({ state: updated });
  }),
);

// GRP-02: remove a member from a group (admin only). Blocked when the member
// still has an outstanding balance in the group or is the last admin. Fans out
// to the remaining members and the removed member.
router.delete(
  '/groups/:groupId/members/:memberId',
  asyncHandler(async (req, res) => {
    const { groupId, memberId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');

    const { state, group } = await authorizeAdmin(requesterId, groupId);
    const balanceCents = groupMemberNetCents(state, groupId, memberId);
    const check = canRemoveMember(group, memberId, balanceCents);
    if (!check.valid) throw new AppError(check.error.includes('settled') ? 409 : 400, check.error);

    group.members = group.members.filter((id) => id !== memberId);
    group.admins = removeAdmin(group.admins ?? [], memberId);
    await saveState(requesterId, state);

    const updated = await propagateGroupMembership(requesterId, groupId, { removedMemberId: memberId });
    res.json({ state: updated });
  }),
);

// GRP-roles: promote a member to admin (admin only) and fan out.
router.put(
  '/groups/:groupId/admins/:memberId',
  asyncHandler(async (req, res) => {
    const { groupId, memberId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');

    const { state, group } = await authorizeAdmin(requesterId, groupId);
    const check = canAssignAdmin(group, memberId);
    if (!check.valid) throw new AppError(400, check.error);

    group.admins = addAdmin(group.admins ?? [], memberId);
    await saveState(requesterId, state);

    const updated = await propagateGroupMembership(requesterId, groupId);
    res.json({ state: updated });
  }),
);

// GRP-roles: revoke a member's admin role (admin only). Blocked when it would
// leave the group with no admin. Fans out.
router.delete(
  '/groups/:groupId/admins/:memberId',
  asyncHandler(async (req, res) => {
    const { groupId, memberId } = req.params;
    const body = requireBody(req.body);
    const requesterId = requireString(body.requesterId, 'requesterId');

    const { state, group } = await authorizeAdmin(requesterId, groupId);
    const check = canRevokeAdmin(group, memberId);
    if (!check.valid) throw new AppError(400, check.error);

    group.admins = removeAdmin(group.admins ?? [], memberId);
    await saveState(requesterId, state);

    const updated = await propagateGroupMembership(requesterId, groupId);
    res.json({ state: updated });
  }),
);

export default router;
