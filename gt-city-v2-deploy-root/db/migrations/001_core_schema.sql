-- GT City Channel Manager v2 foundation
-- PostgreSQL 14+. Safe to run on a NEW database. Does not alter legacy data.json.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  default_timezone text NOT NULL DEFAULT 'Asia/Tashkent',
  default_currency char(3) NOT NULL DEFAULT 'UZS',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  full_name text NOT NULL,
  email citext,
  role text NOT NULL CHECK (role IN ('admin','manager','owner','housekeeper','staff')),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, email)
);

CREATE TABLE IF NOT EXISTS properties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  owner_user_id uuid REFERENCES users(id),
  name text NOT NULL,
  property_type text NOT NULL CHECK (property_type IN ('apartment_building','hotel','guesthouse','individual_unit','other')),
  address text,
  city text,
  country_code char(2) NOT NULL DEFAULT 'UZ',
  timezone text NOT NULL DEFAULT 'Asia/Tashkent',
  currency char(3) NOT NULL DEFAULT 'UZS',
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_properties_org ON properties(organization_id, status);

CREATE TABLE IF NOT EXISTS room_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  code text NOT NULL,
  name text NOT NULL,
  max_adults smallint NOT NULL DEFAULT 2 CHECK (max_adults > 0),
  max_children smallint NOT NULL DEFAULT 0 CHECK (max_children >= 0),
  inventory_count integer NOT NULL DEFAULT 1 CHECK (inventory_count > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE(property_id, code),
  UNIQUE(id, property_id)
);

CREATE TABLE IF NOT EXISTS units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
  room_type_id uuid REFERENCES room_types(id),
  unit_code text NOT NULL,
  name text NOT NULL,
  unit_kind text NOT NULL CHECK (unit_kind IN ('apartment','hotel_room','villa','bed','other')),
  floor_label text,
  max_guests smallint NOT NULL DEFAULT 2 CHECK (max_guests > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','out_of_service','inactive')),
  owner_share_percent numeric(5,2) CHECK (owner_share_percent BETWEEN 0 AND 100),
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(property_id, unit_code),
  UNIQUE(id, property_id),
  FOREIGN KEY(room_type_id, property_id) REFERENCES room_types(id, property_id)
);
CREATE INDEX IF NOT EXISTS idx_units_property_status ON units(property_id, status);

CREATE TABLE IF NOT EXISTS channels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  display_name text NOT NULL,
  integration_type text NOT NULL CHECK (integration_type IN ('channel_manager','direct_api','ical','manual')),
  active boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS channel_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  channel_id uuid NOT NULL REFERENCES channels(id),
  account_name text NOT NULL,
  provider_name text,
  credentials_secret_ref text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','connected','error','disabled')),
  last_sync_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(organization_id, channel_id, account_name)
);

CREATE TABLE IF NOT EXISTS channel_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_account_id uuid NOT NULL REFERENCES channel_accounts(id) ON DELETE CASCADE,
  external_property_id text,
  external_listing_id text NOT NULL,
  external_room_type_id text,
  listing_name text,
  listing_status text NOT NULL DEFAULT 'active' CHECK (listing_status IN ('active','inactive','unmapped','error')),
  raw_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(channel_account_id, external_listing_id)
);

CREATE TABLE IF NOT EXISTS channel_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES channel_listings(id) ON DELETE CASCADE,
  property_id uuid NOT NULL REFERENCES properties(id),
  mapping_mode text NOT NULL CHECK (mapping_mode IN ('UNIT','ROOM_TYPE','PROPERTY')),
  unit_id uuid,
  room_type_id uuid,
  property_inventory boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','needs_review')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (mapping_mode='UNIT' AND unit_id IS NOT NULL AND room_type_id IS NULL AND property_inventory=false) OR
    (mapping_mode='ROOM_TYPE' AND unit_id IS NULL AND room_type_id IS NOT NULL AND property_inventory=false) OR
    (mapping_mode='PROPERTY' AND unit_id IS NULL AND room_type_id IS NULL AND property_inventory=true)
  ),
  FOREIGN KEY(unit_id, property_id) REFERENCES units(id, property_id),
  FOREIGN KEY(room_type_id, property_id) REFERENCES room_types(id, property_id),
  UNIQUE(listing_id)
);
CREATE INDEX IF NOT EXISTS idx_channel_mappings_property ON channel_mappings(property_id, status);

CREATE TABLE IF NOT EXISTS guests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  full_name text,
  email text,
  phone text,
  phone_visibility text NOT NULL DEFAULT 'unknown' CHECK (phone_visibility IN ('available','masked','unavailable','unknown')),
  email_visibility text NOT NULL DEFAULT 'unknown' CHECK (email_visibility IN ('available','masked','unavailable','unknown')),
  country_code char(2),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_guests_org_email ON guests(organization_id, email);

CREATE TABLE IF NOT EXISTS reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  property_id uuid NOT NULL REFERENCES properties(id),
  unit_id uuid,
  room_type_id uuid,
  guest_id uuid REFERENCES guests(id),
  source_channel_id uuid REFERENCES channels(id),
  check_in date NOT NULL,
  check_out date NOT NULL,
  adults smallint NOT NULL DEFAULT 1 CHECK (adults > 0),
  children smallint NOT NULL DEFAULT 0 CHECK (children >= 0),
  status text NOT NULL CHECK (status IN ('new','confirmed','modified','cancelled','checked_in','checked_out','no_show','inquiry')),
  total_amount numeric(14,2),
  currency char(3),
  commission_amount numeric(14,2),
  special_requests text,
  source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (check_out > check_in),
  CHECK ((unit_id IS NOT NULL AND room_type_id IS NULL) OR (unit_id IS NULL AND room_type_id IS NOT NULL)),
  FOREIGN KEY(unit_id, property_id) REFERENCES units(id, property_id),
  FOREIGN KEY(room_type_id, property_id) REFERENCES room_types(id, property_id)
);
CREATE INDEX IF NOT EXISTS idx_reservations_property_dates ON reservations(property_id, check_in, check_out);
CREATE INDEX IF NOT EXISTS idx_reservations_status_dates ON reservations(status, check_in, check_out);

CREATE TABLE IF NOT EXISTS reservation_external_refs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
  channel_id uuid NOT NULL REFERENCES channels(id),
  external_booking_id text NOT NULL,
  external_status text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(channel_id, external_booking_id),
  UNIQUE(reservation_id, channel_id)
);

CREATE TABLE IF NOT EXISTS unit_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
  unit_id uuid NOT NULL REFERENCES units(id),
  stay daterange NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT isempty(stay)),
  UNIQUE(reservation_id, unit_id),
  EXCLUDE USING gist (unit_id WITH =, stay WITH &&)
);
CREATE INDEX IF NOT EXISTS idx_unit_allocations_unit ON unit_allocations USING gist(unit_id, stay);

CREATE TABLE IF NOT EXISTS reservation_events (
  id bigserial PRIMARY KEY,
  reservation_id uuid NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  source text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS integration_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  channel_account_id uuid REFERENCES channel_accounts(id),
  event_key text NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','processing','processed','failed','ignored')),
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE(channel_account_id, event_key)
);
CREATE INDEX IF NOT EXISTS idx_integration_events_queue ON integration_events(status, next_attempt_at);

CREATE TABLE IF NOT EXISTS sync_logs (
  id bigserial PRIMARY KEY,
  channel_account_id uuid NOT NULL REFERENCES channel_accounts(id),
  object_type text NOT NULL,
  object_id text,
  direction text NOT NULL CHECK (direction IN ('inbound','outbound')),
  status text NOT NULL CHECK (status IN ('success','warning','error')),
  message text,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Seed channel directory; credentials are NEVER stored in this table.
INSERT INTO channels(code, display_name, integration_type) VALUES
 ('booking_com','Booking.com','channel_manager'),
 ('airbnb','Airbnb','channel_manager'),
 ('ostrovok','Ostrovok','direct_api'),
 ('sutochno','Sutochno.ru','direct_api'),
 ('olx','OLX','manual'),
 ('direct','GT City Direct','manual'),
 ('ical','iCal feed','ical')
ON CONFLICT(code) DO NOTHING;
