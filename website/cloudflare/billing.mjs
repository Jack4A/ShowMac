// Sandbox integration only. Live checkout and license fulfillment are deliberately
// unavailable until seller approval and verified server-side delivery are ready.
export function sandboxConfiguration(env,currency) {
  if(!['CNY','USD'].includes(currency))return null;
  const clientToken=env.PADDLE_SANDBOX_CLIENT_TOKEN;
  const priceId=env['PADDLE_SANDBOX_PRICE_'+currency];
  const ready=typeof clientToken==='string' && /^test_[a-zA-Z0-9_]{10,150}$/.test(clientToken)
    && typeof priceId==='string' && /^pri_[a-z0-9]{26}$/.test(priceId);
  if(!ready)return {ready:false,environment:'sandbox',currency};
  return {ready:true,environment:'sandbox',clientToken,priceId,currency,unitAmount:currency==='CNY'?590:100};
}

export const sandboxContentPolicy="default-src 'self'; script-src 'self' https://cdn.paddle.com; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' https://*.paddle.com; frame-src https://sandbox-buy.paddle.com; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'none'";
