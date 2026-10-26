-- Core finance schema. Every synced table carries version (optimistic concurrency)
-- and change_seq (server-assigned pull cursor, see docs/decisions/0003).

create sequence public.change_seq_global;

create function public.bump_change_seq()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.change_seq := nextval('public.change_seq_global');
  new.updated_at := now();
  return new;
end;
$$;

create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default '' check (char_length(display_name) <= 100),
  currency_code text not null default 'TND' check (currency_code ~ '^[A-Z]{3}$'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  change_seq    bigint not null default 0
);

create table public.categories (
  id          uuid primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 50),
  type        text not null check (type in ('income', 'expense')),
  icon_key    text not null default 'tag' check (char_length(icon_key) between 1 and 40),
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  version     int    not null default 1,
  change_seq  bigint not null default 0,
  -- target for composite FKs so references can never cross users
  unique (id, user_id)
);

create table public.transactions (
  id               uuid primary key,
  user_id          uuid not null references auth.users (id) on delete cascade,
  category_id      uuid,
  type             text   not null check (type in ('income', 'expense')),
  amount_minor     bigint not null check (amount_minor > 0),
  currency_code    text   not null check (currency_code ~ '^[A-Z]{3}$'),
  description      text   not null default '' check (char_length(description) <= 500),
  transaction_date date   not null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  version          int    not null default 1,
  change_seq       bigint not null default 0,
  foreign key (category_id, user_id) references public.categories (id, user_id)
);

create table public.budgets (
  id            uuid primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  category_id   uuid,
  name          text   not null check (char_length(name) between 1 and 50),
  amount_minor  bigint not null check (amount_minor > 0),
  currency_code text   not null check (currency_code ~ '^[A-Z]{3}$'),
  period_start  date   not null,
  period_end    date   not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  version       int    not null default 1,
  change_seq    bigint not null default 0,
  check (period_end >= period_start),
  foreign key (category_id, user_id) references public.categories (id, user_id)
);

create index profiles_change_seq_idx on public.profiles (change_seq);
create index categories_user_seq_idx on public.categories (user_id, change_seq);
create index transactions_user_seq_idx on public.transactions (user_id, change_seq);
create index transactions_user_date_idx on public.transactions (user_id, transaction_date);
create index transactions_category_idx on public.transactions (category_id, user_id);
create index budgets_user_seq_idx on public.budgets (user_id, change_seq);
create index budgets_category_idx on public.budgets (category_id, user_id);

create trigger profiles_change_seq before insert or update on public.profiles
  for each row execute function public.bump_change_seq();
create trigger categories_change_seq before insert or update on public.categories
  for each row execute function public.bump_change_seq();
create trigger transactions_change_seq before insert or update on public.transactions
  for each row execute function public.bump_change_seq();
create trigger budgets_change_seq before insert or update on public.budgets
  for each row execute function public.bump_change_seq();

revoke execute on function public.bump_change_seq() from public, anon, authenticated;
