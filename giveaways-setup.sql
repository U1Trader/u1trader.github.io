-- U1Trader Giveaways setup v2.
-- Run this complete script in Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.giveaway_settings (
 id integer primary key default 1 check (id=1),
 is_open boolean not null default false,
 updated_at timestamptz not null default now()
);
insert into public.giveaway_settings(id,is_open) values(1,false) on conflict(id) do nothing;
alter table public.giveaway_settings enable row level security;
drop policy if exists "Public can read giveaway state" on public.giveaway_settings;
create policy "Public can read giveaway state" on public.giveaway_settings for select to anon, authenticated using (true);
drop policy if exists "Admin manages giveaway state" on public.giveaway_settings;
create policy "Admin manages giveaway state" on public.giveaway_settings for update to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com') with check (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');

create table if not exists public.giveaway_entries (
 id uuid primary key default gen_random_uuid(),
 full_name text not null,
 email text not null,
 instagram_username text not null,
 provider text not null,
 account_size text not null,
 code_used text not null,
 invoice_path text not null,
 status text not null default 'pending' check(status in ('pending','eligible','disqualified','winner')),
 created_at timestamptz not null default now()
);
alter table public.giveaway_entries add column if not exists full_name text;
alter table public.giveaway_entries add column if not exists instagram_username text;
alter table public.giveaway_entries add column if not exists provider text;
alter table public.giveaway_entries add column if not exists account_size text;
alter table public.giveaway_entries add column if not exists code_used text;
alter table public.giveaway_entries add column if not exists invoice_path text;
alter table public.giveaway_entries alter column user_id drop not null;
alter table public.giveaway_entries alter column email drop not null;
alter table public.giveaway_entries alter column social_handle drop not null;
alter table public.giveaway_entries alter column confirmed_tasks drop not null;
alter table public.giveaway_entries alter column instagram_done drop not null;
alter table public.giveaway_entries alter column youtube_done drop not null;
alter table public.giveaway_entries alter column telegram_done drop not null;
alter table public.giveaway_entries alter column status set default 'pending';
alter table public.giveaway_entries enable row level security;
drop policy if exists "Members can view own giveaway entry" on public.giveaway_entries;
drop policy if exists "Members can submit own giveaway entry" on public.giveaway_entries;
drop policy if exists "Public submit while giveaway open" on public.giveaway_entries;
create policy "Public submit while giveaway open" on public.giveaway_entries for insert to anon, authenticated with check (
 status='pending' and length(trim(full_name)) between 2 and 120
 and length(trim(email)) between 5 and 254 and length(trim(instagram_username)) between 1 and 100
 and length(trim(provider)) between 2 and 100 and length(trim(account_size)) between 2 and 100
 and length(trim(code_used)) between 2 and 80 and invoice_path ~ '^[0-9a-fA-F-]{36}\.(jpg|png|webp|pdf)$'
 and exists(select 1 from public.giveaway_settings where id=1 and is_open=true)
);
drop policy if exists "Admin reads giveaway entries" on public.giveaway_entries;
create policy "Admin reads giveaway entries" on public.giveaway_entries for select to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');
drop policy if exists "Admin updates giveaway entries" on public.giveaway_entries;
create policy "Admin updates giveaway entries" on public.giveaway_entries for update to authenticated using (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com') with check (lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');

create unique index if not exists giveaway_entries_email_unique on public.giveaway_entries(lower(email));
create unique index if not exists giveaway_entries_instagram_unique on public.giveaway_entries(lower(instagram_username));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('giveaway-invoices','giveaway-invoices',false,8388608,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];
drop policy if exists "Public upload invoice while open" on storage.objects;
create policy "Public upload invoice while open" on storage.objects for insert to anon, authenticated with check (
 bucket_id='giveaway-invoices' and (storage.filename(name) ~ '^[0-9a-fA-F-]{36}\.(jpg|png|webp|pdf)$')
 and exists(select 1 from public.giveaway_settings where id=1 and is_open=true)
);
drop policy if exists "Admin reads invoice proofs" on storage.objects;
create policy "Admin reads invoice proofs" on storage.objects for select to authenticated using (bucket_id='giveaway-invoices' and lower(coalesce(auth.jwt()->>'email',''))='tharmesh2001@gmail.com');
drop policy if exists "Public deletes own failed invoice upload" on storage.objects;
create policy "Public deletes own failed invoice upload" on storage.objects for delete to anon, authenticated using (bucket_id='giveaway-invoices' and name ~ '^[0-9a-fA-F-]{36}\.(jpg|png|webp|pdf)$');

create or replace function public.select_giveaway_winner(entry_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if lower(coalesce(auth.jwt()->>'email','')) <> 'tharmesh2001@gmail.com' then
   raise exception 'Admin access only';
 end if;
 update public.giveaway_settings set is_open=false,updated_at=now() where id=1;
 if not exists(select 1 from public.giveaway_entries where id=entry_id and status='eligible') then
   raise exception 'Selected entry is not eligible';
 end if;
 update public.giveaway_entries set status='eligible' where status='winner';
 update public.giveaway_entries set status='winner' where id=entry_id;
end; $$;
revoke all on function public.select_giveaway_winner(uuid) from public, anon;
grant execute on function public.select_giveaway_winner(uuid) to authenticated;
