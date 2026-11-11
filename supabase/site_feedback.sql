-- Visitor feedback backend (Supabase project "site-feedback", ref jhduhnrtvbvfsgdfpymx).
-- Applied as migration "site_feedback_init". Reference copy only; no secrets here.
create extension if not exists pg_net with schema extensions;

create table public.site_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  site text default 'brandon-jackson-2028',
  page_url text,
  viewport text,
  user_agent text,
  comment text not null check (char_length(comment) between 1 and 2000),
  screenshot_path text,
  status text not null default 'new' check (status in ('new','in_progress','done','rejected')),
  resolution_note text
);
alter table public.site_feedback enable row level security;
revoke all on table public.site_feedback from anon, authenticated;
grant insert (site, page_url, viewport, user_agent, comment, screenshot_path, status, resolution_note)
  on table public.site_feedback to anon;
create policy "anon can submit feedback" on public.site_feedback
  for insert to anon with check (status = 'new' and resolution_note is null);
create index site_feedback_status_created_idx on public.site_feedback (status, created_at desc);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-screenshots', 'feedback-screenshots', false, 5242880, array['image/png','image/jpeg']);
create policy "anon can upload feedback screenshots" on storage.objects
  for insert to anon
  with check (bucket_id = 'feedback-screenshots' and lower(storage.extension(name)) in ('png','jpg','jpeg'));

-- Webhook: POSTs each new row to the URL in Vault secret 'feedback_webhook_url',
-- authenticated with Vault secret 'feedback_webhook_key'. No-op if either is missing.
create or replace function public.notify_site_feedback()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_url text; v_key text;
begin
  begin
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'feedback_webhook_url' limit 1;
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'feedback_webhook_key' limit 1;
    if v_url is null or v_url = '' or v_key is null or v_key = '' then return new; end if;
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object('id', new.id, 'created_at', new.created_at, 'comment', new.comment,
                                 'page_url', new.page_url, 'screenshot_path', new.screenshot_path),
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || v_key, 'X-Webhook-Key', v_key),
      timeout_milliseconds := 5000);
  exception when others then
    raise warning 'notify_site_feedback failed: %', sqlerrm;
  end;
  return new;
end; $$;
revoke all on function public.notify_site_feedback() from public, anon, authenticated;
create trigger site_feedback_webhook after insert on public.site_feedback
  for each row execute function public.notify_site_feedback();

-- To turn the webhook on (run once, with real values):
--   select vault.create_secret('<WEBHOOK_URL>', 'feedback_webhook_url');
--   select vault.create_secret('<WEBHOOK_KEY>', 'feedback_webhook_key');
