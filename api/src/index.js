import os from 'node:os';

import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import pg from 'pg';
import { Counter, Gauge, Registry, collectDefaultMetrics } from 'prom-client';
import { createClient } from 'redis';

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

const redisUrl = `redis://:${encodeURIComponent(
  process.env.FOODPULSE_REDIS_PASSWORD || 'admin',
)}@${process.env.FOODPULSE_REDIS_SERVER || 'redis-haproxy'}:${Number(
  process.env.FOODPULSE_REDIS_PORT || 6379,
)}`;

const pool = new Pool(dbConfig);
const redis = createClient({ url: redisUrl });

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

const allowedOrigin = process.env.FOODPULSE_ALLOWED_ORIGIN || 'http://localhost:8090';

app.use(
  cors({
    origin: [allowedOrigin],
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

async function connectRedis() {
  if (!redis.isOpen) {
    await redis.connect();
  }
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
