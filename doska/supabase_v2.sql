-- Выполнить ОДИН раз в Supabase -> SQL Editor (после supabase.sql и supabase_web.sql)

-- телефон из регистрации попадает в профиль
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name, phone)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'name',''), 'Пользователь'),
          nullif(new.raw_user_meta_data->>'phone',''));
  return new;
end $$;

-- жалобы на объявления
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.ads(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 300),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
create policy "reports insert" on public.reports for insert to authenticated
  with check (reporter_id = auth.uid() and not app_is_banned());
create policy "reports read" on public.reports for select to authenticated using (app_is_admin());
create policy "reports delete" on public.reports for delete to authenticated using (app_is_admin());

-- пользователь может удалить свой аккаунт (требование Google Play)
create or replace function public.delete_me() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from auth.users where id = auth.uid();
end $$;
