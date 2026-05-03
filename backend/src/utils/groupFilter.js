import { supabase } from '../supabase.js';

/**
 * Resolves a `groupId` query parameter into a list of user IDs to scope stats by.
 *
 * - If groupId is missing/blank/'all', returns null (meaning "all users — no filter").
 * - If groupId is a UUID, looks up the group's members and returns their user IDs.
 *   The caller is expected to enforce that the requesting user actually belongs
 *   to that group; we don't gate on membership here so admins can preview.
 *
 * Returns either null (no filter) or an array of UUID strings (possibly empty
 * if the group has no members — in which case caller should return zeroed stats).
 */
export async function resolveGroupMemberIds(groupId) {
  if (!groupId || groupId === 'all' || groupId === '') return null;
  const { data, error } = await supabase
    .from('group_members')
    .select('user_id')
    .eq('group_id', groupId);
  if (error) throw error;
  return (data || []).map((r) => r.user_id);
}

/**
 * Throws a 403 if the requesting user is not a member of the group.
 */
export async function requireGroupMember(groupId, userId) {
  const { data, error } = await supabase
    .from('group_members')
    .select('role')
    .eq('group_id', groupId)
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    const e = new Error('Not a member of this group');
    e.status = 403;
    throw e;
  }
  return data.role;
}

/**
 * Throws a 403 if the requesting user is not an admin of the group.
 */
export async function requireGroupAdmin(groupId, userId) {
  const role = await requireGroupMember(groupId, userId);
  if (role !== 'admin') {
    const e = new Error('Admin role required');
    e.status = 403;
    throw e;
  }
}
