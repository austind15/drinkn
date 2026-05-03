import { Router } from 'express';
import { supabase } from '../supabase.js';
import { verifyAppleIdentityToken } from '../utils/appleAuth.js';
import { signSession } from '../utils/session.js';

const router = Router();

// POST /auth/apple
// Body: { identityToken: string, nickname?: string }
// - Verifies the Apple identity token.
// - Looks up or creates the user keyed by Apple's `sub`.
// - Returns { token, user, profileComplete }.
router.post('/apple', async (req, res, next) => {
  try {
    const { identityToken } = req.body || {};
    if (!identityToken) {
      return res.status(400).json({ error: 'identityToken is required' });
    }

    const payload = await verifyAppleIdentityToken(identityToken);
    const appleId = payload.sub;

    let { data: user, error: lookupErr } = await supabase
      .from('users')
      .select('*')
      .eq('apple_id', appleId)
      .maybeSingle();
    if (lookupErr) throw lookupErr;

    if (!user) {
      // Create a stub user with a placeholder nickname; iOS will force the
      // user through profile setup before they can use the app.
      const stubNickname = `user_${appleId.slice(-8)}`;
      const { data: created, error: insertErr } = await supabase
        .from('users')
        .insert({ apple_id: appleId, nickname: stubNickname })
        .select('*')
        .single();
      if (insertErr) throw insertErr;
      user = created;
    }

    const token = signSession(user.id);
    const profileComplete =
      !!user.profile_picture_url && !user.nickname.startsWith('user_');

    res.json({ token, user, profileComplete });
  } catch (err) {
    if (err?.code?.startsWith('ERR_JWT')) {
      return res.status(401).json({ error: 'Invalid Apple identity token' });
    }
    next(err);
  }
});

export default router;
