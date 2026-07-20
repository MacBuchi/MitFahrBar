-- In-App-Feedback: Feature-Wünsche und Fehlermeldungen aus der App.
-- Der Feedback-Bot (.github/workflows/feedback.yml) macht daraus
-- GitHub-Issues und setzt processed_at.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  type text not null default 'feature' check (type in ('feature', 'bug')),
  message text not null check (char_length(message) between 3 and 2000),
  app_version text,
  platform text,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create index feedback_unprocessed_idx on public.feedback (created_at)
  where processed_at is null;

alter table public.feedback enable row level security;

-- Jede Gruppe darf eigenes Feedback einreichen und nachlesen – mehr nicht.
create policy feedback_insert on public.feedback for insert to authenticated
  with check (group_id = auth.uid() and public.my_group_active());
create policy feedback_select_own on public.feedback for select to authenticated
  using (group_id = auth.uid());

-- Der Bot liest/schreibt mit dem Service-Role-Key an RLS vorbei.
grant all on public.feedback to service_role;
