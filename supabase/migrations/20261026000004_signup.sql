-- Profile and default categories are created server-side so two devices never seed duplicates.

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(left(new.raw_user_meta_data ->> 'display_name', 100), ''));

  insert into public.categories (id, user_id, name, type, icon_key, sort_order)
  values
    (gen_random_uuid(), new.id, 'Salary',        'income',  'salary',     0),
    (gen_random_uuid(), new.id, 'Other income',  'income',  'gift',       1),
    (gen_random_uuid(), new.id, 'Groceries',     'expense', 'cart',       0),
    (gen_random_uuid(), new.id, 'Rent',          'expense', 'home',       1),
    (gen_random_uuid(), new.id, 'Transport',     'expense', 'car',        2),
    (gen_random_uuid(), new.id, 'Restaurants',   'expense', 'restaurant', 3),
    (gen_random_uuid(), new.id, 'Bills',         'expense', 'bolt',       4),
    (gen_random_uuid(), new.id, 'Health',        'expense', 'health',     5),
    (gen_random_uuid(), new.id, 'Entertainment', 'expense', 'movie',      6),
    (gen_random_uuid(), new.id, 'Other',         'expense', 'tag',        7);
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
