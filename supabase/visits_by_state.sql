-- Visits by US state for the portal "Visits" tab (project ref jhduhnrtvbvfsgdfpymx).
-- Applied as migration "visits_by_state_geo" on 2026-11-26. Reference copy only; no secrets here.
--
-- How it works (no outside services, nothing paid, no IP stored):
--   * The public site's visit insert is unchanged. A BEFORE INSERT trigger reads two headers that
--     Supabase's Cloudflare edge adds to every API request: cf-ipcountry (country) and
--     cf-connecting-ip (the visitor's IP; Cloudflare rejects requests that try to fake it).
--   * For US visitors the IP is matched against public.geo_ip_state, a local copy of the free
--     DB-IP "IP to City Lite" database (CC BY 4.0, https://db-ip.com) reduced to US-state blocks.
--     Only the 2-letter country and state are saved. The IP is used in memory and then discarded.
--   * Rows logged before this migration have country = null and are left out of the state view.
--   * Rebuild/refresh the lookup table with supabase/geo/build_geo_ip_state.py (see its header).

alter table public.site_visits
  add column if not exists country text check (country is null or country ~ '^[A-Z0-9]{2}$'),
  add column if not exists region  text check (region  is null or region  ~ '^[A-Z]{2}$');
comment on column public.site_visits.country is 'Visitor country code from Cloudflare (XX = unknown). Set by trigger; clients cannot write it.';
comment on column public.site_visits.region  is 'Approximate US state/territory code from a local IP-range table. Set by trigger; IP is never stored.';
-- Clients keep their existing column-level INSERT grant (path, referrer_host, visitor_id) only,
-- so they can't supply country/region themselves; the trigger always overwrites them.

-- Local IP-range -> US state lookup (step table: each row is the start of a block; a block runs
-- until the next row's start). Not readable or writable by any client role.
create table if not exists public.geo_ip_state (
  start_ip inet primary key,
  state text not null check (state ~ '^[A-Z]{2}$')
);
comment on table public.geo_ip_state is 'US IP block starts -> state code, from DB-IP IP to City Lite (CC BY 4.0, https://db-ip.com). Server-side lookup only.';
alter table public.geo_ip_state enable row level security;
revoke all on table public.geo_ip_state from public, anon, authenticated;

create or replace function public.site_visit_geo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  h jsonb;
  cc text;
  v_ip inet;
begin
  new.country := null;
  new.region := null;
  begin
    h := nullif(current_setting('request.headers', true), '')::jsonb;
    cc := upper(coalesce(h->>'cf-ipcountry', ''));
    if cc !~ '^[A-Z]{2}$' or cc in ('XX', 'T1') then cc := 'XX'; end if;  -- T1 = Tor
    new.country := cc;
    if cc = 'US' then
      v_ip := (h->>'cf-connecting-ip')::inet;
      select g.state into new.region
        from public.geo_ip_state g
        where g.start_ip <= v_ip and family(g.start_ip) = family(v_ip)
        order by g.start_ip desc
        limit 1;
    elsif cc in ('PR', 'GU', 'VI', 'AS', 'MP') then
      new.region := cc;  -- US territories
    end if;
  exception when others then
    new.region := null;  -- never block a visit over geo lookup
  end;
  v_ip := null;
  return new;
end; $$;
revoke all on function public.site_visit_geo() from public, anon, authenticated;
drop trigger if exists site_visits_geo on public.site_visits;
create trigger site_visits_geo before insert on public.site_visits
  for each row execute function public.site_visit_geo();

-- Visits per state, all time or for one month (p_month = first day of the month, Central Time).
-- region: 2-letter state/territory code, 'OUTSIDE_US', or 'UNKNOWN'.
-- SECURITY INVOKER (table RLS applies) and refuses anyone not on the portal allowlist.
create or replace function public.portal_visits_by_state(p_month date default null)
returns table (region text, visits bigint, unique_visitors bigint, tracking_since timestamptz)
language plpgsql stable security invoker set search_path = '' as $$
declare v_since timestamptz;
begin
  if not public.is_portal_user() then raise exception 'not authorized' using errcode = '42501'; end if;
  select min(v.created_at) into v_since from public.site_visits v where v.country is not null;
  return query
    select case
             when v.region is not null then v.region
             when v.country is not null and v.country not in ('US', 'XX') then 'OUTSIDE_US'
             else 'UNKNOWN'
           end as region,
           count(*)::bigint as visits,
           (count(distinct v.visitor_id) + count(*) filter (where v.visitor_id is null))::bigint as unique_visitors,
           v_since as tracking_since
    from public.site_visits v
    where v.country is not null
      and (p_month is null or (date_trunc('month', v.created_at at time zone 'America/Chicago'))::date = p_month)
    group by 1
    order by 2 desc, 1;
end; $$;
revoke all on function public.portal_visits_by_state(date) from public, anon;
grant execute on function public.portal_visits_by_state(date) to authenticated;
