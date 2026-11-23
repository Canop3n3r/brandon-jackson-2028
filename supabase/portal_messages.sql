-- Campaign portal chat backend (Supabase project ref jhduhnrtvbvfsgdfpymx).
-- Applied as migration "portal_messages_init". Reference copy only; no secrets here.

-- 1. Retire the old visitor-feedback webhook (table and data are kept).
drop trigger if exists site_feedback_webhook on public.site_feedback;

-- 2. Who may use the portal.
create table if not exists public.portal_allowed_emails (
  email text primary key check (email = lower(email))
);
alter table public.portal_allowed_emails enable row level security;
revoke all on table public.portal_allowed_emails from anon, authenticated;
insert into public.portal_allowed_emails (email) values
  ('brandonjackson178@gmail.com'), ('info@jacksonforliberty.com')
on conflict do nothing;

create or replace function public.is_portal_user()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.portal_allowed_emails
    where email = lower(coalesce((select auth.jwt() ->> 'email'), ''))
  );
$$;
revoke all on function public.is_portal_user() from public, anon;
grant execute on function public.is_portal_user() to authenticated;

-- 3. Messages.
create table public.portal_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  author text not null check (author in ('brandon', 'bot')),
  body text not null check (char_length(body) between 1 and 4000),
  status text not null default 'new'
);
create index portal_messages_created_idx on public.portal_messages (created_at);
alter table public.portal_messages enable row level security;
revoke all on table public.portal_messages from anon, authenticated;
grant select on table public.portal_messages to authenticated;
grant insert (author, body) on table public.portal_messages to authenticated;

create policy "portal users read all messages" on public.portal_messages
  for select to authenticated using ((select public.is_portal_user()));
create policy "portal users post as brandon" on public.portal_messages
  for insert to authenticated with check ((select public.is_portal_user()) and author = 'brandon');

-- Live updates in the portal.
alter publication supabase_realtime add table public.portal_messages;

-- 4. Webhook: POST {type, id, created_at} for each new 'brandon' message to the routine
-- webhook. Reuses Vault secrets 'feedback_webhook_url' and 'feedback_webhook_key'.
create or replace function public.notify_portal_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_url text; v_key text;
begin
  begin
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'feedback_webhook_url' limit 1;
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'feedback_webhook_key' limit 1;
    if v_url is null or v_url = '' or v_key is null or v_key = '' then return new; end if;
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object('type', 'portal_message', 'id', new.id, 'created_at', new.created_at),
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || v_key, 'X-Webhook-Key', v_key),
      timeout_milliseconds := 5000);
  exception when others then
    raise warning 'notify_portal_message failed: %', sqlerrm;
  end;
  return new;
end; $$;
revoke all on function public.notify_portal_message() from public, anon, authenticated;
create trigger portal_messages_webhook after insert on public.portal_messages
  for each row when (new.author = 'brandon')
  execute function public.notify_portal_message();

-- 5. Only allowlisted emails can ever become auth users.
create or replace function public.enforce_portal_signup_allowlist()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.email is null or not exists (
    select 1 from public.portal_allowed_emails where email = lower(new.email)
  ) then
    raise exception 'signups are restricted';
  end if;
  return new;
end; $$;
revoke all on function public.enforce_portal_signup_allowlist() from public, anon, authenticated;
create trigger enforce_portal_signup_allowlist before insert on auth.users
  for each row execute function public.enforce_portal_signup_allowlist();
