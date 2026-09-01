-- Услуги переименованы: screen/shadow → phone/live.
--
-- Выполнять ТОЛЬКО если таблица orders уже создана старой версией orders.sql.
-- Если orders.sql ещё не запускался — этот файл не нужен, запусти сразу orders.sql.
--
-- Supabase → SQL Editor → вставить целиком → Run.

-- Старые заказы, если они есть, переводятся на новые значения:
-- screen (15 минут) ближе всего к phone, shadow (60 минут) — к live.
update public.orders set service = 'phone' where service = 'screen';
update public.orders set service = 'live'  where service = 'shadow';

-- Ограничение на колонку.
alter table public.orders drop constraint if exists orders_service_check;
alter table public.orders
  add constraint orders_service_check check (service in ('phone','live'));

-- Политика вставки: то же условие дублируется в ней, поэтому пересоздаём.
drop policy if exists "anyone can order" on public.orders;

create policy "anyone can order" on public.orders
  for insert to anon
  with check (
    char_length(client_name) between 2 and 80
    and char_length(client_email) between 5 and 120
    and char_length(role_hiring) between 2 and 120
    and service in ('phone','live')
  );

-- Проверка: должно вернуть phone и live, и ничего больше.
-- select distinct service from public.orders;
