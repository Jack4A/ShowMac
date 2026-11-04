// Cloudflare Pages advanced mode. No requests to the former mainland origin.
export function chooseLanguage(request) {
  const manual=/(?:^|;\s*)showmac_language=(en|zh)(?:;|$)/.exec(request.headers.get('Cookie')||'')?.[1];
  if(manual)return manual;
  const country=request.cf?.country;
  if(['CN','HK','MO','TW'].includes(country))return 'zh';
  if(country && !['XX','T1'].includes(country))return 'en';
  return /^zh\b/i.test(request.headers.get('Accept-Language')||'')?'zh':'en';
}

const STATS_HEADERS={'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
const PAGES=new Set(['/en/','/zh/','/en/support/','/zh/support/','/en/privacy/','/zh/privacy/']);
const ARCHITECTURES=new Set(['arm64','x86_64']);
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function canRecord(request,env) {
  const host=new URL(request.url).hostname;
  // Production data must never include preview deployments or local QA.
  if(host!=='show-mac.cc' && !(env.STATS_ENV==='local' && ['localhost','127.0.0.1'].includes(host)))return false;
  if(request.headers.get('DNT')==='1'||request.headers.get('Sec-GPC')==='1')return false;
  if(/prefetch|prerender/i.test([request.headers.get('Purpose'),request.headers.get('Sec-Purpose')].join(' ')))return false;
  if(request.cf?.botManagement?.verifiedBot)return false;
  return !/bot|spider|crawler|headless|facebookexternalhit|slackbot|preview|curl|wget/i.test(request.headers.get('User-Agent')||'');
}

async function recordEvent(env,id,kind,bucket) {
  await env.STATS_DB.prepare(
    'INSERT OR IGNORE INTO stats_events (id, kind, bucket, created_at) VALUES (?, ?, ?, ?)'
  ).bind(id,kind,bucket,Math.floor(Date.now()/1000)).run();
}

async function statistics(request,env) {
  const path=new URL(request.url).pathname;
  if(path==='/api/stats') {
    if(request.method!=='GET')return new Response(null,{status:405,headers:{...STATS_HEADERS,Allow:'GET'}});
    if(!env.STATS_DB)return new Response('Statistics unavailable',{status:503,headers:STATS_HEADERS});
    try {
      const results=await env.STATS_DB.batch([
        env.STATS_DB.prepare('SELECT value FROM stats_meta WHERE key = ?').bind('started_at'),
        env.STATS_DB.prepare('SELECT kind, bucket, count FROM stats_counters')
      ]);
      const startedAt=results[0].results[0]?.value;
      if(!startedAt)throw new Error('Uninitialized statistics');
      const pages=Object.fromEntries([...PAGES].map(page=>[page,0]));
      const downloadsByArchitecture={arm64:0,x86_64:0};
      for(const row of results[1].results) {
        if(row.kind==='pageview'&&PAGES.has(row.bucket))pages[row.bucket]=row.count;
        if(row.kind==='download'&&ARCHITECTURES.has(row.bucket))downloadsByArchitecture[row.bucket]=row.count;
      }
      return Response.json({startedAt,pageviews:Object.values(pages).reduce((a,b)=>a+b,0),
        downloads:Object.values(downloadsByArchitecture).reduce((a,b)=>a+b,0),pages,downloadsByArchitecture},
        {headers:STATS_HEADERS});
    }catch{return new Response('Statistics unavailable',{status:503,headers:STATS_HEADERS});}
  }
  if(path!=='/api/stats/pageview')return new Response('Not found',{status:404,headers:STATS_HEADERS});
  if(request.method!=='POST')return new Response(null,{status:405,headers:{...STATS_HEADERS,Allow:'POST'}});
  if(request.headers.get('Origin')!==new URL(request.url).origin)return new Response('Forbidden',{status:403,headers:STATS_HEADERS});
  if(!canRecord(request,env))return new Response(null,{status:204,headers:STATS_HEADERS});
  if(!/^application\/json\b/i.test(request.headers.get('Content-Type')||''))return new Response('Expected JSON',{status:415,headers:STATS_HEADERS});
  // Bound both advertised and actual payload size, without buffering an unbounded body.
  if(Number(request.headers.get('Content-Length'))>1024)return new Response('Payload too large',{status:413,headers:STATS_HEADERS});
  let payload;
  try {
    const reader=request.body?.getReader();
    if(!reader)throw new Error('No body');
    let bytes=0,body='';const decoder=new TextDecoder();
    while(true) {
      const {done,value}=await reader.read();if(done)break;
      bytes+=value.byteLength;
      if(bytes>1024){await reader.cancel();return new Response('Payload too large',{status:413,headers:STATS_HEADERS});}
      body+=decoder.decode(value,{stream:true});
    }
    payload=JSON.parse(body+decoder.decode());
    if(!payload||typeof payload.id!=='string'||!UUID.test(payload.id)||!PAGES.has(payload.page)||Object.keys(payload).some(key=>!['id','page'].includes(key)))throw new Error('Invalid event');
  }catch{return new Response('Invalid event',{status:400,headers:STATS_HEADERS});}
  if(!env.STATS_DB)return new Response('Statistics unavailable',{status:503,headers:STATS_HEADERS});
  try{await recordEvent(env,payload.id,'pageview',payload.page);}
  catch{return new Response('Statistics unavailable',{status:503,headers:STATS_HEADERS});}
  return new Response(null,{status:204,headers:STATS_HEADERS});
}

async function download(request,env,ctx,architecture) {
  if(!ARCHITECTURES.has(architecture))return new Response('Not found',{status:404,headers:STATS_HEADERS});
  if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:{...STATS_HEADERS,Allow:'GET, HEAD'}});
  let file;
  try {
    const metadata=await env.ASSETS.fetch(new Request(new URL('/release.json',request.url)));
    if(!metadata.ok)throw new Error('Release unavailable');
    file=(await metadata.json()).builds?.[architecture]?.file;
    if(typeof file!=='string'||!new RegExp('^showmac-[0-9]+\\.[0-9]+\\.[0-9]+-macOS-'+architecture+'\\.zip$').test(file))throw new Error('Invalid release file');
  }catch{return new Response('Download temporarily unavailable',{status:503,headers:STATS_HEADERS});}
  if(request.method==='GET'&&env.STATS_DB&&canRecord(request,env)) {
    const supplied=new URL(request.url).searchParams.get('event');
    const id=UUID.test(supplied||'')?supplied:crypto.randomUUID();
    // Statistics must not delay or break delivery of the unchanged release archive.
    const write=recordEvent(env,id,'download',architecture).catch(()=>{});
    if(ctx?.waitUntil)ctx.waitUntil(write);else await write;
  }
  return new Response(null,{status:302,headers:{...STATS_HEADERS,Location:new URL('/downloads/'+file,request.url).toString()}});
}

export default {
  async fetch(request,env,ctx) {
    const url=new URL(request.url);
    if(url.hostname==='www.show-mac.cc') {
      url.hostname='show-mac.cc';return Response.redirect(url,301);
    }
    if(url.pathname==='/api/stats'||url.pathname.startsWith('/api/stats/'))return statistics(request,env);
    if(url.pathname.startsWith('/download/'))return download(request,env,ctx,url.pathname.slice('/download/'.length));
    const language=chooseLanguage(request);
    const headers={'Cache-Control':'private, no-store','Vary':'Cookie, Accept-Language','X-Content-Type-Options':'nosniff'};
    if(url.pathname.startsWith('/api/billing/'))return new Response('Payments are no longer offered.',{status:410,headers});
    const legacy=/^\/(?:(en|zh)\/)?(?:purchase|checkout)\/?$/.exec(url.pathname);
    if(legacy) {
      url.pathname='/'+(legacy[1]||language)+'/';url.search='';url.hash='opensource';
      return new Response(null,{status:301,headers:{...headers,Location:url.toString()}});
    }
    if(url.pathname==='/locale.json')return Response.json({language,country:request.cf?.country||''},{headers});
    if(['/', '/support/', '/privacy/'].includes(url.pathname)) {
      url.pathname='/'+language+url.pathname;
      return new Response(null,{status:302,headers:{...headers,Location:url.toString()}});
    }
    if(url.pathname==='/showmac'||url.pathname.startsWith('/showmac/')) {
      url.pathname=url.pathname.slice(8)||'/';return Response.redirect(url,301);
    }
    return env.ASSETS.fetch(request);
  }
};
