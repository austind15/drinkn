import { createClient } from '@supabase/supabase-js';

const rawUrl = process.env.SUPABASE_URL?.trim();
const url = rawUrl?.replace(/\/+$/, ''); // drop trailing slashes
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

if (!url || !serviceKey) {
  throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
}

console.log(`[supabase] using URL: ${url}`);

export const supabase = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

export const STORAGE_BUCKET = process.env.SUPABASE_STORAGE_BUCKET || 'beer-photos';
