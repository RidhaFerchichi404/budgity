begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, instance_id, aud, role, email)
values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);

select is((select count(*)::int from public.categories where workspace = 'personal'), 10, 'signup categories are personal');

-- v1.0.0 op: no workspace in the payload
select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a1","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"name":"Books","type":"expense"}}]') -> 0 -> 'row' ->> 'workspace',
  'personal', 'op without workspace is personal');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a2","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000002","operation":"create","base_version":null,"payload":{"workspace":"freelancer","name":"Software","type":"expense"}}]') -> 0 -> 'row' ->> 'workspace',
  'freelancer', 'freelancer category created');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a3","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"workspace":"freelancer","category_id":"cccccccc-0000-0000-0000-000000000002","type":"expense","amount_minor":100,"currency_code":"TND","transaction_date":"2026-10-01"}}]') -> 0 ->> 'status',
  'applied', 'freelancer transaction may use a freelancer category');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a4","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000002","operation":"create","base_version":null,"payload":{"category_id":"cccccccc-0000-0000-0000-000000000002","type":"expense","amount_minor":100,"currency_code":"TND","transaction_date":"2026-10-01"}}]') -> 0 ->> 'status',
  'invalid', 'personal transaction cannot use a freelancer category');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a5","entity_type":"budget","entity_id":"bbbbbbbb-0000-0000-0000-000000000001","operation":"create","base_version":null,"payload":{"workspace":"freelancer","category_id":"cccccccc-0000-0000-0000-000000000001","name":"Books","amount_minor":100,"currency_code":"TND","period_start":"2026-10-01","period_end":"2026-10-31"}}]') -> 0 ->> 'status',
  'invalid', 'freelancer budget cannot use a personal category');

-- workspace is immutable: an update without it (or with another one) keeps the row's
select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a6","entity_type":"transaction","entity_id":"dddddddd-0000-0000-0000-000000000001","operation":"update","base_version":1,"payload":{"workspace":"personal","category_id":"cccccccc-0000-0000-0000-000000000002","type":"expense","amount_minor":200,"currency_code":"TND","transaction_date":"2026-10-01"}}]') -> 0 -> 'row' ->> 'workspace',
  'freelancer', 'update cannot move a row to another workspace');

select is(
  public.sync_push('[{"op_id":"00000000-0000-0000-0000-0000000000a7","entity_type":"category","entity_id":"cccccccc-0000-0000-0000-000000000003","operation":"create","base_version":null,"payload":{"workspace":"business","name":"X","type":"expense"}}]') -> 0 ->> 'status',
  'invalid', 'unknown workspace is rejected');

-- profiles: v1.0.0 two-argument call still works and leaves freelancer off
select is((public.update_profile('Ridha', 'TND')).freelancer_enabled, false, 'two-arg update_profile keeps freelancer off');
select is((select count(*)::int from public.categories where workspace = 'freelancer'), 1, 'no seeding while disabled');

select is((public.update_profile('Ridha', 'TND', true)).freelancer_enabled, true, 'freelancer enabled');
select is((select count(*)::int from public.categories where workspace = 'freelancer'), 1,
  'enabling with freelancer categories already present seeds nothing');
select is((public.update_profile('Ridha', 'TND')).freelancer_enabled, true, 'null flag keeps the current value');

-- a fresh account gets the Freelancer defaults once
reset role;
insert into auth.users (id, instance_id, aud, role, email)
values ('bbbbbbbb-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'b@test.dev');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
select update_profile('', 'TND', true);
select is((select count(*)::int from public.categories where workspace = 'freelancer'), 7, 'first enable seeds freelancer categories');
select update_profile('', 'TND', false);
select update_profile('', 'TND', true);
select is((select count(*)::int from public.categories where workspace = 'freelancer'), 7, 're-enabling does not seed twice');

select * from finish();
rollback;
