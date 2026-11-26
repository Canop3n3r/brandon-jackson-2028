# Brandon Jackson 2028

Campaign site for Brandon Jackson, seeking the Libertarian Party presidential nomination. Home base: California.

This is a single-page static site (`index.html`). Live at:

https://jacksonforliberty.com/

## Placeholders still to fill in

Before this is treated as an official campaign site, replace these:

- **Volunteer form:** Submissions are emailed to info@jacksonforliberty.com through FormSubmit's AJAX endpoint. The first submission to that address sends an activation email; someone with access to the inbox needs to click Activate before further signups are delivered. After activation, FormSubmit also provides a random alias that can replace the visible address in the page source.
- **Donate button:** Labeled “Donations opening soon” and disabled. Link a donation processor (Anedot, WinRed, OpenCollective, or a campaign committee page) and remove the disabled state.
- **Paid-for-by line:** Reads “Paid for by Brandon Jackson for President.” Confirm the official committee name and required FEC disclaimer language.
- **Issue planks:** The six issue cards are starter Libertarian copy, not a confirmed personal platform. Edit them to match Brandon’s positions.
- **Contact / social:** Campaign email is info@jacksonforliberty.com. Facebook is linked from his public profile. Add additional social accounts and any formal announcement copy when ready.

## Campaign portal

`/portal/` is a private, noindexed page where the campaign team signs in with a one-time email link (Supabase Auth, no password) and chats with Aaron's assistant about site changes. Only allowlisted emails can sign in. Messages live in the Supabase table `public.portal_messages`, protected by Row Level Security; the page ships only the public anon key. Tabs, in order: **Chat** (requests to the assistant), **Signups** (volunteer signups with CSV download, plus a **By state** view, state filter, and per-state CSV), **Visits** (monthly page loads, plus a **By state** view), and **Team** (who can sign in). Team always stays last; add new tab buttons above the marked comment in `portal/index.html`. **Chat is private to Brandon and Aaron:** RLS on `public.portal_messages` only allows emails in `public.portal_chat_access`, a table with no client grants that no portal RPC can edit, so adding someone on the Team tab never grants chat access (see `supabase/portal_chat_lock.sql`). Brandon's and Aaron's addresses can't be removed from Team. The volunteer form still emails info@ through FormSubmit and also saves a copy (name, email, city/state, interests; no message text) to `public.signups`, which the public can insert into but not read. Schema reference: `supabase/portal_messages.sql` and `supabase/portal_team_signups.sql`.

**States.** Signups by state are parsed in the portal from the free-text city/state (2-letter codes, full names, common abbreviations; anything else is "Unknown"). The volunteer form now has a separate State dropdown; it's combined with City into the same `location` / `city_state` value ("Austin, TX"), so the FormSubmit email and the database column are unchanged. Visits by state (from 2026-11-26) are added server-side by a trigger on `public.site_visits`: it reads Cloudflare's `cf-ipcountry` and `cf-connecting-ip` request headers, looks the IP up in `public.geo_ip_state` (a local, client-unreadable copy of the free [DB-IP IP to City Lite](https://db-ip.com/db/download/ip-to-city-lite) data, CC BY 4.0, reduced to US-state blocks), and saves only the 2-letter country and state, never the IP. No outside service is called at visit time. Refresh the lookup data now and then with `supabase/geo/build_geo_ip_state.py` (see `supabase/visits_by_state.sql`).

## Search and link previews

`index.html` sets Open Graph / Twitter card tags and schema.org JSON-LD pointing at `assets/og-image.png` (1200x630, built from the homepage's gold star seal, `assets/seal.svg`). Favicons and the apple-touch icon are generated from the same seal.

## Local preview

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8080
```
