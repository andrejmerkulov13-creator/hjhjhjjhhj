import { pool } from '../db.js';
import { sha256 } from '../utils/crypto.js';
import { HttpError, asyncRoute } from '../utils/http.js';
export const requireAuth=asyncRoute(async(req,res,next)=>{const token=req.cookies?.tuff_session;if(!token)throw new HttpError(401,'Authentication required','AUTH_REQUIRED');const row=(await pool.query(`SELECT s.user_id FROM sessions s WHERE s.token_hash=$1 AND s.revoked_at IS NULL AND s.expires_at>now()`,[sha256(token)])).rows[0];if(!row)throw new HttpError(401,'Session expired','SESSION_EXPIRED');req.userId=row.user_id;next()});
