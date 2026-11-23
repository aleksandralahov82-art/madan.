-- Вставьте целиком в Supabase -> SQL Editor -> Run

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null default 'Пользователь',
  phone text,
  role text not null default 'user' check (role in ('user','admin')),
  is_banned boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.ads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 80),
  description text not null default '',
  price numeric not null default 0 check (price >= 0),
  category text not null,
  city text not null,
  image_url text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.ads enable row level security;

-- профиль создаётся автоматически при регистрации
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'name',''), 'Пользователь'));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create function public.app_is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select role = 'admin' from profiles where id = auth.uid()), false) $$;

create function public.app_is_banned() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_banned from profiles where id = auth.uid()), false) $$;

-- бан/разбан: только админ, админов банить нельзя
create function public.set_ban(target uuid, banned boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not app_is_admin() then raise exception 'forbidden'; end if;
  update profiles set is_banned = banned where id = target and role <> 'admin';
end $$;

-- profiles: читают все вошедшие, менять можно только свои name и phone
create policy "profiles read" on public.profiles for select to authenticated using (true);
create policy "profiles update own" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (name, phone) on public.profiles to authenticated;

-- ads: объявления забаненных скрыты от всех, кроме админа и их автора
create policy "ads read" on public.ads for select to authenticated using (
  user_id = auth.uid() or app_is_admin()
  or exists (select 1 from profiles p where p.id = ads.user_id and not p.is_banned));
create policy "ads insert" on public.ads for insert to authenticated
  with check (user_id = auth.uid() and not app_is_banned());
create policy "ads update" on public.ads for update to authenticated
  using ((user_id = auth.uid() and not app_is_banned()) or app_is_admin());
create policy "ads delete" on public.ads for delete to authenticated
  using (user_id = auth.uid() or app_is_admin());

-- хранилище фото
insert into storage.buckets (id, name, public) values ('ads', 'ads', true) on conflict do nothing;
create policy "ads img read" on storage.objects for select using (bucket_id = 'ads');
create policy "ads img upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'ads' and (storage.foldername(name))[1] = auth.uid()::text and not app_is_banned());

-- ====== СДЕЛАТЬ СЕБЯ АДМИНОМ (после регистрации в приложении) ======
-- update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'ВАШ_EMAIL');
