/**
 * Pure group membership + role rules (ClearSplit business-logic spec). No I/O,
 * no side effects — safe to unit test and to mirror in the Dart client so both
 * sides agree on who may manage a group and when a change is allowed.
 *
 * Roles are two-tier: a group has an `admins` list (a subset of `members`).
 * Admins control access — add/remove members and promote/demote admins — and a
 * group must always keep at least one admin.
 */

import { isGroupAdmin } from './expenses.js';

export { isGroupAdmin };

/** Resolves a group's effective admin ids (explicit list, else first member). */
export function groupAdmins(group) {
  if (!group) return [];
  if (Array.isArray(group.admins) && group.admins.length > 0) return group.admins;
  return group.members?.length ? [group.members[0]] : [];
}

/** Returns a copy of [admins] with [id] added (no duplicates). */
export function addAdmin(admins, id) {
  return admins.includes(id) ? [...admins] : [...admins, id];
}

/** Returns a copy of [admins] with [id] removed. */
export function removeAdmin(admins, id) {
  return admins.filter((a) => a !== id);
}

/**
 * Whether [memberId] may be removed from [group]. Invalid when they aren't a
 * member, when they still have an outstanding balance in the group
 * (`balanceCents !== 0`), or when removing them would leave the group with no
 * admin. Returns `{ valid, error }`.
 */
export function canRemoveMember(group, memberId, balanceCents) {
  if (!group || !(group.members ?? []).includes(memberId)) {
    return { valid: false, error: 'That person is not a member of this group' };
  }
  if (balanceCents !== 0) {
    return {
      valid: false,
      error: 'Member must be settled up in this group before they can be removed',
    };
  }
  const admins = groupAdmins(group);
  if (admins.includes(memberId) && admins.length <= 1) {
    return {
      valid: false,
      error: 'Promote another member to admin before removing the last admin',
    };
  }
  return { valid: true, error: null };
}

/**
 * Whether [memberId] may be promoted to admin. Invalid when they aren't a
 * member. Already-admin is treated as a valid no-op. Returns `{ valid, error }`.
 */
export function canAssignAdmin(group, memberId) {
  if (!group || !(group.members ?? []).includes(memberId)) {
    return { valid: false, error: 'Only a group member can be made an admin' };
  }
  return { valid: true, error: null };
}

/**
 * Whether [memberId]'s admin role may be revoked. Invalid when revoking it would
 * leave the group with no admin. Returns `{ valid, error }`.
 */
export function canRevokeAdmin(group, memberId) {
  const admins = groupAdmins(group);
  if (admins.includes(memberId) && admins.length <= 1) {
    return { valid: false, error: 'A group must keep at least one admin' };
  }
  return { valid: true, error: null };
}
