-- Write path for clients. See docs/synchronization.md.
--
-- op:     {op_id, entity_type, entity_id, operation, base_version, payload}
-- result: {op_id, status, row?, current?, error?}
--   applied   write accepted; row = server row after the write
--   duplicate op_id already applied; row = row as of that write, current = row now
--   conflict  base_version is stale (or create of an existing id); row = current server row
--   invalid   rejected permanently (validation, ownership, unknown entity)
--   blocked   referenced category does not exist yet; retry later

create table public.sync_operations (
  op_id      uuid primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  entity_type text not null,
  entity_id  uuid not null,
  result     jsonb not null,
  created_at timestamptz not null default now()
);
create index sync_operations_user_idx on public.sync_operations (user_id, created_at);

-- Reachable only through the RPC below.
alter table public.sync_operations enable row level security;
revoke all on public.sync_operations from anon, authenticated;

-- Returns null when p.category_id is absent or owned by uid, else 'invalid' / 'blocked'.
create function public._sync_category_ref(uid uuid, p jsonb)
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
  if exists (select 1 from public.categories c where c.id = cat and c.user_id = uid) then
    return null;
  end if;
  if exists (select 1 from public.categories c where c.id = cat) then
    return 'invalid';
  end if;
  return 'blocked';
end;
$$;

create function public._sync_category(uid uuid, v_id uuid, v_operation text, v_base int, p jsonb)
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

create function public._sync_transaction(uid uuid, v_id uuid, v_operation text, v_base int, p jsonb)
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

create function public._sync_budget(uid uuid, v_id uuid, v_operation text, v_base int, p jsonb)
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

create function public._sync_current_row(v_entity text, v_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case v_entity
    when 'category'    then (select to_jsonb(c) from public.categories c where c.id = v_id)
    when 'transaction' then (select to_jsonb(t) from public.transactions t where t.id = v_id)
    when 'budget'      then (select to_jsonb(b) from public.budgets b where b.id = v_id)
  end;
$$;

create function public._sync_apply_op(uid uuid, op jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_op_id uuid;
  v_entity text;
  v_id uuid;
  v_operation text;
  v_base int;
  p jsonb;
  prior public.sync_operations;
  res jsonb;
begin
  begin
    v_op_id := (op ->> 'op_id')::uuid;
    v_entity := op ->> 'entity_type';
    v_id := (op ->> 'entity_id')::uuid;
    v_operation := op ->> 'operation';
    v_base := (op ->> 'base_version')::int;
    p := coalesce(op -> 'payload', '{}'::jsonb);
  exception when others then
    return jsonb_build_object('op_id', op ->> 'op_id', 'status', 'invalid', 'error', 'malformed op');
  end;
  if v_op_id is null or v_id is null or v_entity is null or v_operation is null then
    return jsonb_build_object('op_id', op ->> 'op_id', 'status', 'invalid', 'error', 'malformed op');
  end if;

  select * into prior from public.sync_operations where op_id = v_op_id;
  if found then
    if prior.user_id <> uid or prior.entity_id <> v_id then
      return jsonb_build_object('op_id', v_op_id, 'status', 'invalid', 'error', 'op_id reused');
    end if;
    return prior.result || jsonb_build_object(
      'op_id', v_op_id, 'status', 'duplicate', 'current', public._sync_current_row(v_entity, v_id));
  end if;

  -- Subtransaction: a failing op rolls back only its own write and ledger entry.
  begin
    res := case v_entity
      when 'category'    then public._sync_category(uid, v_id, v_operation, v_base, p)
      when 'transaction' then public._sync_transaction(uid, v_id, v_operation, v_base, p)
      when 'budget'      then public._sync_budget(uid, v_id, v_operation, v_base, p)
      else jsonb_build_object('status', 'invalid', 'error', 'unknown entity_type')
    end;
    if res ->> 'status' = 'applied' then
      insert into public.sync_operations (op_id, user_id, entity_type, entity_id, result)
      values (v_op_id, uid, v_entity, v_id, res);
    end if;
  exception
    when foreign_key_violation then
      res := jsonb_build_object('status', 'blocked', 'error', sqlerrm);
    when others then
      res := jsonb_build_object('status', 'invalid', 'error', sqlerrm);
  end;

  return res || jsonb_build_object('op_id', v_op_id);
end;
$$;

create function public.sync_push(ops jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  op jsonb;
  results jsonb := '[]'::jsonb;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(ops) is distinct from 'array' or jsonb_array_length(ops) > 200 then
    raise exception 'ops must be a JSON array of at most 200 items' using errcode = '22023';
  end if;

  -- Serialize this user's writes so change_seq commits in order (ADR 0003).
  perform pg_advisory_xact_lock(hashtext(uid::text));

  for op in select value from jsonb_array_elements(ops) loop
    results := results || jsonb_build_array(public._sync_apply_op(uid, op));
  end loop;
  return results;
end;
$$;

-- Last-write-wins profile preferences.
create function public.update_profile(p_display_name text, p_currency_code text)
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
     set display_name = p_display_name, currency_code = p_currency_code
   where id = uid
  returning * into out_row;
  return out_row;
end;
$$;

revoke execute on function
  public._sync_category_ref(uuid, jsonb),
  public._sync_category(uuid, uuid, text, int, jsonb),
  public._sync_transaction(uuid, uuid, text, int, jsonb),
  public._sync_budget(uuid, uuid, text, int, jsonb),
  public._sync_current_row(text, uuid),
  public._sync_apply_op(uuid, jsonb),
  public.sync_push(jsonb),
  public.update_profile(text, text)
from public, anon, authenticated;

grant execute on function public.sync_push(jsonb), public.update_profile(text, text) to authenticated;
