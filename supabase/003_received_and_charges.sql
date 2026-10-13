-- bbt update 003: the bank-charges total a statement reports in its own summary.
-- Run once: Supabase → SQL Editor → New query → paste → Run. Safe to run again.
alter table public.statements
  add column if not exists stated_charges numeric(14, 2);
