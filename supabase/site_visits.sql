-- Website visit counter for the portal "Visits" tab (project ref jhduhnrtvbvfsgdfpymx).
-- Applied as migration "site_visits_counter" on 2026-11-24. Reference copy only; no secrets here.
-- Stores no IP, cookies, or personal data: just the page path, the referring site's host name,
-- and a random anonymous id kept in the visitor's browser (localStorage) for unique counts.

create table public.site_visits (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  path text not null default '/' check (char_length(path) between 1 and 200),
  referrer_host text check (referrer_host is null or char_length(referrer_host) between 1 and 253),
  visitor_id text check (visitor_id is null or visitor_id ~ '^[A-Za-z0-9-]{8,64}$')
);
create index site_visits_created_idx on public.site_visits (created_at);
comment on table public.site_visits is 'One row per public page load on jacksonforliberty.com. No IP or personal data. Insert-only for clients; readable only by portal allowlist.';

alter table public.site_visits enable row level security;
revoke all on table public.site_visits from anon, authenticated;
grant insert (path, referrer_host, visitor_id) on table public.site_visits to anon, authenticated;
grant select on table public.site_visits to authenticated;

create policy "anyone can log a visit" on public.site_visits
  for insert to anon, authenticated
  with check (
    char_length(path) between 1 and 200
    and (referrer_host is null or char_length(referrer_host) <= 253)
    and (visitor_id is null or char_length(visitor_id) <= 64)
  );
create policy "portal users read visits" on public.site_visits
  for select to authenticated using ((select public.is_portal_user()));
-- No UPDATE/DELETE grants or policies: clients can't change or remove rows.

-- Monthly totals (months in Central Time), newest first. SECURITY INVOKER, so table RLS also applies,
-- and it refuses anyone who isn't on the portal allowlist.
create or replace function public.portal_visits_by_month()
returns table (month date, visits bigint, unique_visitors bigint)
language plpgsql stable security invoker set search_path = '' as $$
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  return query
    select (date_trunc('month', v.created_at at time zone 'America/Chicago'))::date as month,
           count(*)::bigint as visits,
           (count(distinct v.visitor_id) + count(*) filter (where v.visitor_id is null))::bigint as unique_visitors
    from public.site_visits v
    group by 1
    order by 1 desc;
end; $$;
revoke all on function public.portal_visits_by_month() from public, anon;
grant execute on function public.portal_visits_by_month() to authenticated;
