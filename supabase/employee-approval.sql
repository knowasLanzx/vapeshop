-- Run this migration in the Supabase SQL Editor.
-- New signups stay pending until an owner approves them in Staff.

alter table public.profiles add column if not exists email text;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('owner', 'employee', 'pending'));
alter table public.profiles alter column role set default 'pending';

create or replace function public.is_profile_owner()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'owner'
  );
$$;

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'New staff'),
    'pending'
  )
  on conflict (id) do update set
    email = excluded.email,
    display_name = coalesce(public.profiles.display_name, excluded.display_name);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_user_profile();

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon;
grant select, insert, update, delete on table public.profiles to authenticated;

drop policy if exists "Users can read their own profile" on public.profiles;
drop policy if exists "Users can create their own pending profile" on public.profiles;
drop policy if exists "Owners can manage profiles" on public.profiles;
drop policy if exists "Owners can remove profiles" on public.profiles;
create policy "Users can read their own profile"
  on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_profile_owner());

create policy "Users can create their own pending profile"
  on public.profiles for insert to authenticated
  with check (id = auth.uid() and role = 'pending');

create policy "Owners can manage profiles"
  on public.profiles for update to authenticated
  using (public.is_profile_owner())
  with check (public.is_profile_owner());

create policy "Owners can remove profiles"
  on public.profiles for delete to authenticated
  using (public.is_profile_owner());

grant select, insert on table public.sales to authenticated;

drop policy if exists "Staff can view sales" on public.sales;
drop policy if exists "Employees can create their own sales" on public.sales;

create policy "Staff can view sales"
  on public.sales for select to authenticated
  using (public.is_profile_owner() or employee_id = auth.uid());

create policy "Employees can create their own sales"
  on public.sales for insert to authenticated
  with check (
    employee_id = auth.uid()
    and exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'employee'
    )
  );
