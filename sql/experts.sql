-- Эксперты Verified.Ninja: заявки и допуск.
-- Выполнить в Supabase → SQL Editor один раз.

create table if not exists public.experts (
  id            bigint generated always as identity primary key,

  -- выдаём мы, после принятия заявки
  code          text unique,                       -- KAGE-03, публичное кодовое имя
  access_code   text unique,                       -- EX-7K3QF9, эксперт смотрит по нему свой статус

  -- личные данные: анониму недоступны ни при каком запросе
  full_name     text not null check (char_length(full_name) between 2 and 80),
  email         text not null check (char_length(email) between 5 and 120),
  linkedin      text check (char_length(linkedin) <= 200),
  employer_note text check (char_length(employer_note) <= 400),

  -- параметры допуска
  stack         text not null check (char_length(stack) between 2 and 200),
  years         int  check (years between 0 and 60),
  interviewing  boolean not null default false,    -- вёл интервью на работе
  hired         boolean not null default false,    -- принимал решения о найме
  disclosure    text not null default 'b' check (disclosure in ('a','b','c')),
  public_role   text check (char_length(public_role) <= 120),
  public_bio    text check (char_length(public_bio) <= 600),
  agreed_rules  boolean not null default false,    -- прочитал и принял планку

  -- состояние
  status        text not null default 'applied'
                check (status in ('applied','exam','shadow','solo','paused','declined')),
  ontime_pct    numeric check (ontime_pct between 0 and 100),
  avg_hours     numeric check (avg_hours >= 0),

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists experts_access_idx on public.experts (access_code);

alter table public.experts enable row level security;

-- ---------------------------------------------------------------
-- Права. Главная защита — привилегии на колонки, а не политики строк.
-- ---------------------------------------------------------------
revoke all on public.experts from anon;

-- Анониму можно только подать заявку и только тем, что он о себе рассказывает.
-- code, access_code и status он подставить не может: их ставим мы.
grant insert (full_name, email, linkedin, employer_note, stack, years,
              interviewing, hired, disclosure, public_role, public_bio, agreed_rules)
  on public.experts to anon;

-- Читать таблицу анониму нельзя вообще. Никаких select-прав не выдаём:
-- свой статус эксперт получает через функцию ниже, которая отдаёт
-- только безличные поля.

create policy "anyone can apply" on public.experts
  for insert to anon
  with check (
    char_length(full_name) between 2 and 80
    and char_length(email) between 5 and 120
    and char_length(stack) between 2 and 200
    and agreed_rules = true
  );

-- ---------------------------------------------------------------
-- Свой статус по коду доступа.
-- security definer, потому что у anon нет прав на таблицу вовсе.
-- Возвращает только то, что эксперт и так про себя знает,
-- и ничего, что позволило бы перебором собрать чужие данные.
-- ---------------------------------------------------------------
create or replace function public.expert_by_code(p_code text)
returns table (
  code         text,
  status       text,
  stack        text,
  years        int,
  interviewing boolean,
  hired        boolean,
  disclosure   text,
  public_role  text,
  ontime_pct   numeric,
  avg_hours    numeric,
  created_at   timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select e.code, e.status, e.stack, e.years, e.interviewing, e.hired,
         e.disclosure, e.public_role, e.ontime_pct, e.avg_hours, e.created_at
  from public.experts e
  where e.access_code = p_code
  limit 1
$$;

revoke all on function public.expert_by_code(text) from public;
grant execute on function public.expert_by_code(text) to anon;

-- ---------------------------------------------------------------
-- Что делаем руками в панели после заявки:
--   1. проверяем личность и трудовую историю;
--   2. ставим code (KAGE-NN) и access_code (EX-XXXXXX), высылаем второй эксперту;
--   3. status: exam → shadow → solo. Bar Raiser можно ставить solo сразу;
--   4. ontime_pct и avg_hours обновляем после каждого сданного отчёта.
-- Ни одно из этих полей не двигается с сайта: политики update для anon нет.
-- ---------------------------------------------------------------
