-- Portal chat lock (project ref jhduhnrtvbvfsgdfpymx).
-- Applied as migration "portal_chat_lock". Reference copy only; no secrets here.
-- Chat (public.portal_messages) is readable/writable ONLY by the emails in
-- public.portal_chat_access. That table has no grants or policies for anon/authenticated,
-- and no portal RPC touches it, so the Team tab can never grant chat access.
-- Changing it requires SQL as the database owner (Supabase dashboard / migration).

create table if not exists public.portal_chat_access (
  email text primary key check (email = lower(email))
);
alter table public.portal_chat_access enable row level security;
revoke all on table public.portal_chat_access from anon, authenticated;
insert into public.portal_chat_access (email) values
  ('brandonjackson178@gmail.com'), ('myers.a2844@gmail.com')
on conflict do nothing;

create or replace function public.is_portal_chat_user()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.portal_chat_access
    where email = lower(coalesce((select auth.jwt() ->> 'email'), ''))
  );
$$;
revoke all on function public.is_portal_chat_user() from public, anon;
grant execute on function public.is_portal_chat_user() to authenticated;

drop policy if exists "portal users read all messages" on public.portal_messages;
drop policy if exists "portal users post as brandon" on public.portal_messages;
create policy "chat users read messages" on public.portal_messages
  for select to authenticated using ((select public.is_portal_chat_user()));
create policy "chat users post as brandon" on public.portal_messages
  for insert to authenticated with check ((select public.is_portal_chat_user()) and author = 'brandon');
-- Webhook trigger portal_messages_webhook (WHEN new.author = 'brandon') is unchanged.

-- Aaron can sign in to the portal (same pre-created confirmed email user as Team-tab adds).
insert into public.portal_allowed_emails (email) values ('myers.a2844@gmail.com') on conflict do nothing;
do $$
declare v_uid uuid := gen_random_uuid(); v_email text := 'myers.a2844@gmail.com';
begin
  if not exists (select 1 from auth.users where lower(email) = v_email) then
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change,
      email_change_token_current, phone_change, phone_change_token, reauthentication_token, is_sso_user, is_anonymous)
    values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email, '', now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
      '', '', '', '', '', '', '', '', false, false);
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, created_at, updated_at)
    values (gen_random_uuid(), v_uid, v_uid::text, 'email',
      jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true, 'phone_verified', false), now(), now());
  end if;
end $$;

-- Chat members (Brandon, Aaron) can't be removed from the team list via the Team tab.
create or replace function public.portal_list_team()
returns table (email text, has_account boolean, last_sign_in_at timestamptz, protected boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query
    select a.email, (u.id is not null), u.last_sign_in_at,
           exists (select 1 from public.portal_chat_access c where c.email = a.email)
    from public.portal_allowed_emails a
    left join auth.users u on lower(u.email) = a.email
    order by (a.email = 'brandonjackson178@gmail.com') desc,
             exists (select 1 from public.portal_chat_access c where c.email = a.email) desc, a.email;
end; $$;

create or replace function public.portal_remove_team_email(p_email text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  if v_email = 'brandonjackson178@gmail.com' then
    raise exception 'Brandon''s address can''t be removed' using errcode = '42501';
  end if;
  if exists (select 1 from public.portal_chat_access where email = v_email) then
    raise exception 'that address can''t be removed' using errcode = '42501';
  end if;
  perform 1 from public.portal_allowed_emails for update;  -- serialize removals
  if not exists (select 1 from public.portal_allowed_emails where email = v_email) then
    raise exception 'that email is not on the team list' using errcode = 'P0002';
  end if;
  if (select count(*) from public.portal_allowed_emails) <= 1 then
    raise exception 'can''t remove the last team member' using errcode = '42501';
  end if;
  delete from public.portal_allowed_emails where email = v_email;
  delete from auth.users where lower(email) = v_email;
  return v_email;
end; $$;
revoke all on function public.portal_list_team() from public, anon;
revoke all on function public.portal_remove_team_email(text) from public, anon;
grant execute on function public.portal_list_team() to authenticated;
grant execute on function public.portal_remove_team_email(text) to authenticated;
