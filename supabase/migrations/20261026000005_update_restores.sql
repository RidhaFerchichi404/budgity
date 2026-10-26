-- An update op only ever comes from a live local row, so applying one restores a
-- soft-deleted record. Without this, "keep this device" on an edit-vs-delete conflict
-- would apply the edit to a row that stays deleted (silent loss, spec section 6).
-- create or replace keeps the grants/revokes from 20261026000003.

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
    insert into public.categories (id, user_id, name, type, icon_key, sort_order, created_at)
    values (v_id, uid, p ->> 'name', p ->> 'type', coalesce(p ->> 'icon_key', 'tag'),
            coalesce((p ->> 'sort_order')::int, 0), coalesce((p ->> 'created_at')::timestamptz, now()))
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
begin
  select * into cur from public.transactions where id = v_id for update;
  if found and cur.user_id <> uid then
    return jsonb_build_object('status', 'invalid', 'error', 'not owner');
  end if;

  if v_operation in ('create', 'update') then
    ref := public._sync_category_ref(uid, p);
    if ref is not null then
      return jsonb_build_object('status', ref, 'error', 'category not available');
    end if;
  end if;

  if v_operation = 'create' then
    if found then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    insert into public.transactions (id, user_id, category_id, type, amount_minor, currency_code,
                                     description, transaction_date, created_at)
    values (v_id, uid, (p ->> 'category_id')::uuid, p ->> 'type', (p ->> 'amount_minor')::bigint,
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
begin
  select * into cur from public.budgets where id = v_id for update;
  if found and cur.user_id <> uid then
    return jsonb_build_object('status', 'invalid', 'error', 'not owner');
  end if;

  if v_operation in ('create', 'update') then
    ref := public._sync_category_ref(uid, p);
    if ref is not null then
      return jsonb_build_object('status', ref, 'error', 'category not available');
    end if;
  end if;

  if v_operation = 'create' then
    if found then
      return jsonb_build_object('status', 'conflict', 'row', to_jsonb(cur));
    end if;
    insert into public.budgets (id, user_id, category_id, name, amount_minor, currency_code,
                                period_start, period_end, created_at)
    values (v_id, uid, (p ->> 'category_id')::uuid, p ->> 'name', (p ->> 'amount_minor')::bigint,
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
