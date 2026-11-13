'use strict';
require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const { Pool } = require('pg');
const { validateMapping } = require('./src/integrations/mapping-validator');

const app = express();
app.disable('x-powered-by');
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',').map(s => s.trim()) : true }));
app.use(express.json({ limit: '1mb' }));

const pool = process.env.DATABASE_URL ? new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_SSL === 'false' ? false : { rejectUnauthorized: false },
  max: Number(process.env.PG_POOL_MAX || 10),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000
}) : null;

app.get('/', (_req, res) => res.json({ name: 'GT City Channel Manager v2', status: 'running', version: '2.0.0' }));
app.get('/api/health', async (_req, res) => {
  const result = { status: 'ok', service: 'gt-city-v2', database: 'not_configured', timestamp: new Date().toISOString() };
  if (pool) {
    try { await pool.query('SELECT 1'); result.database = 'connected'; }
    catch (e) { result.status = 'degraded'; result.database = 'error'; result.databaseError = process.env.NODE_ENV === 'development' ? e.message : undefined; }
  }
  res.status(result.status === 'ok' ? 200 : 503).json(result);
});

app.get('/api/meta', (_req, res) => res.json({
  version: '2.0.0',
  modules: ['properties', 'units', 'room-types', 'channel-listings', 'channel-mappings', 'reservations'],
  databaseConfigured: Boolean(pool)
}));

app.post('/api/mappings/validate', (req, res) => {
  const result = validateMapping(req.body);
  res.status(result.valid ? 200 : 400).json(result);
});

app.get('/api/properties', async (_req, res, next) => {
  if (!pool) return res.status(503).json({ error: 'DATABASE_NOT_CONFIGURED', message: 'Render Environment’da DATABASE_URL sozlanmagan.' });
  try {
    const { rows } = await pool.query(`SELECT id, name, property_type, address, city, timezone, currency, status, created_at FROM properties ORDER BY created_at DESC LIMIT 500`);
    res.json({ data: rows });
  } catch (e) { next(e); }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'INTERNAL_SERVER_ERROR', message: 'Serverda ichki xatolik yuz berdi.' });
});

const port = Number(process.env.PORT || 10000);
const server = app.listen(port, '0.0.0.0', () => console.log(`GT City v2 listening on ${port}`));
async function shutdown() { server.close(); if (pool) await pool.end(); process.exit(0); }
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
