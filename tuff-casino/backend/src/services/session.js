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
