-- Заказы Verified.Ninja.
-- Выполнить в Supabase → SQL Editor один раз.

create table if not exists public.orders (
  id          bigint generated always as identity primary key,
  ref         text not null unique,                       -- VN-7K3QF9, показывается клиенту
  service     text not null check (service in ('phone','live')),
  client_name text not null check (char_length(client_name) between 2 and 80),
  client_email text not null check (char_length(client_email) between 5 and 120),
  company     text check (char_length(company) <= 80),
  role_hiring text not null check (char_length(role_hiring) between 2 and 120),
  concern     text check (char_length(concern) <= 800),   -- в чём именно сомневается клиент
  stage       text not null default 'received'
              check (stage in ('received','payment_sent','paid','scheduled','call_done','delivered','cancelled')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists orders_ref_idx on public.orders (ref);

alter table public.orders enable row level security;

-- ---------------------------------------------------------------
-- Права на колонки. Это главная защита, а не RLS.
-- RLS решает «какие строки», привилегии решают «какие колонки».
-- Без этого блока любой мог бы выгрузить почты всех клиентов
-- одним запросом ?select=* — политика чтения его не остановит.
-- ---------------------------------------------------------------
revoke all on public.orders from anon;

-- Анониму можно записать только то, что он и так о себе сообщает.
-- id, ref, stage, created_at он подставить не может: ref генерирует сайт,
-- stage и время ставит база значениями по умолчанию.
grant insert (ref, service, client_name, client_email, company, role_hiring, concern)
  on public.orders to anon;

-- Читать анониму можно только безличные поля. client_email, client_name,
-- company и concern не читаются НИКОГДА и никем, кроме service_role.
grant select (ref, service, stage, created_at) on public.orders to anon;

-- ---------------------------------------------------------------
-- Политики строк
-- ---------------------------------------------------------------

-- Оформить заказ может кто угодно.
create policy "anyone can order" on public.orders
  for insert to anon
  with check (
    char_length(client_name) between 2 and 80
    and char_length(client_email) between 5 and 120
    and char_length(role_hiring) between 2 and 120
    and service in ('phone','live')
  );

-- Чтение открыто по строкам, но ограничено колонками выше.
-- Номер заказа случайный (8 символов), он и служит ключом к своей строке.
create policy "status is public by ref" on public.orders
  for select to anon
  using (true);

-- Обновление стадии — только вручную из панели Supabase (service_role).
-- Политики update для anon нет намеренно: клиент не двигает свой заказ сам.
