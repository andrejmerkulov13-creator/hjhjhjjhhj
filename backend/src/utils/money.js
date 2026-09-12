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
