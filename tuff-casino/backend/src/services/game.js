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
  // Встроенная математика предназначена исключительно для TEST_MODE.
  // В production замените её сертифицированным game/RNG provider adapter.
  if(!config.testMode) throw new HttpError(503,'Native game engine is disabled outside TEST_MODE','GAME_PROVIDER_REQUIRED');
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
