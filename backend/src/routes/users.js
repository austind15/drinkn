import { Router } from 'express';
import multer from 'multer';
import { supabase, STORAGE_BUCKET } from '../supabase.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { resolveGroupMemberIds } from '../utils/groupFilter.js';

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
});

// GET /users/me
router.get('/me', requireAuth, (req, res) => {
  res.json({ user: req.user });
});

// PUT /users/me
// multipart fields: nickname?, profilePicture? (file)
router.put('/me', requireAuth, upload.single('profilePicture'), async (req, res, next) => {
  try {
    const updates = {};
    const nickname = (req.body?.nickname || '').trim();
    if (nickname) {
      if (nickname.length < 2 || nickname.length > 30) {
        return res.status(400).json({ error: 'Nickname must be 2–30 characters' });
      }
      updates.nickname = nickname;
    }

    if (req.file) {
      const ext = (req.file.mimetype.split('/')[1] || 'jpg').toLowerCase();
      const path = `avatars/${req.user.id}-${Date.now()}.${ext}`;
      const { error: uploadErr } = await supabase.storage
        .from(STORAGE_BUCKET)
        .upload(path, req.file.buffer, {
          contentType: req.file.mimetype,
          upsert: true,
        });
      if (uploadErr) throw uploadErr;
      // Storage bucket is private; return a long-lived signed URL.
      const { data: signed, error: signErr } = await supabase.storage
        .from(STORAGE_BUCKET)
        .createSignedUrl(path, 60 * 60 * 24 * 365); // 1 year
      if (signErr) throw signErr;
      updates.profile_picture_url = signed.signedUrl;
    }

    if (Object.keys(updates).length === 0) {
      return res.json({ user: req.user });
    }

    const { data: updated, error: updateErr } = await supabase
      .from('users')
      .update(updates)
      .eq('id', req.user.id)
      .select('*')
      .single();

    if (updateErr) {
      if (updateErr.code === '23505') {
        return res.status(409).json({ error: 'Nickname is already taken' });
      }
      throw updateErr;
    }

    res.json({ user: updated });
  } catch (err) {
    next(err);
  }
});

// GET /users — leaderboard.
// Query params:
//   ?search=<nickname-fragment>
//   ?groupId=<uuid> (restrict to that group's members)
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const search = (req.query.search || '').trim();
    const memberIds = await resolveGroupMemberIds(req.query.groupId);

    if (memberIds !== null) {
      // Group-scoped: hand-build the leaderboard from beers + users.
      if (memberIds.length === 0) return res.json({ users: [] });

      let userQuery = supabase
        .from('users')
        .select('id, nickname, profile_picture_url')
        .in('id', memberIds);
      if (search) userQuery = userQuery.ilike('nickname', `%${search}%`);
      const { data: members, error: uErr } = await userQuery;
      if (uErr) throw uErr;

      const { data: beers, error: bErr } = await supabase
        .from('beers')
        .select('user_id')
        .in('user_id', memberIds);
      if (bErr) throw bErr;

      const counts = new Map();
      for (const b of beers || []) {
        counts.set(b.user_id, (counts.get(b.user_id) || 0) + 1);
      }
      const users = (members || [])
        .map((m) => ({
          user_id: m.id,
          nickname: m.nickname,
          profile_picture_url: m.profile_picture_url,
          total_beers: counts.get(m.id) || 0,
        }))
        .sort((a, b) => b.total_beers - a.total_beers);

      return res.json({ users });
    }

    // Global leaderboard via the materialised view.
    let query = supabase.from('v_leaderboard').select('*');
    if (search) {
      query = query.ilike('nickname', `%${search}%`);
    }
    const { data, error } = await query;
    if (error) throw error;
    res.json({ users: data });
  } catch (err) {
    next(err);
  }
});

// GET /users/search?q=<fragment> — Social tab user search.
// Returns users matching the nickname + whether the current user follows them.
router.get('/search', requireAuth, async (req, res, next) => {
  try {
    const q = (req.query.q || '').trim();
    let usersQuery = supabase
      .from('users')
      .select('id, nickname, profile_picture_url')
      .neq('id', req.user.id)
      .limit(50);
    if (q) usersQuery = usersQuery.ilike('nickname', `%${q}%`);

    const { data: users, error } = await usersQuery;
    if (error) throw error;

    const ids = (users || []).map((u) => u.id);
    let followingSet = new Set();
    if (ids.length > 0) {
      const { data: follows } = await supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', req.user.id)
        .in('following_id', ids);
      followingSet = new Set((follows || []).map((f) => f.following_id));
    }

    res.json({
      users: (users || []).map((u) => ({
        ...u,
        is_following: followingSet.has(u.id),
      })),
    });
  } catch (err) {
    next(err);
  }
});

// GET /users/:id/stats?tzOffsetMinutes=NNN
router.get('/:id/stats', requireAuth, async (req, res, next) => {
  try {
    const { id } = req.params;
    const tzOffsetMinutes = Number(req.query.tzOffsetMinutes) || 0;
    const { data: user, error: userErr } = await supabase
      .from('users')
      .select('id, nickname, profile_picture_url, created_at')
      .eq('id', id)
      .single();
    if (userErr || !user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const { data: beers, error: beerErr } = await supabase
      .from('beers')
      .select('id, photo_url, timestamp, latitude, longitude, location_name, note, drink_type')
      .eq('user_id', id)
      .order('timestamp', { ascending: false });
    if (beerErr) throw beerErr;

    const stats = computePersonalStats(beers || [], tzOffsetMinutes);

    // Total upvotes received across this user's beers
    const { data: voteTotals } = await supabase
      .from('v_user_vote_totals')
      .select('net_score, total_upvotes, total_downvotes')
      .eq('user_id', id)
      .maybeSingle();

    // Whether the requesting user follows this profile
    let isFollowing = false;
    if (req.user.id !== id) {
      const { data: f } = await supabase
        .from('follows')
        .select('follower_id')
        .eq('follower_id', req.user.id)
        .eq('following_id', id)
        .maybeSingle();
      isFollowing = !!f;
    }

    // Follower / following counts
    const [{ count: followersCount }, { count: followingCount }] = await Promise.all([
      supabase.from('follows').select('*', { count: 'exact', head: true }).eq('following_id', id),
      supabase.from('follows').select('*', { count: 'exact', head: true }).eq('follower_id', id),
    ]);

    res.json({
      user,
      stats: {
        ...stats,
        netScore: voteTotals?.net_score ?? 0,
        totalUpvotes: voteTotals?.total_upvotes ?? 0,
        totalDownvotes: voteTotals?.total_downvotes ?? 0,
        followers: followersCount ?? 0,
        following: followingCount ?? 0,
      },
      beers,
      isFollowing,
    });
  } catch (err) {
    next(err);
  }
});

function computePersonalStats(beers, tzOffsetMinutes = 0) {
  const total = beers.length;
  const drinkBreakdown = ['beer', 'wine', 'spirits', 'cocktail', 'cider'].map((type) => ({
    type,
    count: 0,
  }));

  if (total === 0) {
    return {
      total: 0,
      currentStreak: 0,
      longestStreak: 0,
      mostActiveDayOfWeek: null,
      mostActiveHour: null,
      timeline: [],
      drinkTypes: drinkBreakdown,
    };
  }

  const byDay = new Map();
  const dayOfWeekCounts = new Array(7).fill(0);
  const hourCounts = new Array(24).fill(0);
  const drinkCounts = new Map();

  for (const b of beers) {
    const utc = new Date(b.timestamp);
    const local = new Date(utc.getTime() + tzOffsetMinutes * 60_000);
    const dayKey = local.toISOString().slice(0, 10);
    byDay.set(dayKey, (byDay.get(dayKey) || 0) + 1);
    dayOfWeekCounts[local.getUTCDay()] += 1;
    hourCounts[local.getUTCHours()] += 1;

    const dt = b.drink_type || 'beer';
    drinkCounts.set(dt, (drinkCounts.get(dt) || 0) + 1);
  }

  for (const row of drinkBreakdown) {
    row.count = drinkCounts.get(row.type) || 0;
  }

  // Streaks (UTC days)
  const sortedDays = [...byDay.keys()].sort();
  let longest = 0;
  let running = 0;
  let prev = null;
  for (const day of sortedDays) {
    if (prev === null) {
      running = 1;
    } else {
      const prevDate = new Date(prev + 'T00:00:00Z');
      const cur = new Date(day + 'T00:00:00Z');
      const diff = Math.round((cur - prevDate) / 86400000);
      running = diff === 1 ? running + 1 : 1;
    }
    if (running > longest) longest = running;
    prev = day;
  }

  // Current streak: consecutive days ending today (in user's local TZ) or yesterday
  const today = new Date(Date.now() + tzOffsetMinutes * 60_000).toISOString().slice(0, 10);
  let currentStreak = 0;
  let cursor = today;
  if (!byDay.has(cursor)) {
    const y = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
    cursor = byDay.has(y) ? y : null;
  }
  while (cursor && byDay.has(cursor)) {
    currentStreak += 1;
    const prevDay = new Date(new Date(cursor + 'T00:00:00Z').getTime() - 86400000);
    cursor = prevDay.toISOString().slice(0, 10);
  }

  const mostActiveDayOfWeek = dayOfWeekCounts.indexOf(Math.max(...dayOfWeekCounts));
  const mostActiveHour = hourCounts.indexOf(Math.max(...hourCounts));

  const timeline = sortedDays.map((day) => ({ date: day, count: byDay.get(day) }));

  return {
    total,
    currentStreak,
    longestStreak: longest,
    mostActiveDayOfWeek,
    mostActiveHour,
    timeline,
    drinkTypes: drinkBreakdown,
  };
}

export default router;
