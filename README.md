# Brandon Jackson 2028

Campaign site for Brandon Jackson, seeking the Libertarian Party presidential nomination. Home base: California.

This is a single-page static site (`index.html`). Live on GitHub Pages at:

https://canop3n3r.github.io/brandon-jackson-2028/

## Placeholders still to fill in

Before this is treated as an official campaign site, replace these:

- **Volunteer form:** Submissions currently stay on the page only (thank-you message, nothing is emailed or stored). Connect a campaign inbox or form service and restore a real form action.
- **Donate button:** Labeled “Donations opening soon” and disabled. Link a donation processor (Anedot, WinRed, OpenCollective, or a campaign committee page) and remove the disabled state.
- **Paid-for-by line:** Reads “Paid for by Brandon Jackson for President.” Confirm the official committee name and required FEC disclaimer language.
- **Issue planks:** The six issue cards are starter Libertarian copy, not a confirmed personal platform. Edit them to match Brandon’s positions.
- **Contact / social:** Facebook is linked from his public profile. Add official campaign email, additional social accounts, and any formal announcement copy when ready.

## Local preview

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8080
```

## Visitor feedback

A floating **Feedback** button (bottom-right) captures the visitor's screen with html2canvas, lets them draw on it, and sends the annotated PNG plus a comment to Supabase (project `site-feedback`): screenshots go to the private `feedback-screenshots` bucket, rows to `public.site_feedback`. The page only holds the public publishable key; visitors can insert but never read. An `AFTER INSERT` trigger POSTs each new row to the webhook URL stored in Supabase Vault. See `supabase/site_feedback.sql`.
