-- Portal upgrade: team access RPCs and volunteer signups (project ref jhduhnrtvbvfsgdfpymx).
-- Applied as migration "portal_team_and_signups". Reference copy only; no secrets here.

-- ===== Team access =====
create or replace function public.portal_list_team()
returns table (email text, has_account boolean, last_sign_in_at timestamptz, protected boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query
    select a.email, (u.id is not null), u.last_sign_in_at, (a.email = 'brandonjackson178@gmail.com')
    from public.portal_allowed_emails a
    left join auth.users u on lower(u.email) = a.email
    order by (a.email = 'brandonjackson178@gmail.com') desc, a.email;
end; $$;

create or replace function public.portal_add_team_email(p_email text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(coalesce(p_email, ''))); v_uid uuid;
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email address' using errcode = '22023';
  end if;
  if (select count(*) from public.portal_allowed_emails) >= 25 then
    raise exception 'team list is full (25 max)' using errcode = '54000';
  end if;
  insert into public.portal_allowed_emails (email) values (v_email) on conflict do nothing;
  -- Pre-create a confirmed email user so the one-time login link works (client keeps shouldCreateUser:false).
  if not exists (select 1 from auth.users where lower(email) = v_email) then
    v_uid := gen_random_uuid();
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
  return v_email;
end; $$;

create or replace function public.portal_remove_team_email(p_email text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(coalesce(p_email, '')));
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  if v_email = 'brandonjackson178@gmail.com' then
    raise exception 'Brandon''s address can''t be removed' using errcode = '42501';
  end if;
  perform 1 from public.portal_allowed_emails for update;  -- serialize removals
  if not exists (select 1 from public.portal_allowed_emails where email = v_email) then
    raise exception 'that email is not on the team list' using errcode = 'P0002';
  end if;
  if (select count(*) from public.portal_allowed_emails) <= 1 then
    raise exception 'can''t remove the last team member' using errcode = '42501';
  end if;
  delete from public.portal_allowed_emails where email = v_email;
  -- Remove their login too, ending any sessions.
  delete from auth.users where lower(email) = v_email;
  return v_email;
end; $$;

revoke all on function public.portal_list_team() from public, anon;
revoke all on function public.portal_add_team_email(text) from public, anon;
revoke all on function public.portal_remove_team_email(text) from public, anon;
grant execute on function public.portal_list_team() to authenticated;
grant execute on function public.portal_add_team_email(text) to authenticated;
grant execute on function public.portal_remove_team_email(text) to authenticated;

-- ===== Volunteer signups (mirror of the FormSubmit email; message text is not stored) =====
create table public.signups (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  email text not null check (char_length(email) between 3 and 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  city_state text check (city_state is null or char_length(city_state) <= 120),
  interests text check (interests is null or char_length(interests) <= 300)
);
create index signups_created_idx on public.signups (created_at desc);
alter table public.signups enable row level security;
revoke all on table public.signups from anon, authenticated;
grant insert (name, email, city_state, interests) on table public.signups to anon, authenticated;
grant select on table public.signups to authenticated;

create policy "anyone can submit a signup" on public.signups
  for insert to anon, authenticated
  with check (char_length(btrim(name)) between 1 and 120 and char_length(email) <= 254);
create policy "portal users read signups" on public.signups
  for select to authenticated using ((select public.is_portal_user()));

-- Light abuse throttle: same email at most once per 10 minutes; at most 60 signups per 10 minutes overall.
create or replace function public.throttle_signups()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.email := lower(btrim(new.email));
  new.name := btrim(new.name);
  if exists (select 1 from public.signups where email = new.email and created_at > now() - interval '10 minutes') then
    raise exception 'duplicate signup' using errcode = '23505';
  end if;
  if (select count(*) from public.signups where created_at > now() - interval '10 minutes') >= 60 then
    raise exception 'too many signups, try later' using errcode = '54000';
  end if;
  return new;
end; $$;
revoke all on function public.throttle_signups() from public, anon, authenticated;
create trigger signups_throttle before insert on public.signups
  for each row execute function public.throttle_signups();
