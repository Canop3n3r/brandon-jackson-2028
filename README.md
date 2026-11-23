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

`/portal/` is a private, noindexed page where the campaign team signs in with a one-time email link (Supabase Auth, no password) and chats with Aaron's assistant about site changes. Only allowlisted emails can sign in. Messages live in the Supabase table `public.portal_messages`, protected by Row Level Security; the page ships only the public anon key. Schema reference: `supabase/portal_messages.sql`.

## Local preview

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8080
```
