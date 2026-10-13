-- bbt update 002: transaction types, fees, running balances, books check, own accounts.
-- Run once on an existing project: Supabase → SQL Editor → New query → paste → Run.
-- Safe to run more than once.

alter table public.transactions
  add column if not exists fee      numeric(14, 2) not null default 0,
  add column if not exists balance  numeric(14, 2),
  add column if not exists flagged  boolean not null default false;

alter table public.statements
  add column if not exists opening_balance numeric(14, 2),
  add column if not exists flagged_lines   int not null default 0;

alter table public.profiles
  add column if not exists phone            text not null default '',
  add column if not exists own_accounts     text[] not null default '{}',
  add column if not exists not_own_accounts text[] not null default '{}';
