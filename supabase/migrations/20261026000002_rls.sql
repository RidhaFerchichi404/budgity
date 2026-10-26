-- Clients may only read their own rows. All writes go through security-definer RPCs
-- (sync_push, update_profile), so direct table writes are revoked entirely.

alter table public.profiles     enable row level security;
alter table public.categories   enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets      enable row level security;

revoke all on public.profiles, public.categories, public.transactions, public.budgets
  from anon, authenticated;
grant select on public.profiles, public.categories, public.transactions, public.budgets
  to authenticated;
revoke all on sequence public.change_seq_global from anon, authenticated;

create policy "Users read own profile" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);

create policy "Users read own categories" on public.categories
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "Users read own transactions" on public.transactions
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "Users read own budgets" on public.budgets
  for select to authenticated using ((select auth.uid()) = user_id);
