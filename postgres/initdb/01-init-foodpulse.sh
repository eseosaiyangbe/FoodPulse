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
  signature_item text NOT NULL,
  energy_score integer NOT NULL CHECK (energy_score BETWEEN 0 AND 100),
  price_band text NOT NULL,
  accent_color text NOT NULL,
  spotlight text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vote_events (
  id bigserial PRIMARY KEY,
  venue_slug text NOT NULL REFERENCES venues(slug) ON DELETE CASCADE,
  voted_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO venues (slug, name, neighborhood, category, signature_item, energy_score, price_band, accent_color, spotlight)
VALUES
  ('greenhouse-kitchen', 'Greenhouse Kitchen', 'Downtown Core', 'Seasonal bowls', 'Citrus tahini crunch bowl', 94, '\$\$', '#0f766e', 'Fast, bright, plant-forward plates built for lunch rush energy.'),
  ('ember-common', 'Ember Common', 'Harbourfront', 'Woodfire grill', 'Charred salmon and herb rice', 88, '\$\$\$', '#f97316', 'Smoke, citrus, and careful technique with a calmer evening tempo.'),
  ('studio-oats', 'Studio Oats', 'West End', 'Breakfast lab', 'Protein oats with berry chia jam', 91, '$', '#8b5cf6', 'An all-day breakfast counter tuned for focused mornings and creator sessions.'),
  ('atlas-garden', 'Atlas Garden', 'Midtown', 'Mediterranean plates', 'Za''atar chicken and lemon couscous', 89, '\$\$', '#2563eb', 'Shared plates with color, herbs, and a social dinner feel.');

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${APP_DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${APP_DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${APP_DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO ${APP_DB_USER};
EOSQL
