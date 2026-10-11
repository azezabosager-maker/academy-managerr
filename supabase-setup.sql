-- Run this once in the Supabase SQL Editor.
-- The browser uses only the public anon/publishable key. Row Level Security
-- limits every record to the signed-in account.

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 100),
  phone text not null default '',
  guardian text not null default '',
  guardian_phone text not null default '',
  sport text not null default '',
  training_days text not null default '',
  coach text not null default '',
  level text not null default '',
  notes text not null default '',
  photo_data text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint students_owner_id_id_unique unique (owner_id, id)
);

alter table public.students add column if not exists training_days text not null default '';
alter table public.students add column if not exists photo_data text not null default '';

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  student_id uuid not null,
  start_date date not null,
  months integer not null check (months between 1 and 120),
  end_date date not null,
  price numeric(12,2) not null check (price >= 0),
  due_date date,
  created_at timestamptz not null default now(),
  constraint subscriptions_id_student_id_unique unique (id, student_id),
  constraint subscription_owner_student_fk foreign key (owner_id, student_id)
    references public.students(owner_id, id) on delete cascade
);

alter table public.subscriptions add column if not exists due_date date;

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  student_id uuid not null,
  subscription_id uuid not null,
  amount numeric(12,2) not null check (amount > 0),
  paid_at date not null default current_date,
  created_at timestamptz not null default now(),
  constraint payment_owner_student_fk foreign key (owner_id, student_id)
    references public.students(owner_id, id) on delete cascade,
  constraint payment_subscription_student_fk foreign key (subscription_id, student_id)
    references public.subscriptions(id, student_id) on delete cascade
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category text not null check (category in ('rent','salaries','electricity','sportsEquipment','miscellaneous')),
  amount numeric(12,2) not null check (amount > 0),
  date date not null,
  description text not null default '' check (char_length(description) <= 200),
  created_at timestamptz not null default now()
);

create index if not exists students_owner_name_idx on public.students(owner_id, name);
create index if not exists students_owner_phone_idx on public.students(owner_id, phone);
create index if not exists subscriptions_owner_student_recent_idx on public.subscriptions(owner_id, student_id, created_at desc);
create index if not exists payments_owner_paid_recent_idx on public.payments(owner_id, paid_at desc, created_at desc);
create index if not exists expenses_owner_date_recent_idx on public.expenses(owner_id, date desc, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists students_set_updated_at on public.students;
create trigger students_set_updated_at
before update on public.students
for each row execute function public.set_updated_at();

create or replace function public.make_subscription_end_date(p_start date, p_months integer)
returns date
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
  target_month date;
  target_last_day date;
begin
  if p_months < 1 or p_months > 120 then
    raise exception 'Subscription duration must be between 1 and 120 months';
  end if;
  target_month := (date_trunc('month', p_start)::date + make_interval(months => p_months))::date;
  target_last_day := (target_month + interval '1 month' - interval '1 day')::date;
  return target_month + least(extract(day from p_start)::integer, extract(day from target_last_day)::integer) - 1;
end;
$$;

create or replace function public.set_subscription_end_date()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.end_date := public.make_subscription_end_date(new.start_date, new.months);
  return new;
end;
$$;

drop trigger if exists subscriptions_set_end_date on public.subscriptions;
create trigger subscriptions_set_end_date
before insert or update of start_date, months on public.subscriptions
for each row execute function public.set_subscription_end_date();

-- Remove the previous version's broad security-definer helper if it exists.
drop function if exists public.create_subscription_with_payment(uuid, date, integer, numeric, numeric, date);

alter table public.students enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;
alter table public.expenses enable row level security;

revoke all on public.students, public.subscriptions, public.payments, public.expenses from public, anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.students, public.subscriptions, public.payments, public.expenses to authenticated;

drop policy if exists "Students are private to their owner" on public.students;
create policy "Students are private to their owner"
on public.students for all to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists "Subscriptions are private to their owner" on public.subscriptions;
drop policy if exists "Owners can read their subscriptions" on public.subscriptions;
drop policy if exists "Owners can add their subscriptions" on public.subscriptions;
create policy "Subscriptions are private to their owner"
on public.subscriptions for all to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1 from public.students
    where students.id = subscriptions.student_id
      and students.owner_id = (select auth.uid())
  )
);

drop policy if exists "Payments are private to their owner" on public.payments;
drop policy if exists "Owners can read their payments" on public.payments;
drop policy if exists "Owners can add their payments" on public.payments;
create policy "Payments are private to their owner"
on public.payments for all to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1 from public.students
    where students.id = payments.student_id
      and students.owner_id = (select auth.uid())
  )
  and exists (
    select 1 from public.subscriptions
    where subscriptions.id = payments.subscription_id
      and subscriptions.student_id = payments.student_id
      and subscriptions.owner_id = (select auth.uid())
  )
);

drop policy if exists "Expenses are private to their owner" on public.expenses;
create policy "Expenses are private to their owner"
on public.expenses for all to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.students;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.subscriptions;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.payments;
    exception when duplicate_object then null;
    end;
    begin
      alter publication supabase_realtime add table public.expenses;
    exception when duplicate_object then null;
    end;
  end if;
end;
$$;
