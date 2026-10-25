-- U1Trader Giveaways v3: multiple Running / Completed giveaways.
-- Run the entire script in Supabase SQL Editor. Safe to re-run.
create extension if not exists pgcrypto;

create table if not exists public.giveaway_campaigns (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 prize_details text not null default '',
 status text not null default 'running' check(status in ('running','completed')),
 created_at timestamptz not null default now(),
 completed_at timestamptz,
 winner_entry_id uuid
);
alter table public.giveaway_campaigns enable row level security;
drop policy if exists "Public can read running giveaways" on public.giveaway_campaigns;
drop policy if exists "Public can read giveaways" on public.giveaway_campaigns;
create policy "Public can read giveaways" on public.giveaway_campaigns for select to anon,authenticated using (true);
drop policy if exists "Admin creates giveaways" on public.giveaway_campaigns;
create policy "Admin creates giveaways" on public.giveaway_campaigns for insert to authenticated with check (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');
drop policy if exists "Admin updates giveaways" on public.giveaway_campaigns;
create policy "Admin updates giveaways" on public.giveaway_campaigns for update to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com') with check (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');

create table if not exists public.giveaway_entries (
 id uuid primary key default gen_random_uuid(),
 giveaway_id uuid references public.giveaway_campaigns(id) on delete cascade,
 full_name text not null,
 email text not null,
 instagram_username text not null,
 provider text not null,
 account_size text not null,
 code_used text,
 invoice_path text not null,
 status text not null default 'pending' check(status in ('pending','eligible','disqualified','winner')),
 created_at timestamptz not null default now()
);
alter table public.giveaway_entries add column if not exists giveaway_id uuid references public.giveaway_campaigns(id) on delete cascade;
alter table public.giveaway_entries add column if not exists full_name text;
alter table public.giveaway_entries add column if not exists instagram_username text;
alter table public.giveaway_entries add column if not exists provider text;
alter table public.giveaway_entries add column if not exists account_size text;
alter table public.giveaway_entries add column if not exists code_used text;
alter table public.giveaway_entries alter column code_used drop not null;
alter table public.giveaway_entries add column if not exists invoice_path text;
alter table public.giveaway_entries enable row level security;
drop policy if exists "Members can view own giveaway entry" on public.giveaway_entries;
drop policy if exists "Members can submit own giveaway entry" on public.giveaway_entries;
drop policy if exists "Public submit while giveaway open" on public.giveaway_entries;
drop policy if exists "Admin reads giveaway entries" on public.giveaway_entries;
drop policy if exists "Admin updates giveaway entries" on public.giveaway_entries;
create policy "Public submit while giveaway running" on public.giveaway_entries for insert to anon,authenticated with check (
 status='pending' and giveaway_id is not null
 and length(trim(full_name)) between 2 and 120
 and length(trim(email)) between 5 and 254 and length(trim(instagram_username)) between 1 and 100
 and length(trim(provider)) between 2 and 100 and length(trim(account_size)) between 2 and 100

 and invoice_path ~ '^[0-9a-fA-F-]{36}\.(jpg|png|webp|pdf)$'
 and exists(select 1 from public.giveaway_campaigns c where c.id=giveaway_id and c.status='running')
);
create policy "Admin reads giveaway entries" on public.giveaway_entries for select to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');
create policy "Admin updates giveaway entries" on public.giveaway_entries for update to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com') with check (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');
drop index if exists public.giveaway_entries_email_unique;
drop index if exists public.giveaway_entries_instagram_unique;
create unique index if not exists giveaway_entries_campaign_email_unique on public.giveaway_entries(giveaway_id,lower(email)) where giveaway_id is not null and email is not null;
create unique index if not exists giveaway_entries_campaign_instagram_unique on public.giveaway_entries(giveaway_id,lower(instagram_username)) where giveaway_id is not null and instagram_username is not null;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('giveaway-invoices','giveaway-invoices',false,8388608,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];
drop policy if exists "Public upload invoice while open" on storage.objects;
drop policy if exists "Public upload invoice while running" on storage.objects;
create policy "Public upload invoice while running" on storage.objects for insert to anon,authenticated with check (
 bucket_id='giveaway-invoices' and (storage.filename(name) ~ '^[0-9a-fA-F-]{36}\.(jpg|png|webp|pdf)$')
 and exists(select 1 from public.giveaway_campaigns where status='running')
);
drop policy if exists "Admin reads invoice proofs" on storage.objects;
create policy "Admin reads invoice proofs" on storage.objects for select to authenticated using (bucket_id='giveaway-invoices' and lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');

-- Public-safe winner records and multi-winner draw support
create table if not exists public.giveaway_winners (
 id uuid primary key default gen_random_uuid(),
 giveaway_id uuid not null references public.giveaway_campaigns(id) on delete cascade,
 entry_id uuid not null references public.giveaway_entries(id) on delete cascade,
 full_name text not null,
 instagram_username text not null,
 selected_at timestamptz not null default now(),
 unique(giveaway_id, entry_id)
);
alter table public.giveaway_winners enable row level security;
drop policy if exists "Public can view giveaway winners" on public.giveaway_winners;
create policy "Public can view giveaway winners" on public.giveaway_winners for select to anon, authenticated using (true);
grant select on public.giveaway_winners to anon, authenticated;

create or replace function public.select_giveaway_winners(p_giveaway_id uuid, p_winner_count integer)
returns jsonb language plpgsql security definer set search_path=public as $
declare
 chosen record;
 chosen_count integer := 0;
 winner_list jsonb := '[]'::jsonb;
begin
 if lower(coalesce(auth.jwt()->>'email','')) <> 'tharmesh2001@gmail.com' then raise exception 'Admin access only'; end if;
 if p_winner_count is null or p_winner_count < 1 or p_winner_count > 20 then raise exception 'Choose between 1 and 20 winners'; end if;
 if not exists(select 1 from public.giveaway_campaigns where id=p_giveaway_id and status='running') then raise exception 'Giveaway is not running'; end if;
 if (select count(*) from public.giveaway_entries where giveaway_id=p_giveaway_id and status='eligible') < p_winner_count then raise exception 'Not enough eligible entries for the number of winners requested'; end if;
 for chosen in
   select id, full_name, instagram_username
   from public.giveaway_entries
   where giveaway_id=p_giveaway_id and status='eligible'
   order by gen_random_uuid()
   limit p_winner_count
 loop
   update public.giveaway_entries set status='winner' where id=chosen.id;
   insert into public.giveaway_winners(giveaway_id,entry_id,full_name,instagram_username)
   values(p_giveaway_id,chosen.id,chosen.full_name,chosen.instagram_username)
   on conflict(giveaway_id,entry_id) do nothing;
   winner_list := winner_list || jsonb_build_array(jsonb_build_object('full_name',chosen.full_name,'instagram_username',chosen.instagram_username));
   chosen_count := chosen_count + 1;
 end loop;
 if chosen_count <> p_winner_count then raise exception 'Could not select the requested number of winners'; end if;
 update public.giveaway_campaigns
 set status='completed',completed_at=now(),winner_entry_id=(select entry_id from public.giveaway_winners where giveaway_id=p_giveaway_id order by selected_at,id limit 1)
 where id=p_giveaway_id and status='running';
 return winner_list;
end; $;
revoke all on function public.select_giveaway_winners(uuid,integer) from public, anon;
grant execute on function public.select_giveaway_winners(uuid,integer) to authenticated;

-- Admin can reopen a completed giveaway and clear its previous draw so it can run again.
create or replace function public.reopen_giveaway(p_giveaway_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $
begin
 if lower(coalesce(auth.jwt()->>'email','')) <> 'tharmesh2001@gmail.com' then
   raise exception 'Admin access only';
 end if;
 if not exists(select 1 from public.giveaway_campaigns where id=p_giveaway_id and status='completed') then
   raise exception 'Only a completed giveaway can be reopened';
 end if;

 update public.giveaway_entries
 set status='eligible'
 where giveaway_id=p_giveaway_id and status='winner';

 delete from public.giveaway_winners
 where giveaway_id=p_giveaway_id;

 update public.giveaway_campaigns
 set status='running', completed_at=null, winner_entry_id=null
 where id=p_giveaway_id and status='completed';
end;
$;
revoke all on function public.reopen_giveaway(uuid) from public, anon;
grant execute on function public.reopen_giveaway(uuid) to authenticated;

create or replace function public.select_giveaway_winner(p_giveaway_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare chosen_id uuid;
begin
 if lower(coalesce(auth.jwt()->>'email','')) <> 'tharmesh2001@gmail.com' then raise exception 'Admin access only'; end if;
 update public.giveaway_campaigns set status='completed',completed_at=now() where id=p_giveaway_id and status='running';
 if not found then raise exception 'Giveaway is not running'; end if;
 select id into chosen_id from public.giveaway_entries where giveaway_entries.giveaway_id=p_giveaway_id and status='eligible' order by gen_random_uuid() limit 1;
 if chosen_id is null then
   update public.giveaway_campaigns set status='running',completed_at=null where id=p_giveaway_id;
   raise exception 'No eligible entries. Verify invoices and mark at least one entry eligible before drawing.';
 end if;
 update public.giveaway_entries set status='winner' where id=chosen_id;
 update public.giveaway_campaigns set winner_entry_id=chosen_id where id=p_giveaway_id;
 return chosen_id;
end; $$;
revoke all on function public.select_giveaway_winner(uuid) from public,anon;
grant execute on function public.select_giveaway_winner(uuid) to authenticated;

-- New giveaways are created from giveaways-admin.html. They have no fixed end date.
