import { Router } from 'express';
import multer from 'multer';
import { supabase, STORAGE_BUCKET } from '../supabase.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { blurCoordinate } from '../utils/geo.js';
import { resolveGroupMemberIds } from '../utils/groupFilter.js';

const router = Router();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 }, // 15 MB
});

const SIGNED_URL_TTL = 60 * 60 * 24 * 365; // 1 year
const ALLOWED_DRINK_TYPES = ['beer', 'wine', 'spirits', 'cocktail', 'cider'];

async function signPhoto(path) {
  const { data, error } = await supabase.storage
    .from(STORAGE_BUCKET)
    .createSignedUrl(path, SIGNED_URL_TTL);
  if (error) throw error;
  return data.signedUrl;
}

// Decorate a list of beers with current user's vote and the per-beer score.
async function attachVoteData(beers, currentUserId) {
  if (!beers || beers.length === 0) return beers;
  const ids = beers.map((b) => b.id);

  const { data: scores } = await supabase
    .from('v_beer_vote_scores')
    .select('beer_id, score, upvotes, downvotes')
    .in('beer_id', ids);
  const scoreMap = new Map((scores || []).map((s) => [s.beer_id, s]));

  const { data: myVotes } = await supabase
    .from('beer_votes')
    .select('beer_id, vote')
    .eq('user_id', currentUserId)
    .in('beer_id', ids);
  const myVoteMap = new Map((myVotes || []).map((v) => [v.beer_id, v.vote]));

  for (const b of beers) {
    const s = scoreMap.get(b.id);
    b.score = s?.score ?? 0;
    b.upvotes = s?.upvotes ?? 0;
    b.downvotes = s?.downvotes ?? 0;
    b.my_vote = myVoteMap.get(b.id) ?? 0;
  }
  return beers;
}

// POST /beers — log a beer
// multipart fields: photo (file, required), latitude?, longitude?, locationName?, note?, drinkType?
router.post('/', requireAuth, upload.single('photo'), async (req, res, next) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'photo is required' });
    }
    const { latitude, longitude, locationName, note, drinkType } = req.body || {};

    if (note && note.length > 140) {
      return res.status(400).json({ error: 'note must be ≤ 140 characters' });
    }

    let resolvedDrinkType = 'beer';
    if (drinkType) {
      const dt = String(drinkType).toLowerCase();
      if (!ALLOWED_DRINK_TYPES.includes(dt)) {
        return res.status(400).json({ error: `drinkType must be one of ${ALLOWED_DRINK_TYPES.join(', ')}` });
      }
      resolvedDrinkType = dt;
    }

    const ext = (req.file.mimetype.split('/')[1] || 'jpg').toLowerCase();
    const path = `beers/${req.user.id}/${Date.now()}.${ext}`;

    const { error: uploadErr } = await supabase.storage
      .from(STORAGE_BUCKET)
      .upload(path, req.file.buffer, {
        contentType: req.file.mimetype,
        upsert: false,
      });
    if (uploadErr) throw uploadErr;

    const photoUrl = await signPhoto(path);

    const insert = {
      user_id: req.user.id,
      photo_url: photoUrl,
      latitude: blurCoordinate(latitude),
      longitude: blurCoordinate(longitude),
      location_name: locationName?.trim() || null,
      note: note?.trim() || null,
      drink_type: resolvedDrinkType,
    };

    const { data, error } = await supabase
      .from('beers')
      .insert(insert)
      .select('*')
      .single();
    if (error) throw error;

    res.status(201).json({ beer: data });
  } catch (err) {
    next(err);
  }
});

// GET /beers — paginated list, newest first.
// Optional ?groupId=<uuid> filters to that group's members.
// Optional ?mode=recent|following|group controls feed scope.
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 20, 100);
    const offset = Math.max(Number(req.query.offset) || 0, 0);
    const mode = req.query.mode || 'recent'; // recent | following | group

    let memberIds = null;

    if (mode === 'following') {
      const { data: follows, error: fErr } = await supabase
        .from('follows')
        .select('following_id')
        .eq('follower_id', req.user.id);
      if (fErr) throw fErr;
      memberIds = (follows || []).map((f) => f.following_id);
      if (memberIds.length === 0) return res.json({ beers: [], limit, offset });
    } else if (mode === 'group') {
      memberIds = await resolveGroupMemberIds(req.query.groupId);
      if (memberIds !== null && memberIds.length === 0) return res.json({ beers: [], limit, offset });
    }
    // mode === 'recent' → memberIds stays null → no filter

    let query = supabase
      .from('beers')
      .select(`
        id, photo_url, timestamp, latitude, longitude, location_name, note, drink_type,
        user:user_id ( id, nickname, profile_picture_url )
      `)
      .order('timestamp', { ascending: false })
      .range(offset, offset + limit - 1);

    if (memberIds !== null) {
      query = query.in('user_id', memberIds);
    }

    const { data, error } = await query;
    if (error) throw error;

    await attachVoteData(data, req.user.id);
    res.json({ beers: data, limit, offset });
  } catch (err) {
    next(err);
  }
});

// GET /beers/total
// Optional ?groupId=<uuid> filters to that group's members.
router.get('/total', requireAuth, async (req, res, next) => {
  try {
    const memberIds = await resolveGroupMemberIds(req.query.groupId);
    let q = supabase.from('beers').select('id', { count: 'exact', head: true });
    if (memberIds !== null) {
      if (memberIds.length === 0) return res.json({ total: 0, goal: 1_000_000 });
      q = q.in('user_id', memberIds);
    }
    const { count, error } = await q;
    if (error) throw error;
    res.json({ total: count ?? 0, goal: 1_000_000 });
  } catch (err) {
    next(err);
  }
});

// GET /beers/map — beers with coordinates
router.get('/map', requireAuth, async (req, res, next) => {
  try {
    const memberIds = await resolveGroupMemberIds(req.query.groupId);
    let q = supabase
      .from('beers')
      .select(`
        id, photo_url, timestamp, latitude, longitude, location_name, drink_type,
        user:user_id ( id, nickname )
      `)
      .not('latitude', 'is', null)
      .not('longitude', 'is', null)
      .order('timestamp', { ascending: false });
    if (memberIds !== null) {
      if (memberIds.length === 0) return res.json({ beers: [] });
      q = q.in('user_id', memberIds);
    }
    const { data, error } = await q;
    if (error) throw error;
    res.json({ beers: data });
  } catch (err) {
    next(err);
  }
});

// GET /beers/stats — aggregates for the charts
// Optional ?tzOffsetMinutes=NNN  (positive minutes east of UTC; e.g. Perth = +480).
// Optional ?groupId=<uuid> filters to that group's members.
router.get('/stats', requireAuth, async (req, res, next) => {
  try {
    const userId = req.user.id;
    const tzOffsetMinutes = Number(req.query.tzOffsetMinutes) || 0;
    const memberIds = await resolveGroupMemberIds(req.query.groupId);

    let q = supabase.from('beers').select('id, user_id, timestamp, drink_type');
    if (memberIds !== null) {
      if (memberIds.length === 0) {
        return res.json({
          total: 0,
          myCount: 0,
          byHour: Array.from({ length: 24 }, (_, hour) => ({ hour, count: 0 })),
          byDayOfWeek: Array.from({ length: 7 }, (_, day) => ({ day, count: 0 })),
          byWeek: [],
          byMonth: [],
          cumulative: [],
          topUsers: [],
          weekTotal: 0,
          drinkTypes: [],
        });
      }
      q = q.in('user_id', memberIds);
    }

    const { data: beers, error } = await q;
    if (error) throw error;

    const total = beers.length;

    const byHour = new Array(24).fill(0);
    const byDayOfWeek = new Array(7).fill(0);
    const byWeek = new Map();
    const byMonth = new Map();
    const byDay = new Map();
    const byUser = new Map();
    const byDrink = new Map();
    const myCount = beers.filter((b) => b.user_id === userId).length;

    // Use a single shared "this week" cutoff: 7 days ago (in UTC) so the
    // count is consistent regardless of where in the day the user looks.
    const weekCutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
    let weekTotal = 0;

    for (const b of beers) {
      // Shift the UTC timestamp by the user's offset, then read components as
      // if it were UTC. This gives us the date/time as the user sees it.
      const utc = new Date(b.timestamp);
      const local = new Date(utc.getTime() + tzOffsetMinutes * 60_000);
      byHour[local.getUTCHours()] += 1;
      byDayOfWeek[local.getUTCDay()] += 1;

      const dayKey = local.toISOString().slice(0, 10);
      byDay.set(dayKey, (byDay.get(dayKey) || 0) + 1);

      const monthKey = dayKey.slice(0, 7);
      byMonth.set(monthKey, (byMonth.get(monthKey) || 0) + 1);

      const weekKey = isoWeekKey(local);
      byWeek.set(weekKey, (byWeek.get(weekKey) || 0) + 1);

      byUser.set(b.user_id, (byUser.get(b.user_id) || 0) + 1);

      const dt = b.drink_type || 'beer';
      byDrink.set(dt, (byDrink.get(dt) || 0) + 1);

      if (utc.getTime() >= weekCutoff) weekTotal += 1;
    }

    // Top 10 drinkers — fetch nicknames in one go
    const topUserIds = [...byUser.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .map(([id]) => id);

    let topUsers = [];
    if (topUserIds.length > 0) {
      const { data: userRows, error: userErr } = await supabase
        .from('users')
        .select('id, nickname, profile_picture_url')
        .in('id', topUserIds);
      if (userErr) throw userErr;
      topUsers = topUserIds.map((id) => {
        const u = userRows.find((u) => u.id === id);
        return {
          user_id: id,
          nickname: u?.nickname || 'unknown',
          profile_picture_url: u?.profile_picture_url || null,
          count: byUser.get(id),
        };
      });
    }

    // Cumulative team total over time (by day)
    const sortedDays = [...byDay.keys()].sort();
    let running = 0;
    const cumulative = sortedDays.map((d) => {
      running += byDay.get(d);
      return { date: d, total: running };
    });

    const drinkTypes = ['beer', 'wine', 'spirits', 'cocktail', 'cider'].map((type) => ({
      type,
      count: byDrink.get(type) || 0,
    }));

    res.json({
      total,
      myCount,
      weekTotal,
      byHour: byHour.map((count, hour) => ({ hour, count })),
      byDayOfWeek: byDayOfWeek.map((count, day) => ({ day, count })),
      byWeek: [...byWeek.entries()]
        .sort()
        .map(([week, count]) => ({ week, count })),
      byMonth: [...byMonth.entries()]
        .sort()
        .map(([month, count]) => ({ month, count })),
      cumulative,
      topUsers,
      drinkTypes,
    });
  } catch (err) {
    next(err);
  }
});

function isoWeekKey(date) {
  // Returns "YYYY-Www" using ISO week numbering
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNum = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(weekNum).padStart(2, '0')}`;
}

export default router;
