# Запуск сайта: пошаговая инструкция

> Боевая версия лежит в `docs/index.html`. Ниже — 3 блока: база подписей (Supabase), публикация (GitHub Pages), домен (DNS). Всё бесплатно, кроме уже купленного домена. Суммарно ~20 минут.

---

## Блок 1 — База подписей (Supabase, ~7 минут)

1. Зайди на [supabase.com](https://supabase.com) → **New project**.
   - Name: `worldconstitution`
   - Database password: сгенерируй и сохрани (нигде больше не понадобится)
   - Region: `Central EU (Frankfurt)`
2. Когда проект создастся (1–2 мин), открой **SQL Editor** → **New query**, вставь целиком и нажми **Run**:

```sql
create table if not exists public.signatures (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 40),
  country text not null default '🌍' check (char_length(country) <= 8),
  is_anon boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.signatures enable row level security;

create policy "anon can insert" on public.signatures
  for insert to anon
  with check (char_length(name) between 1 and 40);

create policy "anyone can read" on public.signatures
  for select to anon
  using (true);
```

3. Открой **Project Settings → API** и скопируй два значения:
   - **Project URL** (вида `https://xxxxxxxx.supabase.co`)
   - **anon public** key (длинная строка, это ПУБЛИЧНЫЙ ключ — его можно светить в коде)

4. Открой `docs/index.html`, найди в начале скрипта блок `const SB = {` и вставь оба значения:

```js
const SB = {
  url:  "https://xxxxxxxx.supabase.co",
  anon: "eyJhbG..."
};
```

Сохрани, закоммить, запушь. Всё — подписи настоящие: бейдж сверху сам сменится на «подписи настоящие», счётчик и стена начнут читать из базы.

> ⚠️ **Никогда не вставляй в код `service_role` key** — только `anon public`. И перевыпусти персональный Access Token (sbp_...), который засветился в чате: Account → Access Tokens → Revoke.

---

## Блок 2 — Публикация (GitHub Pages, ~5 минут)

1. Слей ветку `claude/admiring-ramanujan-3d6h0j` в `main` (через PR или merge).
2. GitHub → репозиторий `wc` → **Settings → Pages**:
   - Source: **Deploy from a branch**
   - Branch: `main`, папка: **`/docs`** → Save
3. Через 1–2 минуты сайт будет жить на `https://murad2026.github.io/wc/`.

> Репозиторий должен быть **публичным** для бесплатных Pages (и это в духе проекта — открытый код). Settings → General → внизу Change visibility → Public.

---

## Блок 3 — Домен (~5 минут + ожидание DNS)

Файл `docs/CNAME` уже содержит `theworldconstitution.org`.

1. У регистратора домена добавь DNS-записи:

| Тип | Имя | Значение |
|---|---|---|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| CNAME | www | murad2026.github.io |

2. GitHub → Settings → Pages → Custom domain: введи `theworldconstitution.org` → Save → дождись галочки DNS check (от минут до пары часов) → включи **Enforce HTTPS**.

Готово: сайт живёт на https://theworldconstitution.org.

---

## Проверка после запуска (чек-лист)

- [ ] Открыл сайт с телефона — бейдж «подписи настоящие»
- [ ] Подписал сам — имя появилось на стене, счётчик = 1
- [ ] Открыл с другого устройства — счётчик и стена показывают то же
- [ ] Подписал анонимно со второго устройства — «Аноним» на стене
- [ ] В Supabase → Table Editor → signatures видны обе записи

После первых 20–50 подписей от своей сети — по плану: посты в сообществах, питч RadicalxChange, заявка на Gitcoin.
