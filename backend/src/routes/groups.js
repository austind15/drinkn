import { Router } from 'express';
import { supabase } from '../supabase.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireGroupAdmin, requireGroupMember } from '../utils/groupFilter.js';

const router = Router();

// GET /groups — list groups the current user belongs to
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('group_members')
      .select(`
        role,
        group:groups (
          id, name, description, created_by, created_at
        )
      `)
      .eq('user_id', req.user.id);
    if (error) throw error;

    const groups = (data || [])
      .filter((row) => row.group)
      .map((row) => ({ ...row.group, role: row.role }));

    // Tack on member counts in one extra query.
    if (groups.length > 0) {
      const ids = groups.map((g) => g.id);
      const { data: counts, error: cErr } = await supabase
        .from('group_members')
        .select('group_id')
        .in('group_id', ids);
      if (cErr) throw cErr;
      const byGroup = new Map();
      for (const c of counts || []) {
        byGroup.set(c.group_id, (byGroup.get(c.group_id) || 0) + 1);
      }
      for (const g of groups) g.member_count = byGroup.get(g.id) || 0;
    }

    res.json({ groups });
  } catch (err) {
    next(err);
  }
});

// GET /groups/discover — list groups the user is NOT in (for browsing)
router.get('/discover', requireAuth, async (req, res, next) => {
  try {
    const search = (req.query.search || '').trim();

    const { data: myMemberships, error: memErr } = await supabase
      .from('group_members')
      .select('group_id')
      .eq('user_id', req.user.id);
    if (memErr) throw memErr;
    const mineIds = new Set((myMemberships || []).map((r) => r.group_id));

    let q = supabase
      .from('groups')
      .select('id, name, description, created_by, created_at');
    if (search) q = q.ilike('name', `%${search}%`);
    const { data, error } = await q.limit(50);
    if (error) throw error;

    const groups = (data || []).filter((g) => !mineIds.has(g.id));
    res.json({ groups });
  } catch (err) {
    next(err);
  }
});

// POST /groups — create a group; creator becomes admin
router.post('/', requireAuth, async (req, res, next) => {
  try {
    const name = (req.body?.name || '').trim();
    const description = (req.body?.description || '').trim() || null;
    if (name.length < 2 || name.length > 50) {
      return res.status(400).json({ error: 'Name must be 2–50 characters' });
    }
    if (description && description.length > 280) {
      return res.status(400).json({ error: 'Description must be ≤ 280 characters' });
    }

    const { data: group, error: insertErr } = await supabase
      .from('groups')
      .insert({ name, description, created_by: req.user.id })
      .select('*')
      .single();
    if (insertErr) throw insertErr;

    const { error: memberErr } = await supabase
      .from('group_members')
      .insert({ group_id: group.id, user_id: req.user.id, role: 'admin' });
    if (memberErr) throw memberErr;

    res.status(201).json({ group: { ...group, role: 'admin', member_count: 1 } });
  } catch (err) {
    next(err);
  }
});

// GET /groups/:id — group details + member list (must be a member)
router.get('/:id', requireAuth, async (req, res, next) => {
  try {
    const { id } = req.params;
    await requireGroupMember(id, req.user.id);

    const { data: group, error: gErr } = await supabase
      .from('groups')
      .select('*')
      .eq('id', id)
      .single();
    if (gErr) throw gErr;

    const { data: members, error: mErr } = await supabase
      .from('group_members')
      .select(`
        role, joined_at,
        user:user_id ( id, nickname, profile_picture_url )
      `)
      .eq('group_id', id);
    if (mErr) throw mErr;

    res.json({
      group,
      members: (members || []).map((m) => ({
        id: m.user?.id,
        nickname: m.user?.nickname,
        profile_picture_url: m.user?.profile_picture_url,
        role: m.role,
        joined_at: m.joined_at,
      })),
    });
  } catch (err) {
    next(err);
  }
});

// GET /groups/:id/invite-search?q= — search users to invite (not already members)
router.get('/:id/invite-search', requireAuth, async (req, res, next) => {
  try {
    const { id } = req.params;
    await requireGroupMember(id, req.user.id);

    const q = (req.query.q || '').trim();

    // Get existing member IDs so we can exclude them
    const { data: members, error: mErr } = await supabase
      .from('group_members')
      .select('user_id')
      .eq('group_id', id);
    if (mErr) throw mErr;
    const memberIds = new Set((members || []).map((m) => m.user_id));

    let usersQuery = supabase
      .from('users')
      .select('id, nickname, profile_picture_url')
      .neq('id', req.user.id)
      .limit(20);
    if (q) usersQuery = usersQuery.ilike('nickname', `%${q}%`);

    const { data: users, error: uErr } = await usersQuery;
    if (uErr) throw uErr;

    // Filter out existing members
    const results = (users || []).filter((u) => !memberIds.has(u.id));

    // Mark which ones already have a pending invite
    const resultIds = results.map((u) => u.id);
    let pendingSet = new Set();
    if (resultIds.length > 0) {
      const { data: pending } = await supabase
        .from('group_invites')
        .select('invited_user')
        .eq('group_id', id)
        .eq('status', 'pending')
        .in('invited_user', resultIds);
      pendingSet = new Set((pending || []).map((p) => p.invited_user));
    }

    res.json({
      users: results.map((u) => ({ ...u, invite_pending: pendingSet.has(u.id) })),
    });
  } catch (err) {
    next(err);
  }
});

// POST /groups/:id/invites — invite a user by userId; must be a group member
router.post('/:id/invites', requireAuth, async (req, res, next) => {
  try {
    const { id } = req.params;
    await requireGroupMember(id, req.user.id);

    // Accept either userId (UUID) or nickname (legacy fallback)
    let targetId = (req.body?.userId || '').trim();
    let targetNickname = '';

    if (!targetId) {
      // Legacy: look up by exact nickname
      const nickname = (req.body?.nickname || '').trim();
      if (!nickname) {
        return res.status(400).json({ error: 'userId or nickname is required' });
      }
      const { data: target, error: lookupErr } = await supabase
        .from('users')
        .select('id, nickname')
        .ilike('nickname', nickname)
        .limit(1)
        .maybeSingle();
      if (lookupErr) throw lookupErr;
      if (!target) {
        return res.status(404).json({ error: `No user found matching "${nickname}"` });
      }
      targetId = target.id;
      targetNickname = target.nickname;
    } else {
      const { data: target } = await supabase
        .from('users')
        .select('nickname')
        .eq('id', targetId)
        .maybeSingle();
      targetNickname = target?.nickname || targetId;
    }

    // Already a member?
    const { data: existing, error: exErr } = await supabase
      .from('group_members')
      .select('user_id')
      .eq('group_id', id)
      .eq('user_id', targetId)
      .maybeSingle();
    if (exErr) throw exErr;
    if (existing) {
      return res.status(409).json({ error: `${targetNickname} is already in this group` });
    }

    // Already a pending invite?
    const { data: pending } = await supabase
      .from('group_invites')
      .select('id')
      .eq('group_id', id)
      .eq('invited_user', targetId)
      .eq('status', 'pending')
      .maybeSingle();
    if (pending) {
      return res.status(409).json({ error: `${targetNickname} already has a pending invite` });
    }

    const { data: invite, error: insErr } = await supabase
      .from('group_invites')
      .insert({
        group_id: id,
        invited_by: req.user.id,
        invited_user: targetId,
      })
      .select('*')
      .single();
    if (insErr) throw insErr;

    res.status(201).json({ invite });
  } catch (err) {
    next(err);
  }
});

// GET /groups/invites/incoming — invites awaiting the current user's response
router.get('/invites/incoming', requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('group_invites')
      .select(`
        id, status, created_at,
        group:groups ( id, name, description ),
        invited_by_user:users!group_invites_invited_by_fkey ( id, nickname, profile_picture_url )
      `)
      .eq('invited_user', req.user.id)
      .eq('status', 'pending')
      .order('created_at', { ascending: false });
    if (error) throw error;
    res.json({ invites: data || [] });
  } catch (err) {
    next(err);
  }
});

// POST /groups/invites/:inviteId/accept
router.post('/invites/:inviteId/accept', requireAuth, async (req, res, next) => {
  try {
    const { inviteId } = req.params;
    const { data: invite, error: lookupErr } = await supabase
      .from('group_invites')
      .select('*')
      .eq('id', inviteId)
      .single();
    if (lookupErr) throw lookupErr;
    if (invite.invited_user !== req.user.id) {
      return res.status(403).json({ error: 'Not your invite' });
    }
    if (invite.status !== 'pending') {
      return res.status(409).json({ error: 'Invite is no longer pending' });
    }

    const { error: memErr } = await supabase
      .from('group_members')
      .upsert(
        { group_id: invite.group_id, user_id: req.user.id, role: 'member' },
        { onConflict: 'group_id,user_id' }
      );
    if (memErr) throw memErr;

    const { error: updErr } = await supabase
      .from('group_invites')
      .update({ status: 'accepted', responded_at: new Date().toISOString() })
      .eq('id', inviteId);
    if (updErr) throw updErr;

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// POST /groups/invites/:inviteId/decline
router.post('/invites/:inviteId/decline', requireAuth, async (req, res, next) => {
  try {
    const { inviteId } = req.params;
    const { data: invite, error: lookupErr } = await supabase
      .from('group_invites')
      .select('*')
      .eq('id', inviteId)
      .single();
    if (lookupErr) throw lookupErr;
    if (invite.invited_user !== req.user.id) {
      return res.status(403).json({ error: 'Not your invite' });
    }

    const { error: updErr } = await supabase
      .from('group_invites')
      .update({ status: 'declined', responded_at: new Date().toISOString() })
      .eq('id', inviteId);
    if (updErr) throw updErr;

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// POST /groups/:id/leave
router.post('/:id/leave', requireAuth, async (req, res, next) => {
  try {
    const { id } = req.params;
    const { error } = await supabase
      .from('group_members')
      .delete()
      .eq('group_id', id)
      .eq('user_id', req.user.id);
    if (error) throw error;
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// POST /groups/:id/members/:memberId/promote — admin only
router.post('/:id/members/:memberId/promote', requireAuth, async (req, res, next) => {
  try {
    const { id, memberId } = req.params;
    await requireGroupAdmin(id, req.user.id);

    const { error } = await supabase
      .from('group_members')
      .update({ role: 'admin' })
      .eq('group_id', id)
      .eq('user_id', memberId);
    if (error) throw error;
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

export default router;
