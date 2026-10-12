-- bbt database schema for Supabase.
-- Run once: Supabase dashboard → SQL Editor → New query → paste all of this → Run.
-- Every table has Row Level Security: each user can only ever see and change their own rows.

-- ---------------------------------------------------------------------------
-- Profiles (one per user, created automatically on sign-up)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  created_at  timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  insert into public.events (user_id, type) values (new.id, 'signed_up');
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Uploaded statements (the file itself is never stored, only what was read)
-- ---------------------------------------------------------------------------
create table if not exists public.statements (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  file_name       text not null,
  bank            text,
  account_tail    text,
  closing_balance numeric(14, 2),
  period_start    date,
  period_end      date,
  txn_count       int not null default 0,
  uploaded_at     timestamptz not null default now()
);
create index if not exists statements_user_idx on public.statements (user_id, uploaded_at desc);

-- ---------------------------------------------------------------------------
-- Transactions
-- fingerprint = date|description|amount|n  → uploading overlapping statements
-- never creates duplicates.
-- ---------------------------------------------------------------------------
create table if not exists public.transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  statement_id  uuid references public.statements (id) on delete cascade,
  date          date not null,
  name          text not null,
  raw           text not null default '',
  amount        numeric(14, 2) not null,
  category      text not null,
  sub           text not null default '',
  source        text not null default 'rule',  -- rule | model | user | none
  confidence    real not null default 1,
  fingerprint   text not null,
  created_at    timestamptz not null default now(),
  unique (user_id, fingerprint)
);
create index if not exists transactions_user_date_idx on public.transactions (user_id, date desc);

-- ---------------------------------------------------------------------------
-- What the user taught the categoriser (the learning model is rebuilt from this)
-- ---------------------------------------------------------------------------
create table if not exists public.category_lessons (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text          text not null,
  merchant_key  text not null,
  category      text not null,
  amount        numeric(14, 2) not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists lessons_user_idx on public.category_lessons (user_id, created_at);

-- ---------------------------------------------------------------------------
-- Monthly budget limits per category
-- ---------------------------------------------------------------------------
create table if not exists public.budgets (
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category       text not null,
  monthly_limit  numeric(14, 2) not null check (monthly_limit > 0),
  updated_at     timestamptz not null default now(),
  primary key (user_id, category)
);

-- ---------------------------------------------------------------------------
-- Activity log (so you can monitor how the app is used)
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type        text not null,          -- signed_up, signed_in, statement_uploaded, ...
  detail      jsonb not null default '{}',
  created_at  timestamptz not null default now()
);
create index if not exists events_created_idx on public.events (created_at desc);

-- Trigger after events exists (the function writes to it).
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.statements        enable row level security;
alter table public.transactions      enable row level security;
alter table public.category_lessons  enable row level security;
alter table public.budgets           enable row level security;
alter table public.events            enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "own statements" on public.statements;
create policy "own statements" on public.statements
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own transactions" on public.transactions;
create policy "own transactions" on public.transactions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own lessons" on public.category_lessons;
create policy "own lessons" on public.category_lessons
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own budgets" on public.budgets;
create policy "own budgets" on public.budgets
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Users can add to their own log and read it, but not edit or delete it.
drop policy if exists "insert own events" on public.events;
create policy "insert own events" on public.events
  for insert with check (user_id = auth.uid());
drop policy if exists "read own events" on public.events;
create policy "read own events" on public.events
  for select using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Handy view for you (dashboard → SQL editor: select * from admin_overview;)
-- Not exposed to the app: only readable with the dashboard / service role.
-- ---------------------------------------------------------------------------
create or replace view public.admin_overview with (security_invoker = true) as
select
  u.email,
  p.full_name,
  u.created_at                                    as signed_up,
  u.last_sign_in_at,
  (select count(*) from public.statements s where s.user_id = u.id)        as statements,
  (select count(*) from public.transactions t where t.user_id = u.id)      as transactions,
  (select count(*) from public.category_lessons l where l.user_id = u.id)  as corrections
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at desc;
revoke all on public.admin_overview from anon, authenticated;
