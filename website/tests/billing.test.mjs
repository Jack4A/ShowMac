import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../cloudflare/worker.mjs';
import {sandboxConfiguration,sandboxContentPolicy} from '../cloudflare/billing.mjs';

const fixture={PADDLE_SANDBOX_CLIENT_TOKEN:'test_fixture_only_not_a_real_token',PADDLE_SANDBOX_PRICE_USD:'pri_'+'a'.repeat(26),PADDLE_SANDBOX_PRICE_CNY:'pri_'+'b'.repeat(26)};
test('missing configuration cannot enable checkout or expose unrelated secrets',()=>{
  assert.deepEqual(sandboxConfiguration({PADDLE_API_KEY:'private-fixture'},'USD'),{ready:false,environment:'sandbox',currency:'USD'});
});
test('live tokens never enable the sandbox page',()=>{
  assert.equal(sandboxConfiguration({...fixture,PADDLE_SANDBOX_CLIENT_TOKEN:'live_fixture_only_not_real'},'USD').ready,false);
});
test('the two authorized prices retain exact minor units and currency',()=>{
  const usd=sandboxConfiguration(fixture,'USD'),cny=sandboxConfiguration(fixture,'CNY');
  assert.equal(usd.unitAmount,100);assert.equal(cny.unitAmount,590);
  assert.equal(usd.priceId,fixture.PADDLE_SANDBOX_PRICE_USD);assert.equal(cny.priceId,fixture.PADDLE_SANDBOX_PRICE_CNY);
  assert.equal(sandboxConfiguration(fixture,'EUR'),null);
});
test('the configuration endpoint is read-only, validates currency and is never cached',async()=>{
  const valid=await worker.fetch(new Request('https://show-mac.cc/api/billing/sandbox-config?currency=CNY'),fixture);
  assert.equal(valid.status,200);assert.match(valid.headers.get('Cache-Control'),/no-store/);
  assert.equal((await valid.json()).unitAmount,590);
  const invalid=await worker.fetch(new Request('https://show-mac.cc/api/billing/sandbox-config?currency=EUR'),fixture);
  assert.equal(invalid.status,400);
  const post=await worker.fetch(new Request('https://show-mac.cc/api/billing/sandbox-config',{method:'POST'}),fixture);
  assert.equal(post.status,405);assert.equal(post.headers.get('Allow'),'GET');
});
test('Paddle frames are allowed only on the test checkout page',async()=>{
  const env={ASSETS:{fetch:async()=>new Response('fixture',{headers:{'Content-Security-Policy':"default-src 'self'"}})}};
  const ordinary=await worker.fetch(new Request('https://show-mac.cc/zh/'),env);
  assert.equal(ordinary.headers.get('Content-Security-Policy'),"default-src 'self'");
  const checkout=await worker.fetch(new Request('https://show-mac.cc/zh/checkout/'),env);
  assert.equal(checkout.headers.get('Content-Security-Policy'),sandboxContentPolicy);
  assert.match(checkout.headers.get('X-Robots-Tag'),/noindex/);
  assert.match(checkout.headers.get('Cache-Control'),/no-store/);
  assert.match(sandboxContentPolicy,/frame-src https:\/\/sandbox-buy\.paddle\.com;/);
  assert.doesNotMatch(sandboxContentPolicy,/unsafe-eval/);
});
