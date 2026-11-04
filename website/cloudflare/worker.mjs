// Cloudflare Pages advanced mode. No requests to the former mainland origin.
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
