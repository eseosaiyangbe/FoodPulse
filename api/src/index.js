import os from 'node:os';

import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import Redis from 'ioredis';
import morgan from 'morgan';
import pg from 'pg';
import { Counter, Gauge, Histogram, Registry, collectDefaultMetrics } from 'prom-client';

const { Pool } = pg;

const app = express();
const port = Number(process.env.PORT || 4567);
const dbConfig = {
  host: process.env.FOODPULSE_DB_SERVER || 'pg-haproxy',
  port: Number(process.env.FOODPULSE_DB_PORT || 5432),
  database: process.env.FOODPULSE_DB_NAME || 'foodpulse',
  user: process.env.FOODPULSE_DB_USER || 'foodpulse',
  password: process.env.FOODPULSE_DB_PASSWORD || 'change-me',
};

const pool = new Pool(dbConfig);
const redis = new Redis(buildRedisConfig());

redis.on('error', (error) => {
  console.error('redis error', error.message);
});

const metrics = new Registry();
collectDefaultMetrics({ register: metrics, prefix: 'foodpulse_api_' });

const voteCounter = new Counter({
  name: 'foodpulse_votes_total',
  help: 'Total number of votes submitted through the FoodPulse API.',
  labelNames: ['venue_slug'],
  registers: [metrics],
});

const pageViewGauge = new Gauge({
  name: 'foodpulse_pageviews',
  help: 'Current FoodPulse page view count stored in Redis.',
  registers: [metrics],
});

const venueLeadGauge = new Gauge({
  name: 'foodpulse_leading_venue_votes',
  help: 'Votes for the current leading FoodPulse venue.',
  labelNames: ['venue_slug'],
  registers: [metrics],
});

const httpRequestDuration = new Histogram({
  name: 'foodpulse_http_request_duration_seconds',
  help: 'FoodPulse API HTTP request duration in seconds.',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [metrics],
});

const httpRequestsTotal = new Counter({
  name: 'foodpulse_http_requests_total',
  help: 'Total number of HTTP requests handled by the FoodPulse API.',
  labelNames: ['method', 'route', 'status_code'],
  registers: [metrics],
});

const httpErrorsTotal = new Counter({
  name: 'foodpulse_http_errors_total',
  help: 'Total number of failed HTTP requests handled by the FoodPulse API.',
  labelNames: ['method', 'route', 'status_code', 'error_class'],
  registers: [metrics],
});

const allowedOrigins = (process.env.FOODPULSE_ALLOWED_ORIGIN || 'http://localhost:8090')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.use(
  cors({
    origin: allowedOrigins,
    credentials: false,
  }),
);
app.use(
  helmet({
    crossOriginResourcePolicy: false,
    contentSecurityPolicy: false,
  }),
);
app.use(morgan('tiny'));
app.use(express.json());

function routeLabel(req) {
  if (req.route?.path) {
    return req.route.path;
  }

  return req.path || 'unknown';
}

function errorClass(statusCode) {
  if (statusCode >= 500) {
    return 'server_error';
  }

  if (statusCode >= 400) {
    return 'client_error';
  }

  return 'none';
}

app.use((req, res, next) => {
  const endTimer = httpRequestDuration.startTimer();

  res.on('finish', () => {
    const statusCode = String(res.statusCode);
    const labels = {
      method: req.method,
      route: routeLabel(req),
      status_code: statusCode,
    };

    endTimer(labels);
    httpRequestsTotal.inc(labels);

    if (res.statusCode >= 400) {
      httpErrorsTotal.inc({
        ...labels,
        error_class: errorClass(res.statusCode),
      });
    }
  });

  next();
});

async function connectRedis() {
  if (redis.status === 'ready') {
    return;
  }

  if (redis.status === 'connecting' || redis.status === 'connect') {
    await redis.ping();
    return;
  }

  if (redis.status === 'wait' || redis.status === 'close' || redis.status === 'end') {
    await redis.connect();
  }
}

function parseSentinels(value) {
  return value
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [host, port] = entry.split(':');
      return {
        host,
        port: Number(port || 26379),
      };
    });
}

function buildRedisConfig() {
  const password = process.env.FOODPULSE_REDIS_PASSWORD || 'admin';
  const sentinels = process.env.FOODPULSE_REDIS_SENTINELS;
  const masterName = process.env.FOODPULSE_REDIS_MASTER_NAME || 'foodpulse-cache';

  if (sentinels) {
    return {
      sentinels: parseSentinels(sentinels),
      name: masterName,
      password,
      sentinelPassword: process.env.FOODPULSE_REDIS_SENTINEL_PASSWORD || password,
      connectTimeout: 5000,
      enableReadyCheck: true,
      lazyConnect: true,
      maxRetriesPerRequest: 1,
    };
  }

  return {
    host: process.env.FOODPULSE_REDIS_SERVER || 'redis-haproxy',
    port: Number(process.env.FOODPULSE_REDIS_PORT || 6379),
    password,
    connectTimeout: 5000,
    lazyConnect: true,
    maxRetriesPerRequest: 1,
  };
}

async function incrementPageViews() {
  try {
    await connectRedis();
    const total = await redis.incr('foodpulse:pageviews');
    pageViewGauge.set(total);
    return total;
  } catch (error) {
    console.error('pageview increment failed', error.message);
    return null;
  }
}

async function getPageViews() {
  try {
    await connectRedis();
    const current = Number((await redis.get('foodpulse:pageviews')) || 0);
    pageViewGauge.set(current);
    return current;
  } catch (error) {
    console.error('pageview read failed', error.message);
    return 0;
  }
}

async function fetchVenueRows() {
  const query = `
    SELECT
      v.slug,
      v.name,
      v.neighborhood,
      v.category,
      v.headline,
      v.signature_item,
      v.energy_score,
      v.price_band,
      v.accent_color,
      v.website_url,
      v.spotlight,
      COUNT(ve.id)::int AS votes
    FROM venues v
    LEFT JOIN vote_events ve ON ve.venue_slug = v.slug
    GROUP BY v.slug, v.name, v.neighborhood, v.category, v.signature_item, v.energy_score, v.price_band, v.accent_color, v.spotlight
    ORDER BY votes DESC, v.name ASC
  `;

  const { rows } = await pool.query(query);
  if (rows[0]) {
    venueLeadGauge.reset();
    venueLeadGauge.labels(rows[0].slug).set(rows[0].votes);
  }
  return rows;
}

async function fetchStats() {
  const [pageviews, voteRows] = await Promise.all([
    getPageViews(),
    fetchVenueRows(),
  ]);

  const totalVotes = voteRows.reduce((sum, row) => sum + row.votes, 0);
  const topVenue = voteRows[0] || null;

  return {
    hostname: os.hostname(),
    pageviews,
    totalVotes,
    activeVenueCount: voteRows.length,
    topVenue: topVenue
      ? {
          slug: topVenue.slug,
          name: topVenue.name,
          votes: topVenue.votes,
        }
      : null,
    generatedAt: new Date().toISOString(),
  };
}

async function createVote(venueSlug) {
  const { rowCount } = await pool.query(
    'INSERT INTO vote_events (venue_slug) SELECT slug FROM venues WHERE slug = $1',
    [venueSlug],
  );

  if (!rowCount) {
    const error = new Error('unknown venue');
    error.statusCode = 404;
    throw error;
  }

  voteCounter.labels(venueSlug).inc();
  const [stats, venues] = await Promise.all([fetchStats(), fetchVenueRows()]);
  const venue = venues.find((row) => row.slug === venueSlug);

  return {
    ok: true,
    venue: venue
      ? {
          slug: venue.slug,
          name: venue.name,
          votes: venue.votes,
        }
      : null,
    stats,
  };
}

async function runHealthCheck() {
  const checks = {
    database: false,
    cache: false,
  };

  try {
    await pool.query('SELECT 1');
    checks.database = true;
  } catch (error) {
    console.error('database health check failed', error.message);
  }

  try {
    await connectRedis();
    await redis.ping();
    checks.cache = true;
  } catch (error) {
    console.error('cache health check failed', error.message);
  }

  return {
    status: checks.database && checks.cache ? 'healthy' : 'degraded',
    checks,
    hostname: os.hostname(),
  };
}

function toLegacyVotes(rows) {
  return rows.map((row) => ({
    name: row.slug,
    label: row.name,
    value: row.votes,
  }));
}

app.get('/health', async (_req, res) => {
  const health = await runHealthCheck();
  res.status(health.status === 'healthy' ? 200 : 503).json(health);
});

app.get('/api/health', async (_req, res) => {
  const health = await runHealthCheck();
  res.status(health.status === 'healthy' ? 200 : 503).json(health);
});

app.get('/api/venues', async (_req, res, next) => {
  try {
    const venues = await fetchVenueRows();
    res.json({ venues });
  } catch (error) {
    next(error);
  }
});

app.post('/api/pageviews', async (_req, res, next) => {
  try {
    const total = await incrementPageViews();
    res.status(201).json({ pageviews: total ?? 0 });
  } catch (error) {
    next(error);
  }
});

app.get('/api/pageviews', async (_req, res, next) => {
  try {
    const total = await getPageViews();
    res.json(total);
  } catch (error) {
    next(error);
  }
});

app.get('/api/hostname', (_req, res) => {
  res.json(os.hostname());
});

app.get('/api/getstats', async (_req, res, next) => {
  try {
    const stats = await fetchStats();
    res.json(stats);
  } catch (error) {
    next(error);
  }
});

app.get('/api/getvotes', async (_req, res, next) => {
  try {
    const venues = await fetchVenueRows();
    res.json(toLegacyVotes(venues));
  } catch (error) {
    next(error);
  }
});

app.post('/api/vote', async (req, res, next) => {
  try {
    const venueSlug = req.body.venueSlug || req.body.restaurant;
    if (!venueSlug) {
      return res.status(400).json({ error: 'venueSlug is required' });
    }
    const result = await createVote(venueSlug);
    return res.status(201).json(result);
  } catch (error) {
    return next(error);
  }
});

app.get('/api/vote', async (req, res, next) => {
  try {
    const venueSlug = req.query.venueSlug || req.query.restaurant;
    if (!venueSlug) {
      return res.status(400).json({ error: 'venueSlug query parameter is required' });
    }
    const result = await createVote(String(venueSlug));
    return res.json(result);
  } catch (error) {
    return next(error);
  }
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', metrics.contentType);
  res.end(await metrics.metrics());
});

app.use((error, _req, res, _next) => {
  const statusCode = error.statusCode || 500;
  console.error('foodpulse api error', error);
  res.status(statusCode).json({
    error: error.message || 'internal server error',
  });
});

async function start() {
  const maxAttempts = 20;

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      await pool.query('SELECT 1');
      await connectRedis();
      await getPageViews();
      app.listen(port, () => {
        console.log(`foodpulse-api listening on ${port}`);
      });
      return;
    } catch (error) {
      console.error(`foodpulse-api startup dependency check failed (${attempt}/${maxAttempts})`, error.message);

      if (attempt === maxAttempts) {
        console.error('foodpulse-api failed to start', error);
        process.exit(1);
      }

      await new Promise((resolve) => {
        setTimeout(resolve, 3000);
      });
    }
  }
}

start();
