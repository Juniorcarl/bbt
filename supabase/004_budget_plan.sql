-- bbt update 004: the user's own monthly budget plan (income they plan with + savings goal).
-- Run once: Supabase → SQL Editor → New query → paste → Run. Safe to run again.
alter table public.profiles
  add column if not exists planned_income  numeric(14, 2),
  add column if not exists planned_savings numeric(14, 2);
