-- 7 Imports Card Finder initial schema.
-- Apply in a new Supabase project. Review with a developer before production use.
create extension if not exists pgcrypto;

create type public.app_role as enum ('owner', 'employee');
create type public.card_condition as enum ('NM', 'LP', 'MP', 'HP', 'DMG');
create type public.inventory_status as enum ('pending_pricing', 'active', 'inactive');
create type public.reservation_status as enum ('reserved', 'picked_up', 'canceled', 'expired');

create table public.games (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.games (slug, name) values
 ('mtg','Magic: The Gathering'), ('pokemon','Pokémon'), ('one-piece','One Piece'),
 ('yugioh','Yu-Gi-Oh!'), ('lorcana','Disney Lorcana'), ('dragon-ball-super','Dragon Ball Super'),
 ('riftbound','Riftbound'), ('gundam','Gundam')
on conflict (slug) do nothing;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role public.app_role not null default 'employee',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.cards (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id),
  external_catalog_id text,
  canonical_name text not null,
  searchable_name text generated always as (lower(canonical_name)) stored,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (game_id, external_catalog_id)
);

create index cards_search_idx on public.cards using gin (to_tsvector('simple', canonical_name));

create table public.printings (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  set_code text,
  set_name text,
  collector_number text,
  rarity text,
  language text not null default 'English',
  artwork_url text,
  finish_options text[] not null default array['nonfoil'],
  external_printing_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (card_id, external_printing_id)
);

create table public.inventory_variants (
  id uuid primary key default gen_random_uuid(),
  printing_id uuid not null references public.printings(id),
  condition public.card_condition not null,
  finish text not null,
  language text not null default 'English',
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  quantity_reserved integer not null default 0 check (quantity_reserved >= 0),
  retail_price_cents integer check (retail_price_cents is null or retail_price_cents >= 0),
  market_price_cents integer check (market_price_cents is null or market_price_cents >= 0),
  market_source text,
  market_checked_at timestamptz,
  status public.inventory_status not null default 'pending_pricing',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (printing_id, condition, finish, language),
  check (quantity_reserved <= quantity_on_hand)
);

create view public.public_available_inventory
with (security_invoker = false) as
select
  iv.id as inventory_variant_id,
  c.canonical_name,
  g.name as game_name,
  p.set_name,
  p.set_code,
  p.collector_number,
  p.rarity,
  p.artwork_url,
  iv.condition,
  iv.finish,
  iv.language,
  (iv.quantity_on_hand - iv.quantity_reserved) as quantity_available,
  iv.retail_price_cents
from public.inventory_variants iv
join public.printings p on p.id = iv.printing_id
join public.cards c on c.id = p.card_id
join public.games g on g.id = c.game_id
where iv.status = 'active'
  and iv.retail_price_cents is not null
  and iv.quantity_on_hand > iv.quantity_reserved;



-- Enforce owner-only pricing at the database layer, not just in the user interface.
create or replace function public.guard_inventory_price_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role public.app_role;
  is_service boolean;
begin
  is_service := coalesce(auth.role(), '') = 'service_role';
  actor_role := public.current_app_role();

  if tg_op = 'INSERT' then
    if not is_service and actor_role is distinct from 'owner' then
      new.retail_price_cents := null;
      new.market_price_cents := null;
      new.market_source := null;
      new.market_checked_at := null;
      new.status := 'pending_pricing';
    end if;
    return new;
  end if;

  if not is_service and actor_role is distinct from 'owner' then
    if new.retail_price_cents is distinct from old.retail_price_cents
       or new.market_price_cents is distinct from old.market_price_cents
       or new.market_source is distinct from old.market_source
       or new.market_checked_at is distinct from old.market_checked_at then
      raise exception 'Only an owner or trusted server integration may change pricing fields';
    end if;
  end if;

  return new;
end;
$$;

create trigger inventory_price_guard
before insert or update on public.inventory_variants
for each row execute function public.guard_inventory_price_changes();

-- The public view intentionally exposes only active, priced, in-stock listings.
grant select on public.public_available_inventory to anon, authenticated;

create table public.price_approvals (
  id uuid primary key default gen_random_uuid(),
  inventory_variant_id uuid not null references public.inventory_variants(id) on delete cascade,
  suggested_price_cents integer check (suggested_price_cents is null or suggested_price_cents >= 0),
  market_price_cents integer check (market_price_cents is null or market_price_cents >= 0),
  market_source text,
  market_checked_at timestamptz,
  approved_price_cents integer check (approved_price_cents is null or approved_price_cents >= 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  email text,
  auth_user_id uuid references auth.users(id),
  sms_consent_at timestamptz,
  email_consent_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.reservations (
  id uuid primary key default gen_random_uuid(),
  confirmation_code text unique not null default upper(substr(encode(gen_random_bytes(8),'hex'),1,10)),
  customer_id uuid not null references public.customers(id),
  status public.reservation_status not null default 'reserved',
  expires_at timestamptz not null default (now() + interval '24 hours'),
  created_at timestamptz not null default now(),
  picked_up_at timestamptz,
  canceled_at timestamptz
);

create table public.reservation_items (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  inventory_variant_id uuid not null references public.inventory_variants(id),
  quantity integer not null check (quantity > 0),
  unit_price_cents integer not null check (unit_price_cents >= 0)
);

create table public.scan_sessions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references auth.users(id),
  game_id uuid not null references public.games(id),
  mode text not null check (mode in ('individual','bulk')),
  status text not null default 'in_progress',
  scanned_count integer not null default 0,
  needs_review_count integer not null default 0,
  created_at timestamptz not null default now(),
  submitted_at timestamptz
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  inventory_variant_id uuid not null references public.inventory_variants(id),
  employee_id uuid references auth.users(id),
  movement_type text not null,
  quantity_delta integer not null,
  note text,
  created_at timestamptz not null default now()
);

-- Role helper. Profiles are created/invited by a trusted owner workflow, not public signup.
create or replace function public.current_app_role()
returns public.app_role
language sql stable security definer
set search_path = public
as $$
  select role from public.profiles
  where user_id = auth.uid() and active = true
  limit 1;
$$;

alter table public.games enable row level security;
alter table public.cards enable row level security;
alter table public.printings enable row level security;
alter table public.inventory_variants enable row level security;
alter table public.profiles enable row level security;
alter table public.price_approvals enable row level security;
alter table public.customers enable row level security;
alter table public.reservations enable row level security;
alter table public.reservation_items enable row level security;
alter table public.scan_sessions enable row level security;
alter table public.inventory_movements enable row level security;

-- Public catalog metadata may be read; customer-facing stock is exposed through the approved view.
create policy "public read enabled games" on public.games for select using (enabled);
create policy "public read cards" on public.cards for select using (true);
create policy "public read printings" on public.printings for select using (true);

-- Staff inventory access. Price changes are deliberately excluded from employee update policy;
-- production should enforce this with column-level grants and audited owner-only RPCs.
create policy "staff read inventory" on public.inventory_variants
for select using (public.current_app_role() in ('owner','employee'));
create policy "staff insert inventory" on public.inventory_variants
for insert with check (public.current_app_role() in ('owner','employee'));
create policy "staff update inventory" on public.inventory_variants
for update using (public.current_app_role() in ('owner','employee'))
with check (public.current_app_role() in ('owner','employee'));

create policy "staff read own profile" on public.profiles
for select using (user_id = auth.uid() or public.current_app_role() = 'owner');

create policy "owner manage price approvals" on public.price_approvals
for all using (public.current_app_role() = 'owner')
with check (public.current_app_role() = 'owner');

create policy "staff read customers" on public.customers
for select using (public.current_app_role() in ('owner','employee'));
create policy "staff read reservations" on public.reservations
for select using (public.current_app_role() in ('owner','employee'));
create policy "staff read reservation items" on public.reservation_items
for select using (public.current_app_role() in ('owner','employee'));
create policy "staff read scan sessions" on public.scan_sessions
for select using (public.current_app_role() in ('owner','employee'));
create policy "staff manage scan sessions" on public.scan_sessions
for all using (public.current_app_role() in ('owner','employee'))
with check (public.current_app_role() in ('owner','employee'));
create policy "staff read movements" on public.inventory_movements
for select using (public.current_app_role() in ('owner','employee'));

-- NOTE: Guest reservation creation must be implemented through a server-side, rate-limited
-- endpoint or narrowly scoped RPC that validates contact data, stock, expiry, and consent.
-- Do not expose direct anonymous INSERT access to customers/reservations/reservation_items.
-- Do not expose service-role credentials to the browser.
