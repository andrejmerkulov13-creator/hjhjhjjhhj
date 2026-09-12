import pg from 'pg';
import { config } from './config.js';
const { Pool } = pg;
export const pool = new Pool({ connectionString: config.databaseUrl, max: 20, idleTimeoutMillis: 30000, ssl: config.env === 'production' && !config.databaseUrl.includes('@postgres:') ? { rejectUnauthorized: false } : false });
export async function tx(fn) { const client=await pool.connect(); try { await client.query('BEGIN'); const out=await fn(client); await client.query('COMMIT'); return out; } catch(e){ await client.query('ROLLBACK'); throw e; } finally { client.release(); } }
