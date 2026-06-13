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

-- 4. 인덱스 (조회 성능)
--  - notes: 사용자별 최신순 조회
--  - todos: 사용자+날짜 필터
--  - time_records: todo_id 임베드/조인 조회
create index if not exists noting_notes_user_created_idx
  on public.noting_notes (user_id, created_at desc);
create index if not exists noting_todos_user_date_idx
  on public.noting_todos (user_id, date);
create index if not exists noting_time_records_todo_idx
  on public.noting_time_records (todo_id);

-- 5. 계정 삭제 시 사용자 데이터 자동 정리 (CASCADE)
-- 기존 FK는 CASCADE 없이 만들어져서 auth.users 삭제가 막힘. 재정의.
alter table public.noting_notes
  drop constraint if exists noting_notes_user_id_fkey,
  add  constraint noting_notes_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;
alter table public.noting_todos
  drop constraint if exists noting_todos_user_id_fkey,
  add  constraint noting_todos_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;
alter table public.noting_time_records
  drop constraint if exists noting_time_records_user_id_fkey,
  add  constraint noting_time_records_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade;

-- 6. 카테고리 (사용자별 메모 카테고리 목록 + 순서)
-- 이전에는 SharedPreferences(폰 로컬)에만 있어서 다기기 동기화/유저 격리가
-- 안 됐음. 이 테이블로 옮기면 사용자별·다기기 일관성 보장.
create table if not exists public.noting_categories (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users (id) on delete cascade not null default auth.uid(),
  name       text not null,
  position   integer not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);
alter table public.noting_categories enable row level security;
drop policy if exists "own noting_categories" on public.noting_categories;
create policy "own noting_categories"
  on public.noting_categories for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create index if not exists noting_categories_user_pos_idx
  on public.noting_categories (user_id, position);

-- 7. AI 호출 rate limit 추적
-- classify Edge Function이 호출될 때마다 1행 기록.
-- 시간당/일별 카운트로 사용자별 횟수 제한.
create table if not exists public.noting_ai_calls (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users on delete cascade not null,
  created_at timestamptz not null default now()
);
create index if not exists noting_ai_calls_user_time_idx
  on public.noting_ai_calls (user_id, created_at desc);
alter table public.noting_ai_calls enable row level security;
-- 정책 없음 — 함수가 service_role로 직접 쓰고, 사용자는 읽을 일 없음.
