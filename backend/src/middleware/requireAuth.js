import { verifySession } from '../utils/session.js';
import { supabase } from '../supabase.js';

export async function requireAuth(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const match = header.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      return res.status(401).json({ error: 'Missing bearer token' });
    }
    const payload = verifySession(match[1]);
    const userId = payload.sub;
    const { data: user, error } = await supabase
      .from('users')
      .select('*')
      .eq('id', userId)
      .single();
    if (error || !user) {
      return res.status(401).json({ error: 'Invalid session' });
    }
    req.user = user;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid session' });
  }
}
