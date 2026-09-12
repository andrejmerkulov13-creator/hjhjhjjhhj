#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-tuff-casino}"
mkdir -p "$ROOT"/{frontend,backend/src/{controllers,middleware,routes,services/payments,utils},database/migrations}

cat > "$ROOT/.env.example" <<'EOF'
NODE_ENV=development
PORT=3000
APP_ORIGIN=http://localhost:3000
TRUST_PROXY=1

POSTGRES_DB=tuff
POSTGRES_USER=tuff
POSTGRES_PASSWORD=change_me
DATABASE_URL=postgresql://tuff:change_me@postgres:5432/tuff

TELEGRAM_BOT_TOKEN=
SESSION_SECRET=
SESSION_TTL_DAYS=30
TELEGRAM_AUTH_MAX_AGE_SECONDS=86400

TEST_MODE=true
DEV_BYPASS_TELEGRAM=false
DEV_TELEGRAM_USER_ID=999001
DEV_TELEGRAM_USER_NAME=Local Developer

CURRENCY=USDT
CURRENCY_SCALE=6
STARTING_TEST_BALANCE=100000000

PAYMENT_PROVIDER=mock
PAYMENT_API_KEY=
PAYMENT_WEBHOOK_SECRET=
PAYMENT_ALLOWED_ASSETS=USDT_TRC20,USDT_ERC20

RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX=180
FINANCE_RATE_LIMIT_MAX=30
LOG_LEVEL=info
EOF

cat > "$ROOT/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-tuff}
      POSTGRES_USER: ${POSTGRES_USER:-tuff}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-change_me}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-tuff} -d ${POSTGRES_DB:-tuff}"]
      interval: 5s
      timeout: 5s
      retries: 20

  backend:
    build: ./backend
    restart: unless-stopped
    env_file: .env
    environment:
      DATABASE_URL: ${DATABASE_URL:-postgresql://tuff:change_me@postgres:5432/tuff}
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "127.0.0.1:${PORT:-3000}:3000"

volumes:
  postgres_data:
EOF

cat > "$ROOT/nginx.conf.example" <<'EOF'
server {
    listen 80;
    server_name casino.example.com;
    return 301 https://$host$request_uri;
}
server {
    listen 443 ssl http2;
    server_name casino.example.com;

    ssl_certificate /etc/letsencrypt/live/casino.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/casino.example.com/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    client_max_body_size 1m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

cat > "$ROOT/backend/package.json" <<'EOF'
{
  "name": "tuff-casino-backend",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js",
    "migrate": "node src/migrate.js"
  },
  "engines": { "node": ">=20" },
  "dependencies": {
    "cookie-parser": "^1.4.7",
    "cors": "^2.8.5",
    "dotenv": "^16.4.7",
    "express": "^4.21.2",
    "express-rate-limit": "^7.5.0",
    "helmet": "^8.0.0",
    "pg": "^8.13.1",
    "pino": "^9.6.0",
    "pino-http": "^10.4.0",
    "zod": "^3.24.2"
  }
}
EOF

cat > "$ROOT/backend/Dockerfile" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY ../database /database
COPY ../frontend /frontend
ENV NODE_ENV=production PORT=3000
EXPOSE 3000
CMD ["sh", "-c", "node src/migrate.js && node src/server.js"]
EOF

cat > "$ROOT/backend/.dockerignore" <<'EOF'
node_modules
npm-debug.log
.env
EOF

cat > "$ROOT/backend/src/config.js" <<'EOF'
import 'dotenv/config';
const int = (name, fallback) => Number.parseInt(process.env[name] || String(fallback), 10);
const bool = (name, fallback = false) => (process.env[name] ?? String(fallback)).toLowerCase() === 'true';
export const config = Object.freeze({
  env: process.env.NODE_ENV || 'development',
  port: int('PORT', 3000),
  appOrigin: process.env.APP_ORIGIN || 'http://localhost:3000',
  trustProxy: int('TRUST_PROXY', 1),
  databaseUrl: process.env.DATABASE_URL || '',
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || '',
  telegramMaxAge: int('TELEGRAM_AUTH_MAX_AGE_SECONDS', 86400),
  sessionSecret: process.env.SESSION_SECRET || '',
  sessionTtlDays: int('SESSION_TTL_DAYS', 30),
  testMode: bool('TEST_MODE', true),
  devBypassTelegram: bool('DEV_BYPASS_TELEGRAM', false),
  devTelegramId: process.env.DEV_TELEGRAM_USER_ID || '999001',
  devTelegramName: process.env.DEV_TELEGRAM_USER_NAME || 'Local Developer',
  currency: process.env.CURRENCY || 'USDT',
  currencyScale: int('CURRENCY_SCALE', 6),
  startingTestBalance: BigInt(process.env.STARTING_TEST_BALANCE || '100000000'),
  paymentProvider: process.env.PAYMENT_PROVIDER || 'mock',
  paymentApiKey: process.env.PAYMENT_API_KEY || '',
  paymentWebhookSecret: process.env.PAYMENT_WEBHOOK_SECRET || '',
  paymentAllowedAssets: (process.env.PAYMENT_ALLOWED_ASSETS || 'USDT_TRC20,USDT_ERC20').split(',').map(x => x.trim()).filter(Boolean),
  rateWindowMs: int('RATE_LIMIT_WINDOW_MS', 60000),
  rateMax: int('RATE_LIMIT_MAX', 180),
  financeRateMax: int('FINANCE_RATE_LIMIT_MAX', 30),
  logLevel: process.env.LOG_LEVEL || 'info'
});
if (!config.databaseUrl) throw new Error('DATABASE_URL is required');
if (!config.testMode && (!config.telegramBotToken || !config.sessionSecret)) throw new Error('Production requires TELEGRAM_BOT_TOKEN and SESSION_SECRET');
if (!config.testMode && config.paymentProvider === 'mock') throw new Error('PAYMENT_PROVIDER=mock is forbidden outside TEST_MODE');
EOF

cat > "$ROOT/backend/src/utils/money.js" <<'EOF'
import { config } from '../config.js';
export function parseUnits(value, scale = config.currencyScale) {
  const text = String(value).trim();
  if (!/^\d+(\.\d+)?$/.test(text)) throw new Error('Invalid monetary amount');
  const [whole, fraction = ''] = text.split('.');
  if (fraction.length > scale) throw new Error(`Maximum ${scale} decimal places`);
  return BigInt(whole) * 10n ** BigInt(scale) + BigInt((fraction + '0'.repeat(scale)).slice(0, scale));
}
export function formatUnits(value, scale = config.currencyScale) {
  const n = BigInt(value); const base = 10n ** BigInt(scale);
  const whole = n / base; const fraction = (n % base).toString().padStart(scale, '0').replace(/0+$/, '');
  return fraction ? `${whole}.${fraction}` : whole.toString();
}
export const jsonMoney = value => formatUnits(value);
EOF

cat > "$ROOT/backend/src/utils/crypto.js" <<'EOF'
import crypto from 'node:crypto';
export const randomToken = (bytes = 32) => crypto.randomBytes(bytes).toString('base64url');
export const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
export const hmacHex = (secret, value) => crypto.createHmac('sha256', secret).update(value).digest('hex');
export const safeEqualHex = (a, b) => { try { const x=Buffer.from(a,'hex'), y=Buffer.from(b,'hex'); return x.length===y.length && crypto.timingSafeEqual(x,y); } catch { return false; } };
export const secureInt = max => crypto.randomInt(0, max);
EOF

cat > "$ROOT/backend/src/utils/http.js" <<'EOF'
export class HttpError extends Error { constructor(status, message, code='ERROR'){ super(message); this.status=status; this.code=code; } }
export const asyncRoute = fn => (req,res,next) => Promise.resolve(fn(req,res,next)).catch(next);
EOF

cat > "$ROOT/backend/src/db.js" <<'EOF'
import pg from 'pg';
import { config } from './config.js';
const { Pool } = pg;
export const pool = new Pool({ connectionString: config.databaseUrl, max: 20, idleTimeoutMillis: 30000, ssl: config.env === 'production' && !config.databaseUrl.includes('@postgres:') ? { rejectUnauthorized: false } : false });
export async function tx(fn) { const client=await pool.connect(); try { await client.query('BEGIN'); const out=await fn(client); await client.query('COMMIT'); return out; } catch(e){ await client.query('ROLLBACK'); throw e; } finally { client.release(); } }
EOF

cat > "$ROOT/backend/src/services/telegram.js" <<'EOF'
import crypto from 'node:crypto';
import { config } from '../config.js';
import { HttpError } from '../utils/http.js';
export function validateTelegramInitData(initData) {
  if (config.testMode && config.devBypassTelegram && !initData) return { id: config.devTelegramId, first_name: config.devTelegramName, username: 'local_dev' };
  if (!config.telegramBotToken) throw new HttpError(503, 'Telegram bot token is not configured', 'TELEGRAM_NOT_CONFIGURED');
  if (!initData) throw new HttpError(401, 'Telegram initData is missing', 'BAD_TELEGRAM_DATA');
  const params=new URLSearchParams(initData); const received=params.get('hash'); if(!received) throw new HttpError(401,'Telegram hash is missing');
  params.delete('hash'); const dataCheck=[...params.entries()].sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>`${k}=${v}`).join('\n');
  const secret=crypto.createHmac('sha256','WebAppData').update(config.telegramBotToken).digest();
  const calculated=crypto.createHmac('sha256',secret).update(dataCheck).digest('hex');
  const a=Buffer.from(received,'hex'),b=Buffer.from(calculated,'hex'); if(a.length!==b.length||!crypto.timingSafeEqual(a,b)) throw new HttpError(401,'Invalid Telegram signature','BAD_TELEGRAM_SIGNATURE');
  const authDate=Number(params.get('auth_date')); if(!authDate||Math.abs(Date.now()/1000-authDate)>config.telegramMaxAge) throw new HttpError(401,'Telegram authorization data expired','TELEGRAM_DATA_EXPIRED');
  let user; try { user=JSON.parse(params.get('user')); } catch { throw new HttpError(401,'Invalid Telegram user'); }
  if(!user?.id) throw new HttpError(401,'Telegram user ID is missing'); return user;
}
EOF

cat > "$ROOT/backend/src/services/session.js" <<'EOF'
import { tx } from '../db.js';
import { config } from '../config.js';
import { randomToken, sha256 } from '../utils/crypto.js';
export async function createOrRefreshUser(telegramUser) {
  return tx(async c => {
    const user=(await c.query(`INSERT INTO users(telegram_id,username,first_name,last_name,language_code,last_login_at)
      VALUES($1,$2,$3,$4,$5,now()) ON CONFLICT(telegram_id) DO UPDATE SET username=EXCLUDED.username,first_name=EXCLUDED.first_name,last_name=EXCLUDED.last_name,language_code=EXCLUDED.language_code,last_login_at=now(),updated_at=now() RETURNING *`,
      [String(telegramUser.id),telegramUser.username||null,telegramUser.first_name||'',telegramUser.last_name||'',telegramUser.language_code||null])).rows[0];
    await c.query(`INSERT INTO wallets(user_id,currency,balance_minor) VALUES($1,$2,$3) ON CONFLICT(user_id,currency) DO NOTHING`,[user.id,config.currency,config.testMode?config.startingTestBalance.toString():'0']);
    await c.query(`INSERT INTO user_missions(user_id,mission_code,status) SELECT $1,code,'active' FROM missions WHERE enabled=true ON CONFLICT DO NOTHING`,[user.id]);
    const token=randomToken(); const tokenHash=sha256(token); const expires=new Date(Date.now()+config.sessionTtlDays*86400000);
    await c.query(`INSERT INTO sessions(user_id,token_hash,expires_at) VALUES($1,$2,$3)`,[user.id,tokenHash,expires]);
    return { user, token, expires };
  });
}
export async function getSessionPayload(c,userId){
  const user=(await c.query(`SELECT id,telegram_id,username,first_name,last_name FROM users WHERE id=$1`,[userId])).rows[0];
  const wallet=(await c.query(`SELECT currency,balance_minor FROM wallets WHERE user_id=$1 AND currency=$2`,[userId,config.currency])).rows[0];
  const stats=(await c.query(`SELECT count(*)::int rounds,COALESCE(sum(amount_minor),0)::text wagered,COALESCE(sum(payout_minor),0)::text won FROM bets WHERE user_id=$1`,[userId])).rows[0];
  const gameHistory=(await c.query(`SELECT b.id,g.name game_name,b.amount_minor,b.payout_minor,(b.payout_minor-b.amount_minor)::text net,b.created_at FROM bets b JOIN games g ON g.id=b.game_id WHERE b.user_id=$1 ORDER BY b.created_at DESC LIMIT 20`,[userId])).rows;
  const paymentHistory=(await c.query(`SELECT id,external_id,method,asset,network,amount_minor,status,created_at FROM payments WHERE user_id=$1 ORDER BY created_at DESC LIMIT 20`,[userId])).rows;
  return {user:{id:user.id,telegramId:user.telegram_id,username:user.username,name:[user.first_name,user.last_name].filter(Boolean).join(' ')},wallet:{currency:wallet.currency,available:wallet.balance_minor},stats,gameHistory:gameHistory.map(x=>({gameName:x.game_name,amount:x.amount_minor,payout:x.payout_minor,net:x.net,createdAt:x.created_at})),paymentHistory};
}
EOF

cat > "$ROOT/backend/src/middleware/auth.js" <<'EOF'
import { pool } from '../db.js';
import { sha256 } from '../utils/crypto.js';
import { HttpError, asyncRoute } from '../utils/http.js';
export const requireAuth=asyncRoute(async(req,res,next)=>{const token=req.cookies?.tuff_session;if(!token)throw new HttpError(401,'Authentication required','AUTH_REQUIRED');const row=(await pool.query(`SELECT s.user_id FROM sessions s WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now()`,[sha256(token)])).rows[0];if(!row)throw new HttpError(401,'Session expired','SESSION_EXPIRED');req.userId=row.user_id;next()});
EOF

cat > "$ROOT/backend/src/middleware/idempotency.js" <<'EOF'
import { HttpError } from '../utils/http.js';
export function keyFrom(req){const key=req.get('Idempotency-Key');if(!key||key.length<16||key.length>200)throw new HttpError(400,'Valid Idempotency-Key is required','IDEMPOTENCY_KEY_REQUIRED');return key;}
export async function findIdempotency(c,userId,scope,key){return (await c.query(`SELECT response_status,response_body FROM idempotency_keys WHERE user_id=$1 AND scope=$2 AND idempotency_key=$3`,[userId,scope,key])).rows[0]||null}
export async function saveIdempotency(c,userId,scope,key,status,body){await c.query(`INSERT INTO idempotency_keys(user_id,scope,idempotency_key,response_status,response_body) VALUES($1,$2,$3,$4,$5)`,[userId,scope,key,status,body]);}
EOF

cat > "$ROOT/backend/src/services/game.js" <<'EOF'
import { tx } from '../db.js';
import { config } from '../config.js';
import { parseUnits, formatUnits } from '../utils/money.js';
import { secureInt } from '../utils/crypto.js';
import { HttpError } from '../utils/http.js';
import { findIdempotency, saveIdempotency } from '../middleware/idempotency.js';
function outcomeFor(gameCode, amount){
  const roll=secureInt(1000000); let multiplier=0n;
  if(gameCode==='roulette'){ multiplier=roll<480000?2n:roll<500000?14n:0n; }
  else if(gameCode==='mines'){ multiplier=roll<430000?2n:roll<470000?5n:0n; }
  else { multiplier=roll<300000?2n:roll<360000?5n:roll<370000?20n:0n; }
  return { roll, multiplier, payout: amount*multiplier };
}
export async function placeBet(userId,input,idempotencyKey){
  if(input.currency!==config.currency)throw new HttpError(400,'Unsupported currency'); const amount=parseUnits(input.amount);
  return tx(async c=>{
    const old=await findIdempotency(c,userId,'game.bet',idempotencyKey);if(old)return old.response_body;
    const game=(await c.query(`SELECT * FROM games WHERE code=$1 AND enabled=true FOR SHARE`,[input.gameId])).rows[0];if(!game)throw new HttpError(404,'Game not found');
    if(amount<BigInt(game.min_bet_minor)||amount>BigInt(game.max_bet_minor))throw new HttpError(400,`Bet must be between ${formatUnits(game.min_bet_minor)} and ${formatUnits(game.max_bet_minor)} ${config.currency}`);
    const wallet=(await c.query(`SELECT * FROM wallets WHERE user_id=$1 AND currency=$2 FOR UPDATE`,[userId,config.currency])).rows[0];if(!wallet)throw new HttpError(409,'Wallet not found');if(BigInt(wallet.balance_minor)<amount)throw new HttpError(409,'Insufficient balance','INSUFFICIENT_BALANCE');
    const before=BigInt(wallet.balance_minor);await c.query(`UPDATE wallets SET balance_minor=balance_minor-$1,updated_at=now() WHERE id=$2`,[amount.toString(),wallet.id]);
    const bet=(await c.query(`INSERT INTO bets(user_id,game_id,currency,amount_minor,status,idempotency_key) VALUES($1,$2,$3,$4,'placed',$5) RETURNING *`,[userId,game.id,config.currency,amount.toString(),idempotencyKey])).rows[0];
    await c.query(`INSERT INTO transactions(user_id,wallet_id,type,currency,amount_minor,balance_before_minor,balance_after_minor,reference_type,reference_id) VALUES($1,$2,'bet',$3,$4,$5,$6,'bet',$7)`,[userId,wallet.id,config.currency,(-amount).toString(),before.toString(),(before-amount).toString(),bet.id]);
    const result=outcomeFor(game.code,amount);let finalBalance=before-amount;
    if(result.payout>0n){await c.query(`UPDATE wallets SET balance_minor=balance_minor+$1,updated_at=now() WHERE id=$2`,[result.payout.toString(),wallet.id]);await c.query(`INSERT INTO transactions(user_id,wallet_id,type,currency,amount_minor,balance_before_minor,balance_after_minor,reference_type,reference_id) VALUES($1,$2,'payout',$3,$4,$5,$6,'bet',$7)`,[userId,wallet.id,config.currency,result.payout.toString(),finalBalance.toString(),(finalBalance+result.payout).toString(),bet.id]);finalBalance+=result.payout;}
    await c.query(`UPDATE bets SET payout_minor=$1,result=$2,status='settled',settled_at=now() WHERE id=$3`,[result.payout.toString(),{roll:result.roll,multiplier:result.multiplier.toString()},bet.id]);
    const body={betId:bet.id,gameId:game.code,currency:config.currency,amount:formatUnits(amount),payout:formatUnits(result.payout),multiplier:result.multiplier.toString(),balance:formatUnits(finalBalance)};
    await saveIdempotency(c,userId,'game.bet',idempotencyKey,200,body);return body;
  });
}
EOF

cat > "$ROOT/backend/src/services/payments/base.js" <<'EOF'
export class PaymentAdapter { async createInvoice(){throw new Error('Payment adapter not implemented');} verifyAndNormalizeWebhook(){throw new Error('Payment webhook adapter not implemented');} }
EOF

cat > "$ROOT/backend/src/services/payments/mock.js" <<'EOF'
import { PaymentAdapter } from './base.js';
import { config } from '../../config.js';
import { hmacHex, safeEqualHex } from '../../utils/crypto.js';
import { HttpError } from '../../utils/http.js';
export class MockPaymentAdapter extends PaymentAdapter {
  async createInvoice(payment){if(!config.testMode)throw new HttpError(503,'Mock payments disabled');return {externalId:`mock_${payment.id}`,url:null,status:'pending'};}
  verifyAndNormalizeWebhook(raw,headers){if(!config.testMode)throw new HttpError(503,'Mock webhook disabled');if(!config.paymentWebhookSecret)throw new HttpError(503,'PAYMENT_WEBHOOK_SECRET is required for test webhook');const signature=headers['x-payment-signature']||'';if(!safeEqualHex(signature,hmacHex(config.paymentWebhookSecret,raw)))throw new HttpError(401,'Invalid webhook signature');let body;try{body=JSON.parse(raw)}catch{throw new HttpError(400,'Invalid webhook JSON')}return {externalId:body.externalId,status:body.status,amount:String(body.amount),asset:body.asset,network:body.network,eventId:body.eventId||body.externalId};}
}
EOF

cat > "$ROOT/backend/src/services/payments/index.js" <<'EOF'
import { config } from '../../config.js';
import { MockPaymentAdapter } from './mock.js';
export function paymentAdapter(){if(config.paymentProvider==='mock')return new MockPaymentAdapter();throw new Error(`Payment provider adapter '${config.paymentProvider}' is not installed. Implement it in services/payments/.`)}
EOF

cat > "$ROOT/backend/src/services/payment.js" <<'EOF'
import crypto from 'node:crypto';
import { tx } from '../db.js';
import { config } from '../config.js';
import { parseUnits, formatUnits } from '../utils/money.js';
import { HttpError } from '../utils/http.js';
import { paymentAdapter } from './payments/index.js';
import { findIdempotency, saveIdempotency } from '../middleware/idempotency.js';
export async function createInvoice(userId,input,key){if(input.currency!==config.currency)throw new HttpError(400,'Unsupported currency');if(!config.paymentAllowedAssets.includes(input.asset))throw new HttpError(400,'Unsupported asset/network');const amount=parseUnits(input.amount);if(amount<=0n)throw new HttpError(400,'Invalid amount');return tx(async c=>{const old=await findIdempotency(c,userId,'payment.invoice',key);if(old)return old.response_body;const id=crypto.randomUUID();const [asset,network]=input.asset.split('_');const payment=(await c.query(`INSERT INTO payments(id,user_id,provider,method,asset,network,currency,amount_minor,status,idempotency_key) VALUES($1,$2,$3,'crypto',$4,$5,$6,$7,'created',$8) RETURNING *`,[id,userId,config.paymentProvider,asset,network,config.currency,amount.toString(),key])).rows[0];const provider=await paymentAdapter().createInvoice(payment);await c.query(`UPDATE payments SET external_id=$1,status=$2,provider_payload=$3,updated_at=now() WHERE id=$4`,[provider.externalId,provider.status||'pending',provider,id]);const body={id,externalId:provider.externalId,status:provider.status||'pending',url:provider.url||null,qrUrl:provider.qrUrl||null,amount:formatUnits(amount),asset,network};await saveIdempotency(c,userId,'payment.invoice',key,201,body);return body;});}
export async function processWebhook(raw,headers){const event=paymentAdapter().verifyAndNormalizeWebhook(raw,headers);return tx(async c=>{const payment=(await c.query(`SELECT * FROM payments WHERE external_id=$1 FOR UPDATE`,[event.externalId])).rows[0];if(!payment)throw new HttpError(404,'Payment not found');if(payment.status==='paid')return {ok:true,duplicate:true};if(event.status!=='paid') {await c.query(`UPDATE payments SET status=$1,updated_at=now() WHERE id=$2`,[event.status,payment.id]);return {ok:true,credited:false};}if(event.asset!==payment.asset||event.network!==payment.network)throw new HttpError(400,'Asset or network mismatch');if(parseUnits(event.amount)!==BigInt(payment.amount_minor))throw new HttpError(400,'Amount mismatch');const wallet=(await c.query(`SELECT * FROM wallets WHERE user_id=$1 AND currency=$2 FOR UPDATE`,[payment.user_id,payment.currency])).rows[0];const before=BigInt(wallet.balance_minor),amount=BigInt(payment.amount_minor);await c.query(`UPDATE wallets SET balance_minor=balance_minor+$1,updated_at=now() WHERE id=$2`,[amount.toString(),wallet.id]);await c.query(`INSERT INTO transactions(user_id,wallet_id,type,currency,amount_minor,balance_before_minor,balance_after_minor,reference_type,reference_id,metadata) VALUES($1,$2,'deposit',$3,$4,$5,$6,'payment',$7,$8)`,[payment.user_id,wallet.id,payment.currency,amount.toString(),before.toString(),(before+amount).toString(),payment.id,{eventId:event.eventId}]);await c.query(`UPDATE payments SET status='paid',paid_at=now(),webhook_event_id=$1,updated_at=now() WHERE id=$2`,[event.eventId,payment.id]);return {ok:true,credited:true};});}
EOF

cat > "$ROOT/backend/src/controllers/api.js" <<'EOF'
import { pool, tx } from '../db.js';
import { config } from '../config.js';
import { validateTelegramInitData } from '../services/telegram.js';
import { createOrRefreshUser, getSessionPayload } from '../services/session.js';
import { placeBet } from '../services/game.js';
import { createInvoice } from '../services/payment.js';
import { keyFrom, findIdempotency, saveIdempotency } from '../middleware/idempotency.js';
import { HttpError } from '../utils/http.js';
import { formatUnits } from '../utils/money.js';
export async function telegramAuth(req,res){const initData=req.body?.initData||req.get('X-Telegram-Init-Data')||'';const tgUser=validateTelegramInitData(initData);const created=await createOrRefreshUser(tgUser);res.cookie('tuff_session',created.token,{httpOnly:true,secure:config.env==='production',sameSite:'lax',path:'/',expires:created.expires});const c=await pool.connect();try{res.json(await getSessionPayload(c,created.user.id))}finally{c.release()}}
export async function me(req,res){const c=await pool.connect();try{res.json(await getSessionPayload(c,req.userId))}finally{c.release()}}
export async function launch(req,res){const game=(await pool.query(`SELECT code,name,provider,launch_mode FROM games WHERE code=$1 AND enabled=true`,[req.body.gameId])).rows[0];if(!game)throw new HttpError(404,'Game not found');res.json({gameId:game.code,name:game.name,mode:game.launch_mode,launchUrl:null});}
export async function bet(req,res){const result=await placeBet(req.userId,req.body,keyFrom(req));res.json(result)}
export async function invoice(req,res){const result=await createInvoice(req.userId,req.body,keyFrom(req));res.status(201).json(result)}
export async function dailyBonus(req,res){const key=keyFrom(req);const result=await tx(async c=>{const old=await findIdempotency(c,req.userId,'bonus.daily',key);if(old)return old.response_body;const last=(await c.query(`SELECT claimed_at FROM bonuses WHERE user_id=$1 AND type='daily' ORDER BY claimed_at DESC LIMIT 1 FOR UPDATE`,[req.userId])).rows[0];if(last&&Date.now()-new Date(last.claimed_at).getTime()<86400000)throw new HttpError(409,'Daily bonus already claimed');const wallet=(await c.query(`SELECT * FROM wallets WHERE user_id=$1 AND currency=$2 FOR UPDATE`,[req.userId,config.currency])).rows[0];const amount=config.testMode?1000000n:0n;if(!config.testMode)throw new HttpError(503,'Production bonus rules are not configured');const before=BigInt(wallet.balance_minor);const bonus=(await c.query(`INSERT INTO bonuses(user_id,type,currency,amount_minor,status,claimed_at) VALUES($1,'daily',$2,$3,'credited',now()) RETURNING id`,[req.userId,config.currency,amount.toString()])).rows[0];await c.query(`UPDATE wallets SET balance_minor=balance_minor+$1,updated_at=now() WHERE id=$2`,[amount.toString(),wallet.id]);await c.query(`INSERT INTO transactions(user_id,wallet_id,type,currency,amount_minor,balance_before_minor,balance_after_minor,reference_type,reference_id) VALUES($1,$2,'bonus',$3,$4,$5,$6,'bonus',$7)`,[req.userId,wallet.id,config.currency,amount.toString(),before.toString(),(before+amount).toString(),bonus.id]);const body={message:`Bonus credited: ${formatUnits(amount)} ${config.currency}`};await saveIdempotency(c,req.userId,'bonus.daily',key,200,body);return body;});res.json(result)}
export async function claimMission(req,res){const key=keyFrom(req);const result=await tx(async c=>{const old=await findIdempotency(c,req.userId,'mission.claim',key);if(old)return old.response_body;const mission=(await c.query(`SELECT um.*,m.reward_minor,m.code FROM user_missions um JOIN missions m ON m.code=um.mission_code WHERE um.user_id=$1 AND um.status='active' ORDER BY um.created_at LIMIT 1 FOR UPDATE`,[req.userId])).rows[0];if(!mission)throw new HttpError(409,'No active mission');const bets=Number((await c.query(`SELECT count(*) count FROM bets WHERE user_id=$1`,[req.userId])).rows[0].count);if(bets<1)throw new HttpError(409,'Mission condition is not completed');const wallet=(await c.query(`SELECT * FROM wallets WHERE user_id=$1 AND currency=$2 FOR UPDATE`,[req.userId,config.currency])).rows[0];const amount=BigInt(mission.reward_minor),before=BigInt(wallet.balance_minor);await c.query(`UPDATE wallets SET balance_minor=balance_minor+$1,updated_at=now() WHERE id=$2`,[amount.toString(),wallet.id]);await c.query(`UPDATE user_missions SET status='claimed',claimed_at=now() WHERE id=$1`,[mission.id]);await c.query(`INSERT INTO transactions(user_id,wallet_id,type,currency,amount_minor,balance_before_minor,balance_after_minor,reference_type,reference_id) VALUES($1,$2,'bonus',$3,$4,$5,$6,'mission',$7)`,[req.userId,wallet.id,config.currency,amount.toString(),before.toString(),(before+amount).toString(),mission.id]);const body={message:`Mission reward: ${formatUnits(amount)} ${config.currency}`};await saveIdempotency(c,req.userId,'mission.claim',key,200,body);return body;});res.json(result)}
EOF

cat > "$ROOT/backend/src/routes/api.js" <<'EOF'
import { Router } from 'express';
import { z } from 'zod';
import { asyncRoute, HttpError } from '../utils/http.js';
import { requireAuth } from '../middleware/auth.js';
import * as c from '../controllers/api.js';
import { config } from '../config.js';
const r=Router();
const validate=schema=>(req,res,next)=>{const out=schema.safeParse(req.body);if(!out.success)return next(new HttpError(400,out.error.issues.map(x=>x.message).join(', '),'VALIDATION_ERROR'));req.body=out.data;next()};
const authSchema=z.object({initData:z.string().optional(),mode:z.enum(['login','register']).optional()});
const gameSchema=z.object({gameId:z.string().min(1).max(80)});
const betSchema=z.object({gameId:z.string().min(1).max(80),amount:z.union([z.string(),z.number()]),currency:z.literal(config.currency)});
const invoiceSchema=z.object({amount:z.union([z.string(),z.number()]),currency:z.literal(config.currency),method:z.literal('crypto').optional().default('crypto'),asset:z.enum(config.paymentAllowedAssets)});
r.post('/miniapp/session',validate(authSchema),asyncRoute(c.telegramAuth));r.post('/auth/telegram',validate(authSchema),asyncRoute(c.telegramAuth));r.get('/me',requireAuth,asyncRoute(c.me));r.post('/games/launch',requireAuth,validate(gameSchema),asyncRoute(c.launch));r.post('/games/bet',requireAuth,validate(betSchema),asyncRoute(c.bet));r.post('/payments/invoices',requireAuth,validate(invoiceSchema),asyncRoute(c.invoice));r.post('/bonuses/daily',requireAuth,asyncRoute(c.dailyBonus));r.post('/missions/current/claim',requireAuth,asyncRoute(c.claimMission));export default r;
EOF

cat > "$ROOT/backend/src/migrate.js" <<'EOF'
import fs from 'node:fs/promises';import path from 'node:path';import { pool } from './db.js';
const dir=process.env.MIGRATIONS_DIR||'/database/migrations';await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations(name text PRIMARY KEY,applied_at timestamptz NOT NULL DEFAULT now())`);for(const name of (await fs.readdir(dir)).filter(x=>x.endsWith('.sql')).sort()){const done=(await pool.query(`SELECT 1 FROM schema_migrations WHERE name=$1`,[name])).rowCount;if(done)continue;const sql=await fs.readFile(path.join(dir,name),'utf8');const c=await pool.connect();try{await c.query('BEGIN');await c.query(sql);await c.query(`INSERT INTO schema_migrations(name) VALUES($1)`,[name]);await c.query('COMMIT');console.log('Applied',name)}catch(e){await c.query('ROLLBACK');throw e}finally{c.release()}}await pool.end();
EOF

cat > "$ROOT/backend/src/server.js" <<'EOF'
import express from 'express';import path from 'node:path';import helmet from 'helmet';import cors from 'cors';import cookieParser from 'cookie-parser';import rateLimit from 'express-rate-limit';import pinoHttp from 'pino-http';import pino from 'pino';import { config } from './config.js';import { pool } from './db.js';import apiRoutes from './routes/api.js';import { processWebhook } from './services/payment.js';import { asyncRoute } from './utils/http.js';
const app=express();app.set('trust proxy',config.trustProxy);const logger=pino({level:config.logLevel,redact:['req.headers.cookie','req.headers.authorization','req.body.initData']});app.use(pinoHttp({logger}));app.use(helmet({contentSecurityPolicy:{directives:{defaultSrc:["'self'"],scriptSrc:["'self'","'unsafe-inline'",'https://telegram.org'],styleSrc:["'self'","'unsafe-inline'"],imgSrc:["'self'",'data:','https:'],frameSrc:["'self'",'https:'],connectSrc:["'self'",config.appOrigin]}}}));app.use(cors({origin:config.appOrigin,credentials:true}));app.use(rateLimit({windowMs:config.rateWindowMs,limit:config.rateMax,standardHeaders:true,legacyHeaders:false}));
app.post('/api/payments/webhook',express.raw({type:'application/json',limit:'256kb'}),asyncRoute(async(req,res)=>{const result=await processWebhook(req.body.toString('utf8'),req.headers);req.log.info({result},'payment webhook processed');res.json(result)}));
app.use(express.json({limit:'256kb'}));app.use(cookieParser());app.get('/health',asyncRoute(async(req,res)=>{await pool.query('SELECT 1');res.json({ok:true,mode:config.testMode?'test':'production'})}));app.use('/api',apiRoutes);app.use(express.static('/frontend',{extensions:['html']}));app.get('*',(req,res)=>res.sendFile(path.resolve('/frontend/index.html'));
app.use((err,req,res,next)=>{req.log.error({err,code:err.code},'request failed');res.status(err.status||500).json({message:err.status?err.message:'Internal server error',code:err.code||'INTERNAL_ERROR'})});app.listen(config.port,()=>logger.info({port:config.port,testMode:config.testMode},'TUFF backend started'));
EOF

cat > "$ROOT/database/migrations/001_init.sql" <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TYPE transaction_type AS ENUM ('deposit','bet','payout','bonus','refund','withdrawal','adjustment');
CREATE TYPE payment_status AS ENUM ('created','pending','paid','failed','expired','cancelled');
CREATE TYPE withdrawal_status AS ENUM ('requested','review','approved','rejected','processing','paid','failed','cancelled');
CREATE TABLE users(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),telegram_id text UNIQUE NOT NULL,username text,first_name text NOT NULL DEFAULT '',last_name text NOT NULL DEFAULT '',language_code text,status text NOT NULL DEFAULT 'active',last_login_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE sessions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,token_hash text UNIQUE NOT NULL,expires_at timestamptz NOT NULL,revoked_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());CREATE INDEX sessions_user_idx ON sessions(user_id);
CREATE TABLE wallets(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id),currency text NOT NULL,balance_minor numeric(36,0) NOT NULL DEFAULT 0 CHECK(balance_minor>=0),created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,currency));
CREATE TABLE games(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text UNIQUE NOT NULL,name text NOT NULL,provider text NOT NULL,launch_mode text NOT NULL DEFAULT 'native',currency text NOT NULL DEFAULT 'USDT',min_bet_minor numeric(36,0) NOT NULL,max_bet_minor numeric(36,0) NOT NULL,enabled boolean NOT NULL DEFAULT true,config jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE bets(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id),game_id uuid NOT NULL REFERENCES games(id),currency text NOT NULL,amount_minor numeric(36,0) NOT NULL CHECK(amount_minor>0),payout_minor numeric(36,0) NOT NULL DEFAULT 0 CHECK(payout_minor>=0),status text NOT NULL,idempotency_key text NOT NULL,result jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now(),settled_at timestamptz,UNIQUE(user_id,idempotency_key));CREATE INDEX bets_user_created_idx ON bets(user_id,created_at DESC);
CREATE TABLE payments(id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),provider text NOT NULL,external_id text UNIQUE,method text NOT NULL,asset text NOT NULL,network text NOT NULL,currency text NOT NULL,amount_minor numeric(36,0) NOT NULL CHECK(amount_minor>0),status payment_status NOT NULL,idempotency_key text NOT NULL,webhook_event_id text UNIQUE,provider_payload jsonb NOT NULL DEFAULT '{}',paid_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,idempotency_key));
CREATE TABLE transactions(id bigserial PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),wallet_id uuid NOT NULL REFERENCES wallets(id),type transaction_type NOT NULL,currency text NOT NULL,amount_minor numeric(36,0) NOT NULL,balance_before_minor numeric(36,0) NOT NULL,balance_after_minor numeric(36,0) NOT NULL,reference_type text,reference_id uuid,metadata jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now());CREATE INDEX transactions_user_created_idx ON transactions(user_id,created_at DESC);
CREATE TABLE bonuses(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id),type text NOT NULL,currency text NOT NULL,amount_minor numeric(36,0) NOT NULL,status text NOT NULL,claimed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE missions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text UNIQUE NOT NULL,title text NOT NULL,reward_minor numeric(36,0) NOT NULL,enabled boolean NOT NULL DEFAULT true,config jsonb NOT NULL DEFAULT '{}');
CREATE TABLE user_missions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id),mission_code text NOT NULL REFERENCES missions(code),status text NOT NULL,claimed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,mission_code));
CREATE TABLE idempotency_keys(id bigserial PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),scope text NOT NULL,idempotency_key text NOT NULL,response_status integer NOT NULL,response_body jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(user_id,scope,idempotency_key));
CREATE TABLE withdrawals(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES users(id),currency text NOT NULL,asset text NOT NULL,network text NOT NULL,address text NOT NULL,amount_minor numeric(36,0) NOT NULL CHECK(amount_minor>0),status withdrawal_status NOT NULL DEFAULT 'requested',reviewed_by text,provider_external_id text,metadata jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
INSERT INTO games(code,name,provider,min_bet_minor,max_bet_minor) VALUES ('ruby-sevens','Ruby Sevens','TUFF Originals',1000000,1000000000),('red-wolf','Red Wolf Moon','Nova Play',1000000,1000000000),('royal-dog','Royal Dog House','Red Studio',1000000,1000000000),('crimson-bull','Crimson Bull','TUFF Originals',1000000,1000000000),('tuff-space','TUFF Space','Nova Play',1000000,1000000000),('wild-red-west','Wild Red West','Red Studio',1000000,1000000000),('roulette','TUFF Roulette','TUFF Originals',1000000,1000000000),('blackjack','Red Blackjack','TUFF Originals',1000000,1000000000),('mines','Crimson Mines','TUFF Originals',1000000,1000000000),('neon-fruits','Neon Fruits','Nova Play',1000000,1000000000),('red-diamond','Red Diamond','Red Studio',1000000,1000000000),('lucky-bell','Lucky Bell','TUFF Originals',1000000,1000000000) ON CONFLICT DO NOTHING;
INSERT INTO missions(code,title,reward_minor,config) VALUES('first-bet','Первая ставка',5000000,'{"bets":1}') ON CONFLICT DO NOTHING;
EOF

cat > "$ROOT/frontend/index.html" <<'EOF'
<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no"><meta name="theme-color" content="#0b0b0e"><title>TUFF CASINO</title><script src="https://telegram.org/js/telegram-web-app.js"></script><style>
:root{--bg:#0b0b0e;--p:#18181d;--line:#303036;--red:#ed1b3a;--gold:#ffbc32;--text:#fff;--muted:#92929c;--safe:env(safe-area-inset-bottom)}*{box-sizing:border-box}body{margin:0;background:#000;color:var(--text);font:600 14px system-ui}.app{max-width:680px;min-height:100vh;margin:auto;padding-bottom:100px;background:radial-gradient(circle at 80% 0,#3b0711,transparent 24%),var(--bg)}button,input,select{font:inherit;color:inherit}.top{position:sticky;top:0;z-index:10;padding:11px 16px;background:#111115ed;backdrop-filter:blur(18px)}.row{display:flex;align-items:center;gap:9px}.logo{margin-right:auto;font-size:19px;font-weight:1000}.logo b{color:var(--red)}.btn{padding:10px 14px;border:0;border-radius:999px;background:#29292f;font-weight:900}.gold{background:linear-gradient(145deg,#ffd45f,var(--gold),#ff8619);color:#191208}.wallet{padding:10px 13px;border:1px solid #393940;border-radius:999px;background:#202025}.search{display:flex;gap:8px;margin-top:10px}.search input,.search select{min-width:0;padding:11px;border:1px solid var(--line);border-radius:12px;background:#19191e}.search input{flex:1}.page{display:none;padding:18px}.page.on{display:block}.head{display:flex;justify-content:space-between;align-items:center;margin:10px 0 12px}.head h2{margin:0}.games{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.game{position:relative;overflow:hidden;aspect-ratio:1;border:1px solid var(--line);border-radius:17px;background:var(--art);box-shadow:inset 0 -45px 50px #0008}.game i{position:absolute;top:7px;left:7px;padding:4px 6px;border-radius:7px;background:#ef3c22;font-size:9px}.game span{position:absolute;left:50%;top:44%;transform:translate(-50%,-50%);font-size:46px}.game b{position:absolute;left:6px;right:6px;bottom:8px;text-align:center;font-size:10px}.section{margin-bottom:25px}.mission,.box{padding:16px;border:1px solid var(--line);border-radius:19px;background:var(--p)}.mission{display:flex;align-items:center;gap:12px}.mission strong{flex:1}.leader{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;text-align:center}.leader div{padding:15px 5px;border:1px solid #5f5025;border-radius:18px;background:#211a0e}.leader span{display:block;font-size:35px}.leader small{color:var(--gold)}.nav{position:fixed;left:50%;bottom:12px;transform:translateX(-50%);display:grid;grid-template-columns:repeat(5,1fr);width:min(620px,calc(100% - 30px));padding:8px;border:1px solid #75621d;border-radius:31px;background:#18181def;backdrop-filter:blur(18px)}.nav button{border:0;background:none;color:#888;font-size:10px}.nav span{display:block;font-size:21px}.nav .on{color:var(--gold)}.nav .plus{width:52px;height:52px;margin:-20px auto -4px;border-radius:50%;background:var(--gold);color:#171109;font-size:27px}.field{display:grid;gap:5px;margin:11px 0}.field input,.field select{padding:12px;border:1px solid var(--line);border-radius:11px;background:#0e0e11}.methods{display:grid;grid-template-columns:1fr 1fr;gap:8px}.method{padding:13px;border:1px solid var(--line);border-radius:12px;background:#202025;text-align:left}.method.on{border-color:var(--gold)}.history{display:grid;gap:8px}.item{display:flex;justify-content:space-between;padding:11px;border:1px solid var(--line);border-radius:11px;background:#151519}.modal{position:fixed;z-index:50;inset:0;display:flex;align-items:flex-end;background:#000c}.modal.hide{display:none}.sheet{width:min(680px,100%);max-height:92vh;overflow:auto;margin:auto 0 0;padding:16px;border-radius:24px 24px 0 0;background:#151519}.sheethead{display:flex;justify-content:space-between}.close{width:35px;height:35px;border:0;border-radius:50%;background:#303036}.notice{padding:11px;border:1px solid #5b3741;border-radius:11px;background:#271017;color:#ffc0ca;font-size:10px}.toast{position:fixed;z-index:90;left:50%;bottom:105px;transform:translateX(-50%);padding:11px;border-radius:10px;background:#29292f}.hide{display:none}@media(max-width:400px){.games{gap:7px}.game{border-radius:13px}.game span{font-size:38px}.page{padding:14px}.logo{font-size:16px}}
</style></head><body><div class="app"><header class="top"><div class="row"><div class="logo">TUFF <b>CASINO</b></div><button class="btn" id="auth">Вход</button><div class="wallet hide" id="wallet">—</div></div><div class="search"><input id="q" placeholder="Поиск"><select id="provider"><option value="all">Провайдер</option><option>TUFF Originals</option><option>Red Studio</option><option>Nova Play</option></select></div></header><main><section class="page on" id="lobby"><div class="section"><div class="head"><h2>Популярные сейчас</h2><button class="btn">Все</button></div><div class="games" id="popular"></div></div><div class="section"><div class="head"><h2>Миссии</h2></div><div class="mission"><span style="font-size:35px">🏆</span><strong>Сделайте первую ставку</strong><button class="btn gold" id="mission">Получить</button></div></div><div class="section"><div class="head"><h2>Топ</h2></div><div class="games" id="top"></div></div><div class="section box"><div class="head"><h2>Топ за 24 часа</h2></div><div class="leader"><div><span>🥈</span>RedFox<small>340 USDT</small></div><div><span>🥇</span>TuffPlayer<small>352 USDT</small></div><div><span>🥉</span>RubyMaster<small>320 USDT</small></div></div></div><div class="section"><div class="head"><h2>Горячие</h2></div><div class="games" id="hot"></div></div></section><section class="page" id="search"><div class="head"><h2>Все игры</h2></div><div class="games" id="all"></div></section><section class="page" id="cashier"><div class="head"><h2>Криптокасса</h2></div><div class="box"><div class="notice">Ссылка или QR создаются платёжным провайдером через backend. Баланс меняется только после проверенного webhook.</div><div class="methods"><button class="method on" data-asset="USDT_TRC20">USDT<small> TRC20</small></button><button class="method" data-asset="USDT_ERC20">USDT<small> ERC20</small></button></div><div class="field"><label>Сумма USDT</label><input id="amount" value="10"></div><button class="btn gold" id="deposit">Создать invoice</button></div><div class="head"><h2>Операции</h2></div><div class="history" id="payments"></div></section><section class="page" id="bonuses"><div class="head"><h2>Бонусы</h2></div><div class="mission"><span>🎁</span><strong>Ежедневная награда</strong><button class="btn gold" id="bonus">Получить</button></div></section><section class="page" id="profile"><div class="head"><h2>Профиль</h2></div><div class="box" id="profileBox">Авторизуйтесь через Telegram</div><div class="head"><h2>История игр</h2></div><div class="history" id="gameHistory"></div></section></main><nav class="nav"><button data-page="profile"><span>☰</span>Меню</button><button class="on" data-page="lobby"><span>⌂</span>Лобби</button><button data-page="cashier"><span class="plus">+</span></button><button data-page="bonuses"><span>🎁</span>Бонусы</button><button data-page="search"><span>⌕</span>Поиск</button></nav></div><div class="modal hide" id="modal"><div class="sheet"><div class="sheethead"><h3 id="mtitle">TUFF</h3><button class="close" id="close">×</button></div><div id="mbody"></div></div></div><div class="toast hide" id="toast"></div><script>
const CONFIG={API_BASE:'/api',CURRENCY:'USDT'};const tg=window.Telegram?.WebApp;tg?.ready();tg?.expand();const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];let me=null,asset='USDT_TRC20';const G=[['ruby-sevens','Ruby Sevens','TUFF Originals','7️⃣','#c31330'],['red-wolf','Red Wolf Moon','Nova Play','🐺','#6821bc'],['royal-dog','Royal Dog House','Red Studio','🐶','#ca7d22'],['crimson-bull','Crimson Bull','TUFF Originals','🐂','#d63c18'],['tuff-space','TUFF Space','Nova Play','🚀','#1262b0'],['wild-red-west','Wild Red West','Red Studio','🤠','#9b581c'],['roulette','TUFF Roulette','TUFF Originals','🎡','#16643c'],['blackjack','Red Blackjack','TUFF Originals','♠️','#9e1028'],['mines','Crimson Mines','TUFF Originals','💣','#d81d3c'],['neon-fruits','Neon Fruits','Nova Play','🍒','#b21b50'],['red-diamond','Red Diamond','Red Studio','💎','#6d1aa0'],['lucky-bell','Lucky Bell','TUFF Originals','🔔','#b67912']];
async function api(path,opt={}){const h={'Content-Type':'application/json',...(opt.headers||{})};if(tg?.initData)h['X-Telegram-Init-Data']=tg.initData;const r=await fetch(CONFIG.API_BASE+path,{...opt,headers:h,credentials:'include'}),d=await r.json().catch(()=>({}));if(!r.ok)throw Error(d.message||'Ошибка API');return d}const key=()=>crypto.randomUUID();function toast(t){$('#toast').textContent=t;$('#toast').classList.remove('hide');setTimeout(()=>$('#toast').classList.add('hide'),2500)}function card(g){return `<button class="game" style="--art:linear-gradient(145deg,#21040a,${g[4]})" data-game="${g[0]}"><i>Hot</i><span>${g[3]}</span><b>${g[1]}</b></button>`}function renderGames(){const q=$('#q').value.toLowerCase(),p=$('#provider').value,f=G.filter(g=>(p==='all'||g[2]===p)&&g[1].toLowerCase().includes(q));$('#popular').innerHTML=G.slice(0,6).map(card).join('');$('#top').innerHTML=G.slice(3,9).map(card).join('');$('#hot').innerHTML=G.slice(6).map(card).join('');$('#all').innerHTML=f.map(card).join('')}function render(){if(!me)return;$('#wallet').classList.remove('hide');$('#auth').classList.add('hide');$('#wallet').textContent=`${me.wallet.available} ${me.wallet.currency}`;$('#profileBox').innerHTML=`<b>${me.user.name}</b><p>ID: ${me.user.id}</p><p>Баланс: ${me.wallet.available} ${me.wallet.currency}</p><p>Раундов: ${me.stats.rounds} · Оборот: ${me.stats.wagered}</p>`;$('#gameHistory').innerHTML=(me.gameHistory||[]).map(x=>`<div class="item"><span>${x.gameName}</span><b>${x.net}</b></div>`).join('')||'<div class="notice">История пуста</div>';$('#payments').innerHTML=(me.paymentHistory||[]).map(x=>`<div class="item"><span>${x.asset} ${x.network}</span><b>${x.status}</b></div>`).join('')||'<div class="notice">Операций нет</div>'}function page(n){$$('.page').forEach(x=>x.classList.remove('on'));$('#'+n).classList.add('on');$$('.nav button').forEach(x=>x.classList.toggle('on',x.dataset.page===n));scrollTo(0,0)}function modal(t,h){$('#mtitle').textContent=t;$('#mbody').innerHTML=h;$('#modal').classList.remove('hide')}async function auth(){try{me=await api('/auth/telegram',{method:'POST',body:JSON.stringify({initData:tg?.initData||'',mode:'register'})});render();toast('Авторизация выполнена')}catch(e){toast(e.message)}}async function refresh(){try{me=await api('/me');render()}catch{}}
async function openGame(id){if(!me)return auth();const g=G.find(x=>x[0]===id);modal(g[1],`<div class="notice">Результат рассчитывает только сервер.</div><div style="display:grid;place-items:center;height:250px;font-size:80px">${g[3]}</div><div class="field"><label>Ставка USDT</label><input id="bet" value="1"></div><button class="btn gold" id="betBtn" data-id="${id}">Сделать ставку</button>`)}async function bet(id){try{const r=await api('/games/bet',{method:'POST',headers:{'Idempotency-Key':key()},body:JSON.stringify({gameId:id,amount:$('#bet').value,currency:CONFIG.CURRENCY})});toast(`Выплата: ${r.payout} USDT`);await refresh()}catch(e){toast(e.message)}}async function invoice(){try{const r=await api('/payments/invoices',{method:'POST',headers:{'Idempotency-Key':key()},body:JSON.stringify({amount:$('#amount').value,currency:CONFIG.CURRENCY,method:'crypto',asset})});if(r.url)tg?.openLink?r.url&&tg.openLink(r.url):location.href=r.url;else toast(`Invoice ${r.id} создан`);await refresh()}catch(e){toast(e.message)}}async function claim(path){try{const r=await api(path,{method:'POST',headers:{'Idempotency-Key':key()}});toast(r.message);await refresh()}catch(e){toast(e.message)}}document.addEventListener('click',e=>{const p=e.target.closest('[data-page]');if(p)return page(p.dataset.page);const g=e.target.closest('[data-game]');if(g)return openGame(g.dataset.game);const m=e.target.closest('[data-asset]');if(m){asset=m.dataset.asset;$$('[data-asset]').forEach(x=>x.classList.toggle('on',x===m))}if(e.target.id==='betBtn')bet(e.target.dataset.id)});$('#auth').onclick=auth;$('#deposit').onclick=invoice;$('#bonus').onclick=()=>claim('/bonuses/daily');$('#mission').onclick=()=>claim('/missions/current/claim');$('#close').onclick=()=>$('#modal').classList.add('hide');$('#q').oninput=()=>{renderGames();page('search')};$('#provider').onchange=()=>{renderGames();page('search')};renderGames();api('/miniapp/session',{method:'POST',body:JSON.stringify({initData:tg?.initData||''})}).then(x=>{me=x;render()}).catch(()=>{});
</script></body></html>
EOF

cat > "$ROOT/README.md" <<'EOF'
# TUFF CASINO — Telegram Mini App architecture

Проект содержит frontend, Node.js/Express backend, PostgreSQL, миграции, серверный кошелёк, Telegram Mini App auth, серверные игровые операции и заменяемый криптоплатёжный adapter.

> По умолчанию `TEST_MODE=true`. Реальные депозиты и production-бонусы заблокированы. Перед работой с реальными средствами необходимо проверить требования Telegram, лицензию, географические ограничения, KYC/AML, responsible gaming, правила платёжного провайдера и законодательство всех целевых юрисдикций.

## Структура

- `frontend/index.html` — Mini App, `API_BASE: '/api'`, без секретов и без настоящего баланса в localStorage.
- `backend/src` — API, Telegram validation, sessions, games, payments.
- `database/migrations` — PostgreSQL schema.
- `docker-compose.yml` — backend + PostgreSQL.
- `nginx.conf.example` — HTTPS reverse proxy.

## Быстрый запуск

```bash
cp .env.example .env
```

Сгенерируйте сильные значения:

```bash
openssl rand -hex 32   # SESSION_SECRET
openssl rand -hex 32   # PAYMENT_WEBHOOK_SECRET для mock test webhook
```

Вставьте их в `.env`. Токен бота вставьте самостоятельно:

```env
TELEGRAM_BOT_TOKEN=токен_из_BotFather
```

Не публикуйте `.env` и не помещайте токен во frontend.

Для локальной разработки вне Telegram можно временно включить только вместе с test mode:

```env
TEST_MODE=true
DEV_BYPASS_TELEGRAM=true
```

Запуск:

```bash
docker compose up -d --build
docker compose logs -f backend
curl http://127.0.0.1:3000/health
```

Миграции применяются контейнером автоматически. Вручную:

```bash
docker compose run --rm backend node src/migrate.js
```

## API

- `POST /api/miniapp/session`
- `POST /api/auth/telegram`
- `GET /api/me`
- `POST /api/games/launch`
- `POST /api/games/bet`
- `POST /api/payments/invoices`
- `POST /api/payments/webhook`
- `POST /api/bonuses/daily`
- `POST /api/missions/current/claim`
- `GET /health`

Финансовые POST-запросы требуют заголовок `Idempotency-Key`.

## Telegram Mini App

1. Создайте бота в `@BotFather`.
2. Вставьте токен только в `.env` на VPS.
3. Настройте Menu Button / Mini App URL на `https://ваш-домен/`.
4. Backend валидирует `initData` официальным HMAC-алгоритмом и проверяет `auth_date`.
5. В production установите `DEV_BYPASS_TELEGRAM=false`.

## Денежная модель

USDT хранится в минимальных единицах с scale 6. Например, `1 USDT = 1000000`. PostgreSQL использует `numeric(36,0)`, Node.js — `BigInt`. Ставки передаются строкой и разбираются без `Number`/floating point.

Баланс изменяется только внутри SQL-транзакций с `SELECT ... FOR UPDATE`. Каждое изменение записывается в `transactions`: `deposit`, `bet`, `payout`, `bonus`, `refund`, `withdrawal`, `adjustment`.

## Игры

`POST /api/games/bet` принимает:

```json
{"gameId":"ruby-sevens","amount":"1.25","currency":"USDT"}
```

Сервер проверяет пользователя, игру, лимиты, баланс и идемпотентность, блокирует кошелёк, списывает ставку, использует `crypto.randomInt`, рассчитывает payout, сохраняет bet и ledger. Встроенная игровая математика является только test-mode примером, а не сертифицированным RNG. Для production нужен сертифицированный game/RNG provider, аудит математики и ограничения по юрисдикции.

## Платёжный adapter

В проекте есть только `MockPaymentAdapter` для test mode. Конкретный API провайдера намеренно не придуман. Возможные категории провайдеров: лицензированный crypto payment processor с hosted invoice, поддержкой нужной вам юрисдикции, USDT TRC20/ERC20, подписанными webhook, testnet/sandbox и политикой, допускающей ваш вид деятельности.

После выбора провайдера:

1. Создайте adapter в `backend/src/services/payments/`.
2. Реализуйте `createInvoice()` по официальной документации.
3. Реализуйте проверку подлинной подписи webhook по документации провайдера.
4. Нормализуйте событие в `{externalId,status,amount,asset,network,eventId}`.
5. Добавьте adapter в `payments/index.js`.
6. Укажите `PAYMENT_PROVIDER`, `PAYMENT_API_KEY`, `PAYMENT_WEBHOOK_SECRET`.
7. Никогда не начисляйте баланс по frontend redirect/callback.

Баланс начисляется только после проверенного webhook, совпадения order ID, валюты, сети, суммы, статуса и проверки повторной обработки.

### Test webhook

В mock mode тело подписывается HMAC-SHA256 от точной JSON-строки ключом `PAYMENT_WEBHOOK_SECRET`, подпись передаётся в `X-Payment-Signature`. Используйте только в закрытой тестовой среде.

## Вывод

Таблица `withdrawals` и статусы созданы, но API автоматического вывода отсутствует намеренно. Production withdrawal требует KYC/AML, risk engine, ручного review, address screening, 2FA/step-up auth, лимитов, холодного/горячего кошелька и отдельного подписывающего сервиса. Не храните приватный ключ кошелька в frontend или основном web-контейнере.

## VPS, домен и HTTPS

1. Купите VPS и домен.
2. Установите Docker Engine и Compose plugin.
3. Направьте A/AAAA запись домена на VPS.
4. Скопируйте проект на сервер.
5. Создайте `.env` и заполните секреты.
6. Запустите `docker compose up -d --build`.
7. Установите Nginx и Certbot.
8. Адаптируйте `nginx.conf.example` под домен.
9. Выпустите TLS-сертификат Let's Encrypt.
10. Установите `APP_ORIGIN=https://ваш-домен` и `NODE_ENV=production`.
11. Настройте Mini App URL в BotFather.
12. Подключите sandbox выбранного платёжного провайдера и webhook URL `https://ваш-домен/api/payments/webhook`.
13. Проверьте повторные webhook, несовпадение суммы/сети, истёкшие invoices и параллельные ставки.
14. Только после аудита и юридического допуска отключайте test mode.

## Production checklist

- `NODE_ENV=production`
- `TEST_MODE=false`
- `DEV_BYPASS_TELEGRAM=false`
- сильные `SESSION_SECRET` и provider webhook secret
- настоящий provider adapter и sandbox tests
- managed PostgreSQL backups/PITR
- мониторинг, alerting и offsite audit logs
- KYC/AML, sanctions/address screening
- возрастные и географические ограничения
- responsible gaming и самоисключение
- сертифицированный RNG/game provider
- penetration test и dependency scanning
- DDoS/WAF и секрет-хранилище

## Что изменено во frontend

- сохранена мобильная тёмная красно-золотая компоновка TUFF;
- три карточки в ряд, миссии, топ, горячие игры и нижняя панель;
- `CONFIG.API_BASE='/api'`, `CURRENCY='USDT'`;
- убран localStorage как источник баланса;
- результат игры и новый баланс приходят только от backend;
- оставлены только USDT TRC20/ERC20;
- frontend не содержит токенов и provider keys.
EOF

chmod +x "$ROOT/setup-project.sh" 2>/dev/null || true
printf '\nProject created in: %s\nNext steps:\n  cd %s\n  cp .env.example .env\n  # fill secrets\n  docker compose up -d --build\n' "$ROOT" "$ROOT"
