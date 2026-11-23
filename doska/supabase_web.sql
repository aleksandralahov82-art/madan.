-- Выполнить ОДИН раз в Supabase -> SQL Editor (после supabase.sql).
-- Нужно, чтобы незарегистрированные посетители сайта видели объявления,
-- но не видели телефоны продавцов.

create or replace function public.app_user_ok(uid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select not coalesce((select is_banned from profiles where id = uid), true) $$;

drop policy if exists "ads read" on public.ads;
create policy "ads read" on public.ads for select to anon, authenticated using (
  user_id = auth.uid() or app_is_admin() or app_user_ok(user_id));

create policy "profiles read anon" on public.profiles for select to anon using (true);
revoke select on public.profiles from anon;
grant select (id, name) on public.profiles to anon;
