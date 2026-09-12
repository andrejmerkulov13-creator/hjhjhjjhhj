import { config } from '../../config.js';
import { MockPaymentAdapter } from './mock.js';
export function paymentAdapter(){if(config.paymentProvider==='mock')return new MockPaymentAdapter();throw new Error(`Payment provider adapter '${config.paymentProvider}' is not installed. Implement it in services/payments/.`)}
