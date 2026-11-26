#!/usr/bin/env python3
"""Rebuild the data for public.geo_ip_state (US IP block -> state) from DB-IP's free
"IP to City Lite" CSV (CC BY 4.0, https://db-ip.com/db/download/ip-to-city-lite). No key needed.

    curl -LO https://download.db-ip.com/free/dbip-city-lite-YYYY-MM.csv.gz
    python3 build_geo_ip_state.py dbip-city-lite-YYYY-MM.csv.gz   # writes geo_chunk*.sql

Then run, in order, against project jhduhnrtvbvfsgdfpymx (SQL editor or the Supabase MCP execute_sql):
    truncate public.geo_ip_state;      -- only when refreshing
    geo_chunk0.sql, geo_chunk1.sql, ...

Size: blocks are generalized to IPv4 /20 and IPv6 /36 (majority state per block), then
consecutive blocks with the same state are merged: ~100k rows, ~8 MB. Lookups are gated on
Cloudflare saying the visitor is in the US, so gaps between US blocks don't matter.
Generated SQL files contain only public IP-range data; don't commit them (they're large).
"""
import collections, csv, gzip, ipaddress, sys

STATES = {"Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA", "Colorado": "CO",
          "Connecticut": "CT", "Delaware": "DE", "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA",
          "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA", "Kansas": "KS",
          "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD", "Massachusetts": "MA",
          "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO", "Montana": "MT",
          "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
          "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH", "Oklahoma": "OK",
          "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
          "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
          "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY"}
TERRITORIES = {"PR", "GU", "VI", "AS", "MP"}  # separate country codes in DB-IP
BITS = {4: 20, 6: 36}
CHUNK_BYTES = 700_000  # Supabase MCP rejects queries over ~1 MB


def main(path):
    ranges = {4: [], 6: []}
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for row in csv.reader(f):
            start, end, _cont, country, region = row[:5]
            if country == "US" and region in STATES:
                code = STATES[region]
            elif country in TERRITORIES:
                code = country
            else:
                continue
            a, b = ipaddress.ip_address(start), ipaddress.ip_address(end)
            ranges[a.version].append((int(a), int(b), code))
    out = []
    for ver, rows in ranges.items():
        shift = (32 if ver == 4 else 128) - BITS[ver]
        partial = collections.defaultdict(collections.Counter)
        pure = []
        for a, b, s in rows:
            p, q = a >> shift, b >> shift
            if p == q:
                partial[p][s] += b - a + 1
                continue
            p1, q1 = p, q
            if a != p << shift:
                partial[p][s] += ((p + 1) << shift) - a; p1 = p + 1
            if b != ((q + 1) << shift) - 1:
                partial[q][s] += b - (q << shift) + 1; q1 = q - 1
            if p1 <= q1:
                pure.append((p1, s))
        blocks = sorted([(k, c.most_common(1)[0][0]) for k, c in partial.items()] + pure)
        cls = ipaddress.IPv4Address if ver == 4 else ipaddress.IPv6Address
        last = None
        for k, s in blocks:
            if s != last:
                out.append(f"{cls(k << shift)} {s}")
                last = s
    chunks, cur, size = [], [], 0
    for item in out:
        if size + len(item) > CHUNK_BYTES:
            chunks.append(cur); cur, size = [], 0
        cur.append(item); size += len(item) + 1
    chunks.append(cur)
    for i, c in enumerate(chunks):
        with open(f"geo_chunk{i}.sql", "w") as f:
            f.write("insert into public.geo_ip_state (start_ip, state) select split_part(x,' ',1)::inet, "
                    "split_part(x,' ',2) from unnest(string_to_array('" + ",".join(c) + "', ',')) x "
                    "on conflict (start_ip) do update set state = excluded.state;\n")
    print(f"{len(out)} rows in {len(chunks)} files")


if __name__ == "__main__":
    main(sys.argv[1])
