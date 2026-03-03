create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  salt text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.encrypted_contacts (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  data_blob text not null,
  signature text,
  public_key text,
  device_id text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id)
);

alter table public.profiles enable row level security;
alter table public.encrypted_contacts enable row level security;

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_insert_own on public.profiles;
drop policy if exists profiles_update_own on public.profiles;
drop policy if exists vault_select_own on public.encrypted_contacts;
drop policy if exists vault_insert_own on public.encrypted_contacts;
drop policy if exists vault_update_own on public.encrypted_contacts;
drop policy if exists vault_delete_own on public.encrypted_contacts;

create policy profiles_select_own on public.profiles
for select using (auth.uid() = id);

create policy profiles_insert_own on public.profiles
for insert with check (auth.uid() = id);

create policy profiles_update_own on public.profiles
for update using (auth.uid() = id) with check (auth.uid() = id);

create policy vault_select_own on public.encrypted_contacts
for select using (auth.uid() = user_id);

create policy vault_insert_own on public.encrypted_contacts
for insert with check (auth.uid() = user_id);

create policy vault_update_own on public.encrypted_contacts
for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy vault_delete_own on public.encrypted_contacts
for delete using (auth.uid() = user_id);
