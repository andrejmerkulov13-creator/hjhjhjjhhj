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
