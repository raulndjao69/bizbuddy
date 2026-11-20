-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  plan text not null default 'free' check (plan in ('free','pro','business')),
  role text not null default 'user' check (role in ('user','admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.generations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  tool text not null,
  created_at timestamptz not null default now()
);
create index on public.generations (user_id, created_at);

create table public.saved_content (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  tool text not null,
  category text not null default 'General' check (length(category) < 40),
  body text not null check (length(body) < 8000),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.generations enable row level security;
alter table public.saved_content enable row level security;

-- Users can only READ their own profile and usage. Nobody can write plan, role or usage from the browser.
create policy "read own profile" on public.profiles for select using (auth.uid() = id);
create policy "read own usage" on public.generations for select using (auth.uid() = user_id);
create policy "own saved content" on public.saved_content for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Create a profile automatically when someone signs up.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Free plan: max 20 saved items (enforced in the database, not the browser).
create function public.check_saved_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select plan from public.profiles where id = new.user_id) = 'free'
     and (select count(*) from public.saved_content where user_id = new.user_id) >= 20 then
    raise exception 'Free plan allows 20 saved items. Upgrade to save more.';
  end if;
  return new;
end $$;
create trigger saved_limit before insert on public.saved_content
  for each row execute function public.check_saved_limit();

-- MANUAL ACTIVATION (while you validate the business). Run in the SQL Editor:
--   update public.profiles set plan = 'pro' where email = 'customer@example.com';
-- Make yourself admin (there is no public admin signup):
--   update public.profiles set role = 'admin' where email = 'you@example.com';
-- Deactivate an account:
--   update public.profiles set active = false where email = 'customer@example.com';
