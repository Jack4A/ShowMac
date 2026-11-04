import {test} from 'node:test';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import worker from '../cloudflare/worker.mjs';

if(!globalThis.crypto)globalThis.crypto=webcrypto;
const id='7c2825fb-8460-4d9e-a7d1-6130119f180e';
const startedAt='2026-11-04T00:00:00Z';
function request(path,{method='GET',headers={},body,host='show-mac.cc'}={}) {
  return new Request(`https://${host}${path}`,{method,headers,body});
}
function pageview(options={}) {
  return request('/api/stats/pageview',{method:'POST',headers:{Origin:'https://show-mac.cc','Content-Type':'application/json',...options.headers},
    body:JSON.stringify({id,page:'/zh/',...options.payload}),...Object.fromEntries(Object.entries(options).filter(([key])=>!['headers','payload'].includes(key)))});
}
function environment({fail=false,rows=[],file='showmac-1.18.3-macOS-arm64.zip'}={}) {
  const recorded=[];
  return {recorded,ASSETS:{fetch:async req=>{
    assert.equal(new URL(req.url).pathname,'/release.json');
    return Response.json({builds:{arm64:{file}}});
  }},STATS_DB:{prepare:sql=>({bind:(...args)=>({run:async()=>{
    if(fail)throw new Error('Database unavailable');
    recorded.push({sql,args});
  }})}),batch:async()=>{
    if(fail)throw new Error('Database unavailable');
    return [{results:[{value:startedAt}]},{results:rows}];
  }}};
}

test('only canonical, same-origin, bounded page-view events are accepted',async()=>{
  const env=environment();
  assert.equal((await worker.fetch(pageview(),env)).status,204);
  assert.deepEqual(env.recorded[0].args.slice(0,3),[id,'pageview','/zh/']);
  for(const invalid of [
    pageview({headers:{Origin:'https://other.example'}}),
    pageview({payload:{page:'/zh/?email=private'}}),
    pageview({payload:{page:'/downloads/a.zip'}}),
    pageview({payload:{id:'visitor@example.com'}}),
    pageview({payload:{id:[id]}}),
    pageview({payload:{visitor:'private'}}),
    pageview({body:'{'}),
    pageview({body:'x'.repeat(1025)})
  ])assert.ok((await worker.fetch(invalid,env)).status>=400);
  assert.equal(env.recorded.length,1);
  assert.equal((await worker.fetch(pageview({headers:{'Content-Type':'text/plain'}}),env)).status,415);
  assert.equal((await worker.fetch(request('/api/stats/pageview'),env)).status,405);
  assert.equal((await worker.fetch(request('/api/stats/unknown'),env)).status,404);
});

test('privacy signals, robots, preloads and deployed previews never write counters',async()=>{
  const env=environment();
  for(const headers of [{'DNT':'1'},{'Sec-GPC':'1'},{Purpose:'prefetch'},{'Sec-Purpose':'prefetch;prerender'},{'User-Agent':'Googlebot'}]) {
    assert.equal((await worker.fetch(pageview({headers}),env)).status,204);
  }
  const verified=pageview();verified.cf={botManagement:{verifiedBot:true}};
  assert.equal((await worker.fetch(verified,env)).status,204);
  assert.equal((await worker.fetch(pageview({host:'preview.showmac.pages.dev',headers:{Origin:'https://preview.showmac.pages.dev'}}),env)).status,204);
  assert.equal(env.recorded.length,0);
});

test('summary keeps language/page and architecture counts and reports genuine outages',async()=>{
  const env=environment({rows:[{kind:'pageview',bucket:'/en/',count:5},{kind:'pageview',bucket:'/zh/privacy/',count:2},
    {kind:'download',bucket:'arm64',count:3},{kind:'download',bucket:'x86_64',count:4}]});
  const result=await worker.fetch(request('/api/stats'),env);
  assert.equal(result.headers.get('Cache-Control'),'no-store');
  const totals=await result.json();
  assert.equal(totals.startedAt,startedAt);
  assert.equal(totals.pageviews,7);assert.equal(totals.downloads,7);
  assert.equal(totals.pages['/en/'],5);assert.equal(totals.pages['/zh/privacy/'],2);
  assert.deepEqual(totals.downloadsByArchitecture,{arm64:3,x86_64:4});
  for(const broken of [{},environment({fail:true})]) {
    assert.equal((await worker.fetch(request('/api/stats'),broken)).status,503);
    assert.equal((await worker.fetch(pageview(),broken)).status,503);
  }
});

test('download start counts once at the redirect, preserving verified file delivery',async()=>{
  const env=environment();
  const pending=[];
  const result=await worker.fetch(request('/download/arm64?event='+id),env,{waitUntil:promise=>pending.push(promise)});
  assert.equal(result.status,302);
  assert.equal(result.headers.get('Location'),'https://show-mac.cc/downloads/showmac-1.18.3-macOS-arm64.zip');
  assert.equal(result.headers.get('Cache-Control'),'no-store');
  await Promise.all(pending);
  assert.deepEqual(env.recorded[0].args.slice(0,3),[id,'download','arm64']);
  for(const options of [{method:'HEAD'},{headers:{DNT:'1'}},{headers:{'Sec-Purpose':'prefetch'}}]) {
    assert.equal((await worker.fetch(request('/download/arm64',options),env)).status,302);
  }
  assert.equal(env.recorded.length,1);
  assert.equal((await worker.fetch(request('/download/arm64'),environment({fail:true}))).status,302);
  const missing=environment();delete missing.STATS_DB;
  assert.equal((await worker.fetch(request('/download/arm64'),missing)).status,302);
  assert.equal((await worker.fetch(request('/download/other'),env)).status,404);
  assert.equal((await worker.fetch(request('/download/arm64',{method:'POST'}),env)).status,405);
  for(const file of ['https://example.com/evil.zip','../secrets','showmac-1.18.3-macOS-x86_64.zip']) {
    assert.equal((await worker.fetch(request('/download/arm64'),environment({file}))).status,503);
  }
});
