-- bbt update 005: security hardening.
-- Run once: Supabase → SQL Editor → New query → paste → Run. Safe to run again.
--
-- 1. Masks account and card numbers already saved (the app now masks them
--    before saving; this cleans up what was saved before).
-- 2. Rules apply only to signed-in users; signed-out visitors get nothing.
-- 3. Size limits so nobody can stuff huge values into the database.

-- ---------------------------------------------------------------------------
-- 1. Mask numbers in stored text (same rules as lib/data/privacy.dart)
-- ---------------------------------------------------------------------------
create or replace function pg_temp.bbt_mask(t text) returns text
language sql immutable as $$
  select regexp_replace(
           regexp_replace(
             regexp_replace(t, '(?<![0-9])267([0-9]{8})(?![0-9])', '\1', 'g'),
             '(?<![0-9])[0-9]{4,}[xX*#]+([0-9]{2,4})(?![0-9])', '••••\1', 'g'),
           '(?<![0-9])[0-9]{5,}([0-9]{4})(?![0-9])', '••••\1', 'g')
$$;

update public.transactions
   set raw = pg_temp.bbt_mask(raw),
       fingerprint = pg_temp.bbt_mask(fingerprint)
 where raw ~ '[0-9]{9,}|[0-9]{4,}[xX*#]+[0-9]{2,}'
    or fingerprint ~ '[0-9]{9,}|[0-9]{4,}[xX*#]+[0-9]{2,}';

update public.category_lessons
   set text = pg_temp.bbt_mask(text)
 where text ~ '[0-9]{9,}|[0-9]{4,}[xX*#]+[0-9]{2,}';

-- ---------------------------------------------------------------------------
-- 2. Signed-out visitors (the "anon" role) can't touch any table.
--    Signed-in users still only see their own rows (Row Level Security).
-- ---------------------------------------------------------------------------
revoke all on public.profiles, public.statements, public.transactions,
              public.category_lessons, public.budgets, public.events from anon;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "own statements" on public.statements;
create policy "own statements" on public.statements to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own transactions" on public.transactions;
create policy "own transactions" on public.transactions to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own lessons" on public.category_lessons;
create policy "own lessons" on public.category_lessons to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own budgets" on public.budgets;
create policy "own budgets" on public.budgets to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "insert own events" on public.events;
create policy "insert own events" on public.events for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "read own events" on public.events;
create policy "read own events" on public.events for select to authenticated
  using (user_id = (select auth.uid()));

-- The sign-up trigger function must never be callable from the app.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Size limits (generous for real statements, stops abuse)
-- ---------------------------------------------------------------------------
alter table public.transactions drop constraint if exists transactions_sizes;
alter table public.transactions add constraint transactions_sizes check (
  char_length(raw) <= 500 and char_length(name) <= 200 and char_length(fingerprint) <= 700
  and abs(amount) < 1000000000) not valid;

alter table public.category_lessons drop constraint if exists lessons_sizes;
alter table public.category_lessons add constraint lessons_sizes check (
  char_length(text) <= 500 and char_length(merchant_key) <= 200) not valid;

alter table public.profiles drop constraint if exists profiles_sizes;
alter table public.profiles add constraint profiles_sizes check (
  char_length(full_name) <= 120 and char_length(phone) <= 20
  and cardinality(own_accounts) <= 100 and cardinality(not_own_accounts) <= 100) not valid;

alter table public.statements drop constraint if exists statements_sizes;
alter table public.statements add constraint statements_sizes check (
  char_length(file_name) <= 255) not valid;

alter table public.events drop constraint if exists events_sizes;
alter table public.events add constraint events_sizes check (
  char_length(type) <= 50 and pg_column_size(detail) <= 2000) not valid;
