-- Noting 앱 전용 테이블 (healthfam과 충돌 방지용 noting_ 접두사)
-- Supabase 대시보드 → SQL Editor → New query → 붙여넣고 Run

-- 1. noting_notes
create table if not exists public.noting_notes (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users not null default auth.uid(),
  content    text not null,
  created_at bigint not null,
  category   text
);
alter table public.noting_notes enable row level security;
drop policy if exists "own noting_notes" on public.noting_notes;
create policy "own noting_notes"
  on public.noting_notes for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 2. noting_todos
create table if not exists public.noting_todos (
  id          bigint generated always as identity primary key,
  user_id     uuid references auth.users not null default auth.uid(),
  text        text not null,
  date        text not null,
  done        integer not null default 0,
  created_at  bigint not null,
  order_index integer not null default 0,
  start_time  text,
  end_time    text
);
alter table public.noting_todos enable row level security;
drop policy if exists "own noting_todos" on public.noting_todos;
create policy "own noting_todos"
  on public.noting_todos for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 3. noting_time_records
create table if not exists public.noting_time_records (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users not null default auth.uid(),
  todo_id    bigint references public.noting_todos on delete cascade not null,
  start_time text not null,
  end_time   text
);
alter table public.noting_time_records enable row level security;
drop policy if exists "own noting_time_records" on public.noting_time_records;
create policy "own noting_time_records"
  on public.noting_time_records for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);
