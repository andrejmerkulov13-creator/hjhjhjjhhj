import { HttpError } from '../utils/http.js';
export function keyFrom(req){const key=req.get('Idempotency-Key');if(!key||key.length<16||key.length>200)throw new HttpError(400,'Valid Idempotency-Key is required','IDEMPOTENCY_KEY_REQUIRED');return key;}
export async function findIdempotency(c,userId,scope,key){return (await c.query(`SELECT response_status,response_body FROM idempotency_keys WHERE user_id=$1 AND scope=$2 AND idempotency_key=$3`,[userId,scope,key])).rows[0]||null}
export async function saveIdempotency(c,userId,scope,key,status,body){await c.query(`INSERT INTO idempotency_keys(user_id,scope,idempotency_key,response_status,response_body) VALUES($1,$2,$3,$4,$5)`,[userId,scope,key,status,body]);}
