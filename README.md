# 7 Imports Card Finder — Starter Project

A development starter for a separate customer-facing card finder and staff application.

## Chosen stack
- Next.js (App Router) + TypeScript
- Supabase Postgres + Auth + Row Level Security
- Scryfall catalog integration for Magic: The Gathering card identity/printing data
- External market-pricing provider behind a replaceable adapter (not wired to a paid provider yet)

## Included
- Initial Supabase schema for games, card identities, printings, inventory variants, reservations, price approvals, scan sessions, and audit history.
- A public landing/search shell.
- Environment variable template.
- Setup and security notes.

## Important status
This is a **starter codebase**, not a deployed or production-ready store system. It contains no real inventory, credentials, live market-price connection, camera-recognition service, SMS/email provider, or payment processing. Do not enter customer data or rely on it for live reservations until the remaining implementation, security review, and testing are complete.

## Local setup
1. Install Node.js 20 or later.
2. Create a Supabase project.
3. Copy `.env.example` to `.env.local` and fill in the Supabase URL and anon key.
4. In Supabase SQL Editor, run `supabase/migrations/001_initial_schema.sql`.
5. Install dependencies with `npm install`.
6. Run `npm run dev` and open http://localhost:3000.

## Next implementation milestones
1. Add secure owner/employee invitation and role management.
2. Add authenticated inventory-entry and owner price-approval screens.
3. Add Scryfall bulk catalog import and exact-printing selection.
4. Add market-price provider adapter and owner review queue.
5. Add transactional guest reservations with 24-hour expiration and pickup workflow.
6. Add scanning review queue (camera capture first; recognition must require employee confirmation).
7. Add SMS/email notifications with consent and opt-out.
8. Add automated tests, rate limits, backups, monitoring, and deployment.

## Business rules captured
- Games: MTG, Pokémon, One Piece, Yu-Gi-Oh!, Disney Lorcana, Dragon Ball Super, Riftbound, Gundam.
- Singles only.
- Group identical copies by printing + condition + finish + language.
- Public search shows only active, owner-priced inventory (through a filtered database view).
- Database trigger prevents employees from changing retail or market price fields.
- Employees may update stock/condition details but cannot change retail prices.
- Owner manually approves every suggested price.
- Missing market reference => listing remains pending until owner enters a price.
- Guest reservations; name and phone required; email optional.
- 24-hour hold; pay in store at pickup; no online payment collection.
- Customer accounts optional.
