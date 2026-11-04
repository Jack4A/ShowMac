import {test} from 'node:test';
import assert from 'node:assert/strict';
import worker,{chooseLanguage} from '../cloudflare/worker.mjs';

function request(path,{country,headers={}}={}) {
  const req=new Request('https://show-mac.cc'+path,{headers});
  if(country)req.cf={country};
  return req;
}
const env={ASSETS:{fetch:async()=>new Response('asset')}};

test('location, manual selection and browser fallback',()=>{
  assert.equal(chooseLanguage(request('/',{country:'CN'})),'zh');
  assert.equal(chooseLanguage(request('/',{country:'US'})),'en');
  assert.equal(chooseLanguage(request('/',{country:'CN',headers:{Cookie:'showmac_language=en'}})),'en');
  assert.equal(chooseLanguage(request('/',{headers:{'Accept-Language':'zh-CN, en;q=0.8'}})),'zh');
});
test('former payment URLs lead to the free open-source page',async()=>{
  for(const path of ['/purchase/','/checkout/','/zh/purchase/','/en/checkout/?currency=CNY']) {
    const response=await worker.fetch(request(path,{country:'CN'}),env);
    assert.equal(response.status,301);
    assert.equal(response.headers.get('Location'),`https://show-mac.cc/${path.startsWith('/en/')?'en':'zh'}/#opensource`);
  }
  assert.equal((await worker.fetch(request('/api/billing/sandbox-config'),env)).status,410);
});
test('explicit languages and static downloads stay available',async()=>{
  for(const path of ['/en/','/zh/','/downloads/showmac.zip']) {
    assert.equal(await (await worker.fetch(request(path,{country:'CN'}),env)).text(),'asset');
  }
  const response=await worker.fetch(request('/',{country:'CN'}),env);
  assert.equal(response.headers.get('Location'),'https://show-mac.cc/zh/');
});
