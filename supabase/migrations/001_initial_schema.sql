-- 🍺 1 Million Beers — initial schema
-- Run this in the Supabase SQL editor (or via the Supabase CLI).

-- Extensions
create extension if not exists "uuid-ossp";

-- ───────────────────────────────────────────────────────────────────────────
-- users
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.users (
  id uuid primary key default uuid_generate_v4(),
  apple_id text not null unique,
  nickname text not null unique,
  profile_picture_url text,
  created_at timestamptz not null default now()
);

create index if not exists users_apple_id_idx on public.users (apple_id);

-- ───────────────────────────────────────────────────────────────────────────
-- beers
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.beers (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  photo_url text not null,
  timestamp timestamptz not null default now(),
  latitude double precision,
  longitude double precision,
  location_name text,
  note text check (note is null or char_length(note) <= 140),
  created_at timestamptz not null default now()
);

create index if not exists beers_user_id_idx on public.beers (user_id);
create index if not exists beers_timestamp_idx on public.beers (timestamp desc);

-- ───────────────────────────────────────────────────────────────────────────
-- Row-Level Security
-- The Node backend uses the service role key and bypasses RLS, so the policies
-- here exist only as defence-in-depth: if anyone ever connects to Supabase
-- with the anon/public key they get nothing.
-- ───────────────────────────────────────────────────────────────────────────
alter table public.users enable row level security;
alter table public.beers enable row level security;

-- No anon policies — everything goes through the backend's service role.

-- ───────────────────────────────────────────────────────────────────────────
-- Storage bucket for beer photos
-- ───────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('beer-photos', 'beer-photos', false)
on conflict (id) do nothing;

-- ───────────────────────────────────────────────────────────────────────────
-- Helpful aggregate views (used by /beers/stats)
-- ───────────────────────────────────────────────────────────────────────────
create or replace view public.v_beer_totals as
select count(*)::bigint as total from public.beers;

create or replace view public.v_leaderboard as
select
  u.id as user_id,
  u.nickname,
  u.profile_picture_url,
  count(b.id)::bigint as total_beers
from public.users u
left join public.beers b on b.user_id = u.id
group by u.id, u.nickname, u.profile_picture_url
order by total_beers desc;
