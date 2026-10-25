-- U1Trader Giveaways: run this in Supabase SQL Editor before opening entries.
create table if not exists public.giveaway_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null default '',
  social_handle text not null default '',
  instagram_done boolean not null default false,
  youtube_done boolean not null default false,
  telegram_done boolean not null default false,
  confirmed_tasks boolean not null default false,
  status text not null default 'pending' check (status in ('pending','eligible','disqualified','winner')),
  created_at timestamptz not null default now(),
  unique(user_id)
);
alter table public.giveaway_entries enable row level security;
drop policy if exists "Members can view own giveaway entry" on public.giveaway_entries;
create policy "Members can view own giveaway entry" on public.giveaway_entries
for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Members can submit own giveaway entry" on public.giveaway_entries;
create policy "Members can submit own giveaway entry" on public.giveaway_entries
for insert to authenticated with check (
  auth.uid() = user_id and confirmed_tasks = true
  and instagram_done = true and youtube_done = true and telegram_done = true
);
-- Do not add public update/delete policies. Review entries and run any winner draw
-- from a trusted admin environment; never expose service-role keys in browser code.
