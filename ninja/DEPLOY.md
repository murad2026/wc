# Verified.Ninja — публикация

Сайт собирается из этой папки и живёт на домене `verified.ninja`.
Внутренние документы (экономика, доли, планка допуска, формула балла) в этом
репозитории не лежат — он публичный. Они в приватном `murad2026/verified`.

## Сборка

```bash
bash ninja/build.sh
```

Кладёт в `ninja/dist/` только то, что должен видеть клиент: восемь страниц,
`app.css`, `i18n.js`, пять словарей, `CNAME`, `robots.txt`, `sitemap.xml`.

`ninja/dist/` в git не коммитится — Cloudflare пересобирает её на каждый пуш.

Скрипт копирует файлы поимённо, а не по маске, поэтому посторонний файл
в сборку попасть не может, даже если появится в папке.

---

## Часть 1. Supabase

Пока это не сделано, форма заказа и анкета эксперта показывают честную ошибку
с предложением написать на почту.

1. Открыть пустой запрос:
   `https://supabase.com/dashboard/project/nhkwgulokiwqwfrynmkx/sql/new`
2. Вставить целиком `sql/orders.sql` → **Run** (⌘/Ctrl + Enter).
3. Правильный ответ — зелёное **Success. No rows returned**: создавали таблицу,
   а не запрашивали данные.
4. Открыть новый запрос и повторить с `sql/experts.sql`.

**Проверить:** `https://supabase.com/dashboard/project/nhkwgulokiwqwfrynmkx/editor`
— слева должны быть `experts` и `orders`. Сейчас есть `orders`, но нет `experts`:
второй скрипт ещё не запускался.

| Ошибка на Run | Что значит |
|---|---|
| `relation ... already exists` | Не ошибка, таблица уже создана |
| `policy ... already exists` | Скрипт запускали дважды, политики не пересоздаются |
| `syntax error at or near` | Скопирована часть файла — копировать от первой строки до последней |
| `permission denied` | Не тот проект или вход не под владельцем |

**Живая проверка:** заполнить форму на `/order.html`, получить номер `VN-XXXXXX`,
увидеть строку в Table Editor, пробить номер на `/status.html`, тестовую строку удалить.

---

## Часть 2. Домен

Домен куплен на GoDaddy, публикуем через **Cloudflare Pages**.

Почему Cloudflare, а не GitHub Pages: у репозитория уже занят кастомный домен
под `theworldconstitution.org` — на один репозиторий GitHub даёт ровно один.
И Cloudflare становится DNS-хостингом домена, поэтому **домен нельзя оставить
висящим**: история, когда мы потеряли theworldconstitution.org и его подхватил
чужой сайт с казино, здесь не повторится по устройству.

### Шаг 1. Cloudflare забирает домен

1. **cloudflare.com** → **Add a site** → `verified.ninja` → план **Free**.
2. Cloudflare покажет два своих nameserver'а вида `xxx.ns.cloudflare.com`.
3. **GoDaddy** → My Products → у домена **DNS** → вкладка **Nameservers** →
   **Change** → **I'll use my own nameservers** → вставить оба → сохранить.
4. Ждать статус **Active**. Обычно минуты, иногда до суток.

Смена nameserver'ов отменяет вкладку DNS Records у GoDaddy целиком — дальше
отвечает Cloudflare. Он попытается импортировать записи; чистить их надо уже
в его панели **DNS → Records**:

| Запись | Что с ней |
|---|---|
| `A @ → WebsiteBuilder Site` | **Удалить** — парковка GoDaddy, Pages поставит свою |
| `CNAME www → verified.ninja` | **Удалить** — `www` добавим вторым доменом в Pages |
| `CNAME _domainconnect` | **Удалить** — автонастройка GoDaddy, без их nameserver'ов мертва |
| `CNAME pay → paylinks.commerce.godaddy.com` | Удалить, если платёжные ссылки GoDaddy не используются |
| `TXT _dmarc` | **Оставить** — понадобится под почту |
| `NS @`, `SOA @` | Меняются сами, руками не трогать |

Заранее у GoDaddy удалять ничего не нужно — только вкладка **Nameservers**.

### Шаг 2. Pages собирает сайт

Cloudflare → **Workers & Pages** → **Create** → вкладка **Pages** →
**Connect to Git** → репозиторий `murad2026/wc`.

| Поле | Значение |
|---|---|
| Production branch | `claude/admiring-ramanujan-3d6h0j` |
| Framework preset | None |
| Build command | `bash ninja/build.sh` |
| Build output directory | `ninja/dist` |
| Root directory | пусто |

**Save and Deploy** → появится адрес вида `verified-ninja.pages.dev`, открыть
и убедиться, что сайт работает.

### Шаг 3. Домен на проект

1. Проект Pages → **Custom domains** → **Set up a domain** → `verified.ninja`.
2. Добавить вторым доменом `www.verified.ninja` — перекинет на основной.

Сертификат выпускается сам.

`theworldconstitution.org` при этом не трогается: он как публиковался
с GitHub Pages из `docs/`, так и публикуется.

---

## После переезда

1. **Ссылка на странице Рынка** должна вести на `https://verified.ninja`,
   а не на `ninja/` — это поле `url` в шести файлах `docs/lang/*.json`.
2. **Старый путь `theworldconstitution.org/ninja/` не удалять** — оставить
   страницу с редиректом, на него уже могут быть ссылки.
3. **Почта `hello@verified.ninja`.** Она указана на всех страницах, и пока её
   нет, мы обещаем то, чего не выполняем. Когда DNS уже в Cloudflare, проще
   всего **Email Routing**: бесплатно, пересылает на любой существующий ящик,
   сам ставит MX и SPF.
4. **Проверить с телефона** все пять языков: главная, профили, заказ, статус, анкета.

## Чего не делать

- Не включать у GoDaddy Website Builder или парковку на этом домене.
- Не удалять проект Pages, пока домен смотрит на Cloudflare — это и есть
  «висящий домен».
- Не класть внутренние документы в этот репозиторий: он публичный.
