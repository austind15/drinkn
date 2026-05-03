-- 🍺 1 Million Beers — schema additions for Groups, Votes, Drink Types, Follows
-- Run this in the Supabase SQL editor after 001_initial_schema.sql.

-- ───────────────────────────────────────────────────────────────────────────
-- Drink types on beers (Feature 6)
-- Existing logs default to 'beer' so historical data is preserved.
-- ───────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'drink_type') then
    create type drink_type as enum ('beer', 'wine', 'spirits', 'cocktail', 'cider');
  end if;
end$$;

alter table public.beers
  add column if not exists drink_type drink_type not null default 'beer';

create index if not exists beers_drink_type_idx on public.beers (drink_type);

-- ───────────────────────────────────────────────────────────────────────────
-- Groups (Feature 4)
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.groups (
  id uuid primary key default uuid_generate_v4(),
  name text not null check (char_length(name) between 2 and 50),
  description text check (description is null or char_length(description) <= 280),
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists groups_created_by_idx on public.groups (created_by);

-- group_members: which users are in which groups, and their role
create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id  uuid not null references public.users(id)  on delete cascade,
  role text not null default 'member' check (role in ('member', 'admin')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index if not exists group_members_user_id_idx on public.group_members (user_id);

-- group_invites: pending invites by username; redeemed when target accepts
create table if not exists public.group_invites (
  id uuid primary key default uuid_generate_v4(),
  group_id  uuid not null references public.groups(id) on delete cascade,
  invited_by uuid not null references public.users(id) on delete cascade,
  invited_user uuid not null references public.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (group_id, invited_user, status) deferrable initially deferred
);

create index if not exists group_invites_invited_user_idx on public.group_invites (invited_user, status);
create index if not exists group_invites_group_idx on public.group_invites (group_id);

alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;

-- ───────────────────────────────────────────────────────────────────────────
-- Beer votes (Feature 5: upvote/downvote on Reasons/feed entries)
-- One row per (user, beer); vote ∈ {-1, +1}.
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.beer_votes (
  user_id uuid not null references public.users(id)  on delete cascade,
  beer_id uuid not null references public.beers(id)  on delete cascade,
  vote smallint not null check (vote in (-1, 1)),
  created_at timestamptz not null default now(),
  primary key (user_id, beer_id)
);

create index if not exists beer_votes_beer_idx on public.beer_votes (beer_id);

alter table public.beer_votes enable row level security;

-- ───────────────────────────────────────────────────────────────────────────
-- Follows (Feature 4: Social page — follow other users)
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.follows (
  follower_id uuid not null references public.users(id) on delete cascade,
  following_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create index if not exists follows_following_idx on public.follows (following_id);

alter table public.follows enable row level security;

-- ───────────────────────────────────────────────────────────────────────────
-- Helper view: per-beer vote score
-- ───────────────────────────────────────────────────────────────────────────
create or replace view public.v_beer_vote_scores as
select
  beer_id,
  coalesce(sum(vote), 0)::int as score,
  count(*) filter (where vote = 1)::int  as upvotes,
  count(*) filter (where vote = -1)::int as downvotes
from public.beer_votes
group by beer_id;

-- per-user total upvotes received on their beers (for profile stat)
create or replace view public.v_user_vote_totals as
select
  b.user_id,
  coalesce(sum(v.vote), 0)::int as net_score,
  count(*) filter (where v.vote = 1)::int  as total_upvotes,
  count(*) filter (where v.vote = -1)::int as total_downvotes
from public.beers b
left join public.beer_votes v on v.beer_id = b.id
group by b.user_id;
