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
