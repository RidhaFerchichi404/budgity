-- Personal and Freelancer workspaces as a column (ADR 0006).
-- A constant default is metadata-only: no row rewrite, the change_seq trigger doesn't
-- fire and versions don't move, so ops already queued on devices don't conflict.
-- Ops without a workspace (v1.0.0 clients, ops queued before the upgrade) mean 'personal'.

alter table public.categories
  add column workspace text not null default 'personal' check (workspace in ('personal', 'freelancer')),
  add unique (id, user_id, workspace);
alter table public.transactions
  add column workspace text not null default 'personal' check (workspace in ('personal', 'freelancer'));
alter table public.budgets
  add column workspace text not null default 'personal' check (workspace in ('personal', 'freelancer'));

-- A row may only use a category from its own workspace.
alter table public.transactions
  drop constraint transactions_category_id_user_id_fkey,
  add foreign key (category_id, user_id, workspace) references public.categories (id, user_id, workspace);
alter table public.budgets
  drop constraint budgets_category_id_user_id_fkey,
  add foreign key (category_id, user_id, workspace) references public.categories (id, user_id, workspace);

alter table public.profiles add column freelancer_enabled boolean not null default false;

-- Returns null when p.category_id is absent or is uid's category in workspace ws,
-- 'invalid' when it exists elsewhere, 'blocked' when it doesn't exist yet.
create function public._sync_category_ref(uid uuid, p jsonb, ws text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  cat uuid := (p ->> 'category_id')::uuid;
begin
  if cat is null then
    return null;
  end if;
  if exists (select 1 from public.categories c where c.id = cat and c.user_id = uid and c.workspace = ws) then
    return null;
  end if;
  if exists (select 1 from public.categories c where c.id = cat) then
    return 'invalid';
  end if;
  return 'blocked';
end;
$$;

-- workspace is set on create and immutable afterwards, like category type.
create or replace function public._sync_category(uid uuid, v_id uuid, v_operation text, v_base int, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cur public.categories;
  out_row public.categories;
begin
  select * into cur from public.categories where id = v_id for update;
  if found and cur.user_id <> uid then
    return jsonb_build_object('status', 'invalid', 'error', 'not owner');
  end if;

  if v_operation = 'create' then
    if found then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    insert into public.categories (id, user_id, workspace, name, type, icon_key, sort_order, created_at)
    values (v_id, uid, coalesce(p ->> 'workspace', 'personal'), p ->> 'name', p ->> 'type',
            coalesce(p ->> 'icon_key', 'tag'), coalesce((p ->> 'sort_order')::int, 0),
            coalesce((p ->> 'created_at')::timestamptz, now()))
    returning * into out_row;
  else
    if not found then
      return jsonb_build_object('status', 'invalid', 'error', 'not found');
    end if;
    if cur.version is distinct from v_base then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    if v_operation = 'update' then
      -- type is immutable: existing transactions depend on it
      update public.categories
         set name = p ->> 'name',
             icon_key = coalesce(p ->> 'icon_key', 'tag'),
             sort_order = coalesce((p ->> 'sort_order')::int, 0),
             deleted_at = null,
             version = version + 1
       where id = v_id
      returning * into out_row;
    elsif v_operation = 'delete' then
      update public.categories
         set deleted_at = coalesce(deleted_at, now()), version = version + 1
       where id = v_id
      returning * into out_row;
    else
      return jsonb_build_object('status', 'invalid', 'error', 'unknown operation');
    end if;
  end if;

  return jsonb_build_object('status', 'applied', 'row', to_jsonb(out_row));
end;
$$;

create or replace function public._sync_transaction(uid uuid, v_id uuid, v_operation text, v_base int, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cur public.transactions;
  out_row public.transactions;
  ref text;
  ws text;
begin
  select * into cur from public.transactions where id = v_id for update;
  if found and cur.user_id <> uid then
    return jsonb_build_object('status', 'invalid', 'error', 'not owner');
  end if;
  ws := case when found then cur.workspace else coalesce(p ->> 'workspace', 'personal') end;

  if v_operation in ('create', 'update') then
    ref := public._sync_category_ref(uid, p, ws);
    if ref is not null then
      return jsonb_build_object('status', ref, 'error', 'category not available');
    end if;
  end if;

  if v_operation = 'create' then
    if found then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    insert into public.transactions (id, user_id, workspace, category_id, type, amount_minor, currency_code,
                                     description, transaction_date, created_at)
    values (v_id, uid, ws, (p ->> 'category_id')::uuid, p ->> 'type', (p ->> 'amount_minor')::bigint,
            p ->> 'currency_code', coalesce(p ->> 'description', ''), (p ->> 'transaction_date')::date,
            coalesce((p ->> 'created_at')::timestamptz, now()))
    returning * into out_row;
  else
    if not found then
      return jsonb_build_object('status', 'invalid', 'error', 'not found');
    end if;
    if cur.version is distinct from v_base then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    if v_operation = 'update' then
      update public.transactions
         set category_id = (p ->> 'category_id')::uuid,
             type = p ->> 'type',
             amount_minor = (p ->> 'amount_minor')::bigint,
             currency_code = p ->> 'currency_code',
             description = coalesce(p ->> 'description', ''),
             transaction_date = (p ->> 'transaction_date')::date,
             deleted_at = null,
             version = version + 1
       where id = v_id
      returning * into out_row;
    elsif v_operation = 'delete' then
      update public.transactions
         set deleted_at = coalesce(deleted_at, now()), version = version + 1
       where id = v_id
      returning * into out_row;
    else
      return jsonb_build_object('status', 'invalid', 'error', 'unknown operation');
    end if;
  end if;

  return jsonb_build_object('status', 'applied', 'row', to_jsonb(out_row));
end;
$$;

create or replace function public._sync_budget(uid uuid, v_id uuid, v_operation text, v_base int, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cur public.budgets;
  out_row public.budgets;
  ref text;
  ws text;
begin
  select * into cur from public.budgets where id = v_id for update;
  if found and cur.user_id <> uid then
    return jsonb_build_object('status', 'invalid', 'error', 'not owner');
  end if;
  ws := case when found then cur.workspace else coalesce(p ->> 'workspace', 'personal') end;

  if v_operation in ('create', 'update') then
    ref := public._sync_category_ref(uid, p, ws);
    if ref is not null then
      return jsonb_build_object('status', ref, 'error', 'category not available');
    end if;
  end if;

  if v_operation = 'create' then
    if found then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    insert into public.budgets (id, user_id, workspace, category_id, name, amount_minor, currency_code,
                                period_start, period_end, created_at)
    values (v_id, uid, ws, (p ->> 'category_id')::uuid, p ->> 'name', (p ->> 'amount_minor')::bigint,
            p ->> 'currency_code', (p ->> 'period_start')::date, (p ->> 'period_end')::date,
            coalesce((p ->> 'created_at')::timestamptz, now()))
    returning * into out_row;
  else
    if not found then
      return jsonb_build_object('status', 'invalid', 'error', 'not found');
    end if;
    if cur.version is distinct from v_base then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    if v_operation = 'update' then
      update public.budgets
         set category_id = (p ->> 'category_id')::uuid,
             name = p ->> 'name',
             amount_minor = (p ->> 'amount_minor')::bigint,
             currency_code = p ->> 'currency_code',
             period_start = (p ->> 'period_start')::date,
             period_end = (p ->> 'period_end')::date,
             deleted_at = null,
             version = version + 1
       where id = v_id
      returning * into out_row;
    elsif v_operation = 'delete' then
      update public.budgets
         set deleted_at = coalesce(deleted_at, now()), version = version + 1
       where id = v_id
      returning * into out_row;
    else
      return jsonb_build_object('status', 'invalid', 'error', 'unknown operation');
    end if;
  end if;

  return jsonb_build_object('status', 'applied', 'row', to_jsonb(out_row));
end;
$$;

drop function public._sync_category_ref(uuid, jsonb);

-- p_freelancer_enabled null keeps the current value, so v1.0.0 clients (two args) still work.
-- The first enable seeds Freelancer categories server-side, so two devices never seed duplicates.
drop function public.update_profile(text, text);
create function public.update_profile(p_display_name text, p_currency_code text, p_freelancer_enabled boolean default null)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  out_row public.profiles;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  perform pg_advisory_xact_lock(hashtext(uid::text));
  update public.profiles
     set display_name = p_display_name,
         currency_code = p_currency_code,
         freelancer_enabled = coalesce(p_freelancer_enabled, freelancer_enabled)
   where id = uid
  returning * into out_row;

  if out_row.freelancer_enabled
     and not exists (select 1 from public.categories where user_id = uid and workspace = 'freelancer') then
    insert into public.categories (id, user_id, workspace, name, type, icon_key, sort_order)
    values
      (gen_random_uuid(), uid, 'freelancer', 'Client work',  'income',  'salary', 0),
      (gen_random_uuid(), uid, 'freelancer', 'Other income', 'income',  'gift',   1),
      (gen_random_uuid(), uid, 'freelancer', 'Software',     'expense', 'phone',  0),
      (gen_random_uuid(), uid, 'freelancer', 'Equipment',    'expense', 'cart',   1),
      (gen_random_uuid(), uid, 'freelancer', 'Travel',       'expense', 'travel', 2),
      (gen_random_uuid(), uid, 'freelancer', 'Fees',         'expense', 'bolt',   3),
      (gen_random_uuid(), uid, 'freelancer', 'Other',        'expense', 'tag',    4);
  end if;
  return out_row;
end;
$$;

revoke execute on function
  public._sync_category_ref(uuid, jsonb, text),
  public.update_profile(text, text, boolean)
from public, anon, authenticated;
grant execute on function public.update_profile(text, text, boolean) to authenticated;
