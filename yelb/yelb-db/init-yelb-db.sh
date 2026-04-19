#!/bin/bash
set -e

DB_NAME="${FOODPULSE_DB_NAME:-${YELB_DB_NAME:-foodpulse}}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE ${DB_NAME};
    \connect ${DB_NAME};
	CREATE TABLE restaurants (
    	name        char(30),
    	count       integer,
    	PRIMARY KEY (name)
	);
	INSERT INTO restaurants (name, count) VALUES ('outback', 0);
	INSERT INTO restaurants (name, count) VALUES ('bucadibeppo', 0);
	INSERT INTO restaurants (name, count) VALUES ('chipotle', 0);
	INSERT INTO restaurants (name, count) VALUES ('ihop', 0);
EOSQL
