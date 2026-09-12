import { PaymentAdapter } from './base.js';
import { config } from '../../config.js';
import { hmacHex, safeEqualHex } from '../../utils/crypto.js';
import { HttpError } from '../../utils/http.js';
export class MockPaymentAdapter extends PaymentAdapter {
  async createInvoice(payment){if(!config.testMode)throw new HttpError(503,'Mock payments disabled');return {externalId:`mock_${payment.id}`,url:null,status:'pending'};}
  verifyAndNormalizeWebhook(raw,headers){if(!config.testMode)throw new HttpError(503,'Mock webhook disabled');if(!config.paymentWebhookSecret)throw new HttpError(503,'PAYMENT_WEBHOOK_SECRET is required for test webhook');const signature=headers['x-payment-signature']||'';if(!safeEqualHex(signature,hmacHex(config.paymentWebhookSecret,raw)))throw new HttpError(401,'Invalid webhook signature');let body;try{body=JSON.parse(raw)}catch{throw new HttpError(400,'Invalid webhook JSON')}return {externalId:body.externalId,status:body.status,amount:String(body.amount),asset:body.asset,network:body.network,eventId:body.eventId||body.externalId};}
}
