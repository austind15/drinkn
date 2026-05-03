import { Router } from 'express';
import { supabase } from '../supabase.js';
import { requireAuth } from '../middleware/requireAuth.js';

const router = Router();

// POST /follows/:userId — follow a user
router.post('/:userId', requireAuth, async (req, res, next) => {
  try {
    const { userId } = req.params;
    if (userId === req.user.id) {
      return res.status(400).json({ error: 'Cannot follow yourself' });
    }
    const { error } = await supabase
      .from('follows')
      .upsert(
        { follower_id: req.user.id, following_id: userId },
        { onConflict: 'follower_id,following_id' }
      );
    if (error) throw error;
    res.json({ ok: true, following: true });
  } catch (err) {
    next(err);
  }
});

// DELETE /follows/:userId — unfollow
router.delete('/:userId', requireAuth, async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { error } = await supabase
      .from('follows')
      .delete()
      .eq('follower_id', req.user.id)
      .eq('following_id', userId);
    if (error) throw error;
    res.json({ ok: true, following: false });
  } catch (err) {
    next(err);
  }
});

// GET /follows/me — list users the current user follows
router.get('/me', requireAuth, async (req, res, next) => {
  try {
    const { data, error } = await supabase
      .from('follows')
      .select(`
        following_id,
        user:users!follows_following_id_fkey ( id, nickname, profile_picture_url )
      `)
      .eq('follower_id', req.user.id);
    if (error) throw error;
    res.json({ users: (data || []).map((r) => r.user).filter(Boolean) });
  } catch (err) {
    next(err);
  }
});

// GET /follows/:userId/followers — users who follow :userId
router.get('/:userId/followers', requireAuth, async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { data, error } = await supabase
      .from('follows')
      .select(`
        follower_id,
        user:users!follows_follower_id_fkey ( id, nickname, profile_picture_url )
      `)
      .eq('following_id', userId);
    if (error) throw error;

    const users = (data || []).map((r) => r.user).filter(Boolean);
    const ids = users.map((u) => u.id);
    let followingSet = new Set();
    if (ids.length > 0) {
      const { data: follows } = await supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', req.user.id)
        .in('following_id', ids);
      followingSet = new Set((follows || []).map((f) => f.following_id));
    }
    res.json({ users: users.map((u) => ({ ...u, is_following: followingSet.has(u.id) })) });
  } catch (err) {
    next(err);
  }
});

// GET /follows/:userId/following — users that :userId follows
router.get('/:userId/following', requireAuth, async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { data, error } = await supabase
      .from('follows')
      .select(`
        following_id,
        user:users!follows_following_id_fkey ( id, nickname, profile_picture_url )
      `)
      .eq('follower_id', userId);
    if (error) throw error;

    const users = (data || []).map((r) => r.user).filter(Boolean);
    const ids = users.map((u) => u.id);
    let followingSet = new Set();
    if (ids.length > 0) {
      const { data: follows } = await supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', req.user.id)
        .in('following_id', ids);
      followingSet = new Set((follows || []).map((f) => f.following_id));
    }
    res.json({ users: users.map((u) => ({ ...u, is_following: followingSet.has(u.id) })) });
  } catch (err) {
    next(err);
  }
});

export default router;
