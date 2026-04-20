#!/usr/bin/env bash
set -euo pipefail

APP_DB_NAME="${FOODPULSE_DB_NAME:-foodpulse}"
APP_DB_USER="${FOODPULSE_DB_USER:-foodpulse}"
APP_DB_PASSWORD="${FOODPULSE_DB_PASSWORD:-change-me}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_DB_USER}') THEN
    CREATE ROLE ${APP_DB_USER} LOGIN PASSWORD '${APP_DB_PASSWORD}';
  END IF;
END
\$\$;

CREATE DATABASE ${APP_DB_NAME} OWNER ${APP_DB_USER};
\connect ${APP_DB_NAME};

GRANT ALL PRIVILEGES ON DATABASE ${APP_DB_NAME} TO ${APP_DB_USER};
GRANT ALL ON SCHEMA public TO ${APP_DB_USER};
ALTER DATABASE ${APP_DB_NAME} OWNER TO ${APP_DB_USER};
ALTER SCHEMA public OWNER TO ${APP_DB_USER};

CREATE TABLE venues (
  slug text PRIMARY KEY,
  name text NOT NULL,
  neighborhood text NOT NULL,
  category text NOT NULL,
  headline text NOT NULL,
  signature_item text NOT NULL,
  energy_score integer NOT NULL CHECK (energy_score BETWEEN 0 AND 100),
  price_band text NOT NULL,
  accent_color text NOT NULL,
  website_url text NOT NULL,
  spotlight text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vote_events (
  id bigserial PRIMARY KEY,
  venue_slug text NOT NULL REFERENCES venues(slug) ON DELETE CASCADE,
  voted_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO venues (slug, name, neighborhood, category, headline, signature_item, energy_score, price_band, accent_color, website_url, spotlight)
VALUES
  ('naija-jollof', 'Naija Jollof', 'Toronto, Canada', 'Nigerian comfort food', 'Lagos-style jollof energy served like a homecoming.', 'Jollof rice with chicken, plantain, and coleslaw', 94, '\$\$', '#16a34a', 'https://naijajollof.com/', 'Nigerian classics, catering, pickup, and delivery with a warm Toronto community feel.'),
  ('tumerico', 'Tumerico', 'Tucson, Arizona', 'Vegan Latin kitchen', 'Inventive Latin plant-based plates with local heritage ingredients.', 'Fresh vegan tacos and rotating Latin specials', 97, '\$\$', '#f59e0b', 'https://www.tumerico.com/', 'A celebrated Tucson kitchen led by Chef Wendy Garcia with bold vegetarian and vegan flavor.'),
  ('street-taco-beer', 'STREET Taco and Beer Co.', 'Tucson, Arizona', 'Street-style Mexican', 'Tacos, beer, and Tucson street-food swagger in every bite.', 'Street tacos with onion, cilantro, and cold beer', 90, '\$', '#ef4444', 'https://street.restaurant/', 'Authentic street-style tacos, tortas, local beers, and the bacon-wrapped STREET Dog.'),
  ('rooh', 'ROOH', 'San Francisco, Palo Alto, New Delhi', 'Progressive Indian', 'Modern Indian dining with color, technique, and a little theatre.', 'Dahi puri with yogurt mousse and tamarind', 93, '\$\$\$', '#7c3aed', 'https://www.roohrestaurants.com/', 'Progressive Indian menus across San Francisco, Palo Alto, and New Delhi with signature small plates.'),
  ('z-and-y-restaurant', 'Z & Y Restaurant', 'San Francisco Chinatown', 'Szechuan institution', 'Chinatown heat from a chef trusted by presidents.', 'Szechuan fish filet with flaming chili oil', 96, '\$\$', '#dc2626', 'https://www.zandyrestaurant.com/', 'Award-winning authentic Szechuan cuisine from Chef Lijun Han in historic San Francisco Chinatown.'),
  ('pai-northern-thai', 'PAI Northern Thai Kitchen', 'Toronto, Canada', 'Northern Thai', 'Toronto''s Northern Thai favorite with Michelin Guide shine.', 'Khao soi and Northern Thai street-market plates', 95, '\$\$', '#0ea5e9', 'https://www.paitoronto.com/', 'A Michelin Guide Toronto restaurant known for lively Northern Thai cooking and big downtown energy.');

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${APP_DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${APP_DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${APP_DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ${APP_DB_USER};
EOSQL
