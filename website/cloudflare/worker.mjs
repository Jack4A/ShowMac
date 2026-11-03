// Cloudflare Pages advanced mode. No requests to the former mainland origin.
import {sandboxConfiguration,sandboxContentPolicy} from './billing.mjs';
export function chooseLanguage(request) {
  const manual=/(?:^|;\s*)showmac_language=(en|zh)(?:;|$)/.exec(request.headers.get('Cookie')||'')?.[1];
  if(manual)return manual;
  const country=request.cf?.country;
  if(['CN','HK','MO','TW'].includes(country))return 'zh';
  if(country && !['XX','T1'].includes(country))return 'en';
  return /^zh\b/i.test(request.headers.get('Accept-Language')||'')?'zh':'en';
}
export default {
  async fetch(request,env) {
    const url=new URL(request.url);
    if(url.hostname==='www.show-mac.cc') {
      url.hostname='show-mac.cc';return Response.redirect(url,301);
    }
    const language=chooseLanguage(request);
    const headers={'Cache-Control':'private, no-store','Vary':'Cookie, Accept-Language','X-Content-Type-Options':'nosniff'};
    if(url.pathname==='/api/billing/sandbox-config') {
      if(request.method!=='GET')return new Response(null,{status:405,headers:{...headers,Allow:'GET'}});
      const config=sandboxConfiguration(env,url.searchParams.get('currency')||'USD');
      return Response.json(config||{error:'unsupported_currency'},{status:config?200:400,headers});
    }
    if(url.pathname==='/locale.json')return Response.json({language,country:request.cf?.country||''},{headers});
    if(['/', '/support/', '/privacy/', '/purchase/', '/checkout/'].includes(url.pathname)) {
      url.pathname='/'+language+url.pathname;
      return new Response(null,{status:302,headers:{...headers,Location:url.toString()}});
    }
    if(url.pathname==='/showmac'||url.pathname.startsWith('/showmac/')) {
      url.pathname=url.pathname.slice(8)||'/';return Response.redirect(url,301);
    }
    if(/^\/(en|zh)\/checkout\/?$/.test(url.pathname)) {
      const asset=await env.ASSETS.fetch(request);
      const response=new Response(asset.body,asset);
      response.headers.set('Content-Security-Policy',sandboxContentPolicy);
      response.headers.set('X-Robots-Tag','noindex, nofollow');
      response.headers.set('Cache-Control','private, no-store');
      return response;
    }
    return env.ASSETS.fetch(request);
  }
};
