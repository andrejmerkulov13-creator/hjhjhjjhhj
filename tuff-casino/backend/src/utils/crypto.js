import crypto from 'node:crypto';
export const randomToken = (bytes = 32) => crypto.randomBytes(bytes).toString('base64url');
export const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');
export const hmacHex = (secret, value) => crypto.createHmac('sha256', secret).update(value).digest('hex');
export const safeEqualHex = (a, b) => { try { const x=Buffer.from(a,'hex'), y=Buffer.from(b,'hex'); return x.length===y.length && crypto.timingSafeEqual(x,y); } catch { return false; } };
export const secureInt = max => crypto.randomInt(0, max);
