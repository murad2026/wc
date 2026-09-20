-- Подписи под Конституцией: схема и защита от накрутки.
--
-- Таблица уже существует в проекте, но её схемы в репозитории не было —
-- воспроизвести базу с нуля было неоткуда. Этот файл закрывает и то и другое:
-- он создаёт таблицу, если её нет, и доводит существующую до нужного вида.
--
-- Запускать целиком в Supabase → SQL Editor. Повторный запуск безопасен.
--
-- ЧЕСТНО О ГРАНИЦАХ. Это останавливает скрипт в цикле — реальную угрозу для
-- проекта такого размера. Это НЕ останавливает того, кто раскидает запросы
-- по прокси. Настоящая защита — Turnstile или капча на форме, а она требует
-- Edge Function и делается отдельно. Пока счётчик нельзя подвязывать ни к
-- чему, что имеет последствия.

-- ---------------------------------------------------------------
-- Публичная таблица. Ничего, кроме того, что человек сам показал.
-- ---------------------------------------------------------------
create table if not exists public.signatures (
  id         bigint generated always as identity primary key,
  name       text not null,
  country    text,
  is_anon    boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.signatures
  add column if not exists created_at timestamptz not null default now();

create index if not exists signatures_created_idx on public.signatures (created_at desc);
create index if not exists signatures_country_idx on public.signatures (country);

-- Длина имени и страны. Отдельным блоком, потому что constraint нельзя
-- добавить через if not exists.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'signatures_name_len') then
    alter table public.signatures
      add constraint signatures_name_len
      check (char_length(btrim(name)) between 2 and 80);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'signatures_country_len') then
    alter table public.signatures
      add constraint signatures_country_len
      check (country is null or char_length(country) <= 40);
  end if;
end $$;

-- ---------------------------------------------------------------
-- Служебная схема. PostgREST отдаёт наружу только public, поэтому
-- всё, что здесь, из браузера недостижимо в принципе.
-- ---------------------------------------------------------------
create schema if not exists sec;
revoke all on schema sec from anon, authenticated;

create table if not exists sec.salt (
  k text primary key,
  v text not null
);

-- Соль генерируется один раз, при первом запуске, и в репозиторий не
-- попадает. Без неё хэш от IP перебирается по всему адресному
-- пространству за вечер — четыре миллиарда вариантов это немного.
insert into sec.salt (k, v)
values ('ip', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (k) do nothing;

-- Учёт по адресам держится отдельно от подписей. В публичной таблице
-- не появляется ни одной колонки, которой там не место.
create table if not exists sec.sig_ip (
  sig_id     bigint primary key references public.signatures(id) on delete cascade,
  ip_hash    text not null,
  name_key   text not null,
  created_at timestamptz not null default now()
);

create index if not exists sig_ip_hash_idx on sec.sig_ip (ip_hash, created_at desc);
create index if not exists sig_ip_dup_idx  on sec.sig_ip (ip_hash, name_key);

-- ---------------------------------------------------------------
-- Проверка при вставке
-- ---------------------------------------------------------------
create or replace function sec.client_ip() returns text
language sql stable as $$
  select coalesce(
    nullif(btrim(split_part(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1)), ''),
    'unknown')
$$;

create or replace function public.signatures_guard()
returns trigger
language plpgsql
security definer
set search_path = public, sec
as $$
declare
  v_salt  text;
  v_hash  text;
  v_key   text;
  v_hour  int;
  v_day   int;
  v_dup   int;
begin
  new.name := btrim(new.name);

  select v into v_salt from sec.salt where k = 'ip';
  -- sha256 встроен начиная с Postgres 11, расширение не нужно
  v_hash := encode(sha256(convert_to(sec.client_ip() || coalesce(v_salt, ''), 'utf8')), 'hex');
  v_key  := lower(new.name) || '|' || coalesce(new.country, '');

  select count(*) into v_hour from sec.sig_ip
   where ip_hash = v_hash and created_at > now() - interval '1 hour';
  if v_hour >= 3 then
    raise exception 'rate_limited_hour'
      using hint = 'Не более трёх подписей в час с одного адреса.';
  end if;

  select count(*) into v_day from sec.sig_ip
   where ip_hash = v_hash and created_at > now() - interval '1 day';
  if v_day >= 15 then
    raise exception 'rate_limited_day'
      using hint = 'Не более пятнадцати подписей в сутки с одного адреса.';
  end if;

  select count(*) into v_dup from sec.sig_ip
   where ip_hash = v_hash and name_key = v_key
     and created_at > now() - interval '30 days';
  if v_dup > 0 then
    raise exception 'already_signed'
      using hint = 'Эта подпись уже поставлена.';
  end if;

  return new;
end $$;

drop trigger if exists signatures_guard_ins on public.signatures;
create trigger signatures_guard_ins
  before insert on public.signatures
  for each row execute function public.signatures_guard();

-- Запись в учёт — уже после того, как строка получила id.
create or replace function public.signatures_note_ip()
returns trigger
language plpgsql
security definer
set search_path = public, sec
as $$
declare
  v_salt text;
begin
  select v into v_salt from sec.salt where k = 'ip';
  insert into sec.sig_ip (sig_id, ip_hash, name_key)
  values (
    new.id,
    encode(sha256(convert_to(sec.client_ip() || coalesce(v_salt, ''), 'utf8')), 'hex'),
    lower(new.name) || '|' || coalesce(new.country, '')
  )
  on conflict (sig_id) do nothing;
  return null;
end $$;

drop trigger if exists signatures_note_ip_ins on public.signatures;
create trigger signatures_note_ip_ins
  after insert on public.signatures
  for each row execute function public.signatures_note_ip();

-- ---------------------------------------------------------------
-- Права. Как и в orders: строки решает RLS, колонки решают привилегии.
-- ---------------------------------------------------------------
alter table public.signatures enable row level security;

revoke all on public.signatures from anon;
grant insert (name, country, is_anon) on public.signatures to anon;
grant select (id, name, country, is_anon, created_at) on public.signatures to anon;

do $$
begin
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'signatures'
                    and policyname = 'anyone can sign') then
    create policy "anyone can sign" on public.signatures
      for insert to anon with check (true);
  end if;
  if not exists (select 1 from pg_policies
                  where schemaname = 'public' and tablename = 'signatures'
                    and policyname = 'signatures are public') then
    create policy "signatures are public" on public.signatures
      for select to anon using (true);
  end if;
end $$;

-- Ни одной привилегии на служебную схему. Триггеры ходят туда как
-- security definer, от имени владельца, а не от имени анонима.
revoke all on all tables in schema sec from anon, authenticated;
revoke all on schema sec from anon, authenticated;

-- ---------------------------------------------------------------
-- Проверка после запуска
-- ---------------------------------------------------------------
-- select count(*) from public.signatures;
--
-- Подписаться трижды подряд с одним именем: первая пройдёт,
-- вторая вернёт already_signed.
--
-- Колонок ip_hash в публичной таблице нет и не будет — учёт живёт
-- в sec.sig_ip, которую PostgREST наружу не отдаёт.
