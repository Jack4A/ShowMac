/* First-party aggregate statistics. No visitor identity, cookie or app telemetry. */
(()=>{
  const base=new URL('.',document.currentScript.src);
  const page=location.pathname;
  if(!/^\/(en|zh)\/(?:support\/|privacy\/)?$/.test(page))return;
  const zh=document.documentElement.lang.startsWith('zh');
  const summary=document.querySelector('#site-stats');
  const number=new Intl.NumberFormat(zh?'zh-CN':'en-US');
  const optedOut=navigator.doNotTrack==='1'||navigator.globalPrivacyControl===true;
  let hasTotals=false;

  async function fetchStats(path,options={}){
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),6000);
    try{return await fetch(new URL(path,base),{credentials:'omit',...options,signal:controller.signal});}
    finally{clearTimeout(timeout);}
  }

  function eventID(){
    if(crypto.randomUUID)return crypto.randomUUID();
    // Safari on older supported macOS versions does not expose randomUUID.
    const bytes=crypto.getRandomValues(new Uint8Array(16));
    bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
    const hex=Array.from(bytes,n=>n.toString(16).padStart(2,'0')).join('');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
  }

  async function refresh(){
    if(!summary)return;
    summary.hidden=false;
    const status=summary.querySelector('[data-stats-status]');
    try{
      const response=await fetchStats('api/stats',{cache:'no-store'});
      if(!response.ok)throw new Error('Unavailable');
      const totals=await response.json();
      if(!['pageviews','downloads'].every(key=>Number.isSafeInteger(totals[key])&&totals[key]>=0)||!Number.isFinite(Date.parse(totals.startedAt)))throw new Error('Invalid totals');
      summary.querySelector('[data-total="pageviews"]').textContent=number.format(totals.pageviews);
      summary.querySelector('[data-total="downloads"]').textContent=number.format(totals.downloads);
      const date=new Intl.DateTimeFormat(zh?'zh-CN':'en-US',{year:'numeric',month:'short',day:'numeric',timeZone:'UTC'}).format(new Date(totals.startedAt));
      status.textContent=zh?`自 ${date} 起累计 · 下载按发起次数统计，访问为 PV`:`Since ${date} · Download starts and page views (PV)`;
      hasTotals=true;
    }catch{
      status.textContent=zh?(hasTotals?'统计更新暂不可用':'统计暂不可用'):(hasTotals?'Statistics update unavailable':'Statistics temporarily unavailable');
    }
  }

  async function pageview(){
    if(!optedOut){
      try{
        await fetchStats('api/stats/pageview',{
          method:'POST',keepalive:true,headers:{'Content-Type':'application/json'},
          body:JSON.stringify({id:eventID(),page})
        });
      }catch{/* Page content and downloads remain usable when statistics fail. */}
    }
    await refresh();
  }
  if(document.visibilityState==='hidden'){
    const visible=()=>{if(document.visibilityState!=='hidden'){document.removeEventListener('visibilitychange',visible);void pageview();}};
    document.addEventListener('visibilitychange',visible);
  }else void pageview();
  window.addEventListener('pageshow',event=>{if(event.persisted)void pageview();});

  document.addEventListener('click',event=>{
    const anchor=event.target.closest('a[data-download-arch]');
    if(!anchor)return;
    const arch=anchor.dataset.downloadArch;
    if(!['arm64','x86_64'].includes(arch))return;
    const target=new URL('download/'+arch,base);
    if(!optedOut)target.searchParams.set('event',eventID());
    anchor.href=target.href;
    // Only the redirect endpoint counts downloads; never count the same click here.
    setTimeout(()=>void refresh(),1500);
  });
})();
