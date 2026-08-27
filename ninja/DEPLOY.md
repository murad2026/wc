# Verified.Ninja — запуск за один вечер

> Цель: лендинг живёт на verified.ninja и принимает оплату. Никакой базы, дашбордов и бэкенда — первые заказы обрабатываются вручную.

---

## 1. Stripe Payment Link (10 минут)

1. [stripe.com](https://stripe.com) → зарегистрироваться (гражданин США — активация мгновенная, нужен SSN или EIN).
2. **Products** → **Add product**:
   - Name: `Verified Tech Screen`
   - Price: `$199`, one-time
3. **Payment Links** → **Create link** → выбрать продукт.
4. В настройках ссылки включить:
   - **Collect customer email** ✅
   - **Custom fields** → добавить два текстовых поля: `Candidate name` и `Candidate email / LinkedIn`
   - **After payment** → Confirmation page, текст: *"Thanks. Check your email — we'll send the expert's details and a scheduling link within 24 hours."*
5. Скопировать ссылку вида `https://buy.stripe.com/xxxxx`.
6. В `index.html` заменить `STRIPE_PAYMENT_LINK` на неё (одно место, в самом низу).

> LLC можно оформить параллельно — Stripe принимает и физлицо на старте. Wyoming LLC через Firstbase/Stripe Atlas, но это не блокер для первой продажи.

---

## 2. Деплой (5 минут)

**Вариант A — Netlify Drop (быстрее всего):**
1. [app.netlify.com/drop](https://app.netlify.com/drop)
2. Перетащить папку `ninja/`
3. Site settings → Domain → Add custom domain → `verified.ninja`
4. У регистратора домена прописать DNS-записи, которые покажет Netlify

**Вариант B — Vercel:**
1. Создать новый приватный репозиторий `verified-ninja`, залить содержимое `ninja/`
2. [vercel.com](https://vercel.com) → Import Project → выбрать репозиторий
3. Domains → добавить `verified.ninja`

Оба варианта бесплатны, HTTPS включается автоматически.

---

## 3. Почта (5 минут)

Нужен адрес `hello@verified.ninja` (он указан на лендинге).

Самое простое — форвардинг у регистратора домена (Namecheap, Cloudflare Email Routing — бесплатно) на твой личный ящик.

---

## 4. Как обрабатывать заказ вручную

```
Stripe присылает уведомление об оплате
   ↓
Пишешь клиенту письмо: настоящее имя эксперта, LinkedIn, фото,
ссылка на календарь для выбора слота
   ↓
Эксперт проводит 15-минутный созвон
   ↓
Заполняет отчёт (Google Docs по шаблону) → экспорт в PDF
   ↓
Отправляешь клиенту письмом
   ↓
Платишь эксперту $100 (Wise / Zelle / ACH)
```

Никакого кода. Так работают первые 10 заказов; после этого станет ясно, что именно автоматизировать.

---

## 5. Шаблон отчёта (Google Docs)

```
VERIFIED TECH SCREEN — CONFIDENTIAL
Candidate: [имя]        Date: [дата]
Screened by: [настоящее имя эксперта], former Amazon Bar Raiser
Duration: 15 min live video

RATINGS (1–5)
Technical depth:      [ ]
Problem solving:      [ ]
Communication:        [ ]
Ownership / autonomy: [ ]
Overall:              [ ]

RECOMMENDATION
[ ] Strong hire  [ ] Hire  [ ] Risk — proceed with caution
[ ] No hire      [ ] Strong no hire

WHAT WAS VERIFIED
- Claimed experience with [X]: confirmed / partially / not confirmed
- Depth beyond surface level: [заметки]

RED FLAGS
[что насторожило, либо "None observed"]

NOTES FOR THE HIRING MANAGER
[2–4 предложения: где кандидат силён, где риск, что проверить дальше]
```

---

## 6. Kill switch

- **30 писем CTO → 0 заказов** = ниша не подтвердилась, меняем сегмент.
- **Первые 3 заказа без повторных обращений** = боль недостаточно острая.

Проверяется за 30 дней и стоит один вечер работы.

---

## Чего сознательно НЕ делаем сейчас

Базы данных, личных кабинетов, автоматического назначения экспертов, системы рангов, вебхуков, интеграции с календарём. Всё это строится **после первого платящего клиента**, а не до.
