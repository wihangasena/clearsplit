import { Router } from 'express';
import { asyncHandler } from '../utils/asyncHandler.js';
import { AppError } from '../utils/AppError.js';
import { requireBody, requireString, requirePositiveNumber } from '../middleware/validate.js';
import { getState, fanOut } from '../db/stateStore.js';
import {
  validateExpenseSplits,
  canModifyExpense,
  pickEditableFields,
  makeHistoryEntry,
  describeExpenseChange,
  makeComment,
} from '../domain/expenses.js';

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

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      const expense = state.expenses.find((e) => e.id === expenseId);
      if (expense) expense.settled = true;
      return state;
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

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      if (!state.expenses.some((e) => e.id === record.id)) {
        state.expenses.push(structuredClone(record));
      }
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
    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      const e = state.expenses.find((x) => x.id === expenseId);
      if (e) {
        Object.assign(e, updates);
        e.createdBy = e.createdBy ?? e.paidBy;
        (e.history ??= []).push(makeHistoryEntry(requesterId, description));
      }
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

    await authorizeExpense(requesterId, groupId, expenseId);

    const members = await groupMembers(requesterId, groupId);
    const updated = await fanOut(members, requesterId, (state) => {
      state.expenses = state.expenses.filter((e) => e.id !== expenseId);
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

export default router;
