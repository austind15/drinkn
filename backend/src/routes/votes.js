import { Router } from 'express';
import { supabase } from '../supabase.js';
import { requireAuth } from '../middleware/requireAuth.js';

const router = Router();

// POST /votes/:beerId  body: { vote: 1 | -1 | 0 }
//   1  → upvote
//  -1  → downvote
//   0  → clear vote
router.post('/:beerId', requireAuth, async (req, res, next) => {
  try {
    const { beerId } = req.params;
    const raw = Number(req.body?.vote);
    if (![1, -1, 0].includes(raw)) {
      return res.status(400).json({ error: 'vote must be 1, -1, or 0' });
    }

    if (raw === 0) {
      const { error } = await supabase
        .from('beer_votes')
        .delete()
        .eq('user_id', req.user.id)
        .eq('beer_id', beerId);
      if (error) throw error;
    } else {
      const { error } = await supabase
        .from('beer_votes')
        .upsert(
          { user_id: req.user.id, beer_id: beerId, vote: raw },
          { onConflict: 'user_id,beer_id' }
        );
      if (error) throw error;
    }

    // Return the new score for this beer
    const { data: scoreRow } = await supabase
      .from('v_beer_vote_scores')
      .select('score, upvotes, downvotes')
      .eq('beer_id', beerId)
      .maybeSingle();

    res.json({
      score: scoreRow?.score ?? 0,
      upvotes: scoreRow?.upvotes ?? 0,
      downvotes: scoreRow?.downvotes ?? 0,
      myVote: raw,
    });
  } catch (err) {
    next(err);
  }
});

export default router;
