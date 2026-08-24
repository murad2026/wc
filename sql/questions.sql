-- Вопросы человечеству + поддержка. Прогнать в Supabase → SQL Editor → Run.

create table if not exists public.questions (
  id bigint generated always as identity primary key,
  text text not null check (char_length(text) between 10 and 200),
  author text not null default 'Аноним' check (char_length(author) <= 40),
  country text not null default '🌍' check (char_length(country) <= 8),
  status text not null default 'pending'
    check (status in ('pending','approved','published','rejected')),
  created_at timestamptz not null default now()
);

alter table public.questions enable row level security;

-- любой может предложить вопрос
create policy "anon can propose" on public.questions
  for insert to anon
  with check (char_length(text) between 10 and 200);

-- публично видны только одобренные и опубликованные
create policy "anyone reads approved" on public.questions
  for select to anon
  using (status in ('approved','published'));


-- поддержка вопросов (upvote)
create table if not exists public.question_supports (
  id bigint generated always as identity primary key,
  question_id bigint not null references public.questions(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.question_supports enable row level security;

create policy "anon can support" on public.question_supports
  for insert to anon with check (true);

create policy "anyone reads supports" on public.question_supports
  for select to anon using (true);

-- Модерация: Table Editor → questions → меняешь status:
--   pending   — новый, публично не виден
--   approved  — виден всем, можно поддерживать
--   published — стал «Вопросом дня»
--   rejected  — отклонён (спам/нарушение)
