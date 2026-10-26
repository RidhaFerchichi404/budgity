begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

insert into auth.users (id, instance_id, aud, role, email)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@test.dev'),
  ('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@test.dev');

-- ---------- user A ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is((select count(*)::int from public.categories), 10, 'signup seeds default categories');
select is((select count(*)::int from public.profiles), 1, 'signup creates profile');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000c1","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"name":"Books","type":"expense","icon_key":"book"}}]') -> 0 ->> 'status',
  'applied', 'create category applied');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000c1","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"name":"Books","type":"expense","icon_key":"book"}}]') -> 0 ->> 'status',
  'duplicate', 'replayed op is a duplicate');
select is((select count(*)::int from public.categories where id = 'cccccccc-0000-0000-0000-000000000001'), 1, 'replay created no second row');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000c2","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"update","base_version":1,"payload":{"name":"Books & media","type":"expense","icon_key":"book"}}]') -> 0 -> 'row' ->> 'version',
  '2', 'update with current base_version bumps version');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000c3","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"update","base_version":1,"payload":{"name":"Stale","type":"expense"}}]') -> 0 ->> 'status',
  'conflict', 'stale base_version is a conflict');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000c4","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"update","base_version":null,"payload":{"name":"No base","type":"expense"}}]') -> 0 ->> 'status',
  'conflict', 'missing base_version on update is a conflict');

-- one invalid op must not roll back the others
select is(
  (select jsonb_agg(r ->> 'status') from jsonb_array_elements(public.sync_push('[
    {"op_id":"00000000-0000-0000-0000-0000000000f1","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"type":"expense","amount_minor":-5,"currency_code":"TND","transaction_date":"2026-10-01"}},
    {"op_id":"00000000-0000-0000-0000-0000000000f2","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000002","operation":"create","base_version":null,"payload":{"category_id":"cccccccc-0000-0000-0000-000000000001","type":"expense","amount_minor":12500,"currency_code":"TND","description":"Novel","transaction_date":"2026-10-01"}}
  ]')) r),
  '["invalid","applied"]'::jsonb, 'batch isolates the invalid op');
select is((select count(*)::int from public.transactions), 1, 'only the valid transaction exists');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000f3","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000003","operation":"create","base_version":null,"payload":{"category_id":"cccccccc-0000-0000-0000-00000000ffff","type":"expense","amount_minor":100,"currency_code":"TND","transaction_date":"2026-10-01"}}]') -> 0 ->> 'status',
  'blocked', 'missing category is blocked, not invalid');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000f4","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000002","operation":"delete","base_version":1,"payload":{}}]') -> 0 ->> 'status',
  'applied', 'soft delete applied');
select isnt((select deleted_at from public.transactions where id = 'dddddddd-0000-0000-0000-000000000002'), null, 'tombstone is readable');

select ok(
  (select change_seq from public.transactions where id = 'dddddddd-0000-0000-0000-000000000002')
    > (select change_seq from public.categories where id = 'cccccccc-0000-0000-0000-000000000001'),
  'later write gets a higher change_seq');

-- "keep this device" after an edit-vs-delete conflict: the update restores the row
select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000f5","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000002","operation":"update","base_version":2,"payload":{"category_id":"cccccccc-0000-0000-0000-000000000001","type":"expense","amount_minor":13000,"currency_code":"TND","transaction_date":"2026-10-01"}}]') -> 0 ->> 'status',
  'applied', 'update on a tombstone with current version applies');
select is((select deleted_at from public.transactions where id = 'dddddddd-0000-0000-0000-000000000002'), null, 'update restores a soft-deleted row');

select throws_ok(
  $$insert into public.transactions (id, user_id, type, amount_minor, currency_code, transaction_date)
    values (gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', 'expense', 1, 'TND', '2026-10-01')$$,
  '42501', null, 'direct table insert is denied');

-- ---------- user B ----------
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);

select is((select count(*)::int from public.categories where id = 'cccccccc-0000-0000-0000-000000000001'), 0, 'B cannot read A''s category');
select is((select count(*)::int from public.transactions), 0, 'B cannot read A''s transactions');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000b1","entity_type":"transaction","entity_id":"eeeeeeee-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"category_id":"cccccccc-0000-0000-0000-000000000001","type":"expense","amount_minor":100,"currency_code":"TND","transaction_date":"2026-10-01"}}]') -> 0 ->> 'status',
  'invalid', 'B cannot reference A''s category');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000b2","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"update","base_version":2,"payload":{"name":"Hijack","type":"expense"}}]') -> 0 ->> 'status',
  'invalid', 'B cannot update A''s category');

-- ---------- anon ----------
reset role;
set local role anon;
select throws_ok($$select public.sync_push('[]')$$, '42501', null, 'anon cannot call sync_push');

select * from finish();
rollback;
