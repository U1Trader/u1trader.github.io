-- U1Trader: allow signed-in users to read and update ONLY their own profile.
-- Run this in Supabase Dashboard -> SQL Editor as project owner.

alter table public.user_profiles enable row level security;

grant select, insert, update on table public.user_profiles to authenticated;

drop policy if exists "Users can read own profile" on public.user_profiles;
create policy "Users can read own profile"
on public.user_profiles
for select
to authenticated
using (id = (select auth.uid()));

drop policy if exists "Users can insert own profile" on public.user_profiles;
create policy "Users can insert own profile"
on public.user_profiles
for insert
to authenticated
with check (id = (select auth.uid()));

drop policy if exists "Users can update own profile" on public.user_profiles;
create policy "Users can update own profile"
on public.user_profiles
for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Intentionally no DELETE policy/grant: users cannot delete profiles or edit another user's row.
