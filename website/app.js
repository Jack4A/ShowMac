(() => {
  'use strict';
  const root=document.documentElement;
  const stored=key=>{try{return localStorage.getItem(key);}catch{return null;}};
  const save=(key,value)=>{try{localStorage.setItem(key,value);}catch{}};
  const siteBase=new URL('.',document.currentScript.src);
  const relativePath=location.pathname.slice(siteBase.pathname.length);
  const explicitLanguage=/^(en|zh)(?:\/|$)/.exec(relativePath)?.[1];
  let language=explicitLanguage || (stored('showmac-language')==='zh'?'zh':'en');
  if(!explicitLanguage){
    const manual=stored('showmac-language');
    const fallback=navigator.language?.toLowerCase().startsWith('zh')?'zh':'en';
    const route=value=>location.replace(new URL(value+'/'+relativePath+location.search+location.hash,siteBase));
    if(manual==='en'||manual==='zh')route(manual);
    else fetch(new URL('locale.json',siteBase),{cache:'no-store'}).then(r=>{if(!r.ok)throw Error('locale');return r.json();}).then(data=>route(data.language==='zh'?'zh':'en')).catch(()=>route(fallback));
    return;
  }
  let theme=stored('showmac-theme')==='light'?'light':'dark';
  let screen='overview';
  let release=null;
  let toastTimer;
  const toast=message=>{
    const target=document.querySelector('#toast');if(!target)return;
    target.textContent=message;target.classList.add('visible');clearTimeout(toastTimer);
    toastTimer=setTimeout(()=>target.classList.remove('visible'),3200);
  };
  function setLanguage(value){
    language=value;root.lang=value==='zh'?'zh-CN':'en';
    document.querySelectorAll('[data-en][data-zh]').forEach(el=>{el.innerHTML=el.dataset[value];});
    const toggle=document.querySelector('#language-toggle');
    if(toggle){toggle.textContent=value==='en'?'中文':'EN';toggle.setAttribute('aria-label',value==='en'?'切换到中文':'Switch to English');}
    updateThemeLabel();setScreen(screen);
  }
  function updateThemeLabel(){
    const toggle=document.querySelector('#theme-toggle');
    if(toggle)toggle.setAttribute('aria-label',language==='zh'?(theme==='dark'?'切换到浅色主题':'切换到深色主题'):(theme==='dark'?'Switch to light appearance':'Switch to dark appearance'));
  }
  function setTheme(value){theme=value;root.dataset.theme=value;save('showmac-theme',value);updateThemeLabel();setScreen(screen);}
  function setScreen(value){
    screen=value;
    document.querySelectorAll('[data-product-image]').forEach(img=>{img.src=new URL('assets/'+language+'/'+img.dataset.productImage+'-'+theme+'.png',siteBase);img.alt=language==='zh'?'ShowMac 状态栏弹窗、指标卡片和风扇控制':'ShowMac menu bar panel with live cards and fan controls';});
    const image=document.querySelector('#product-screenshot');
    if(image){
      const files={overview:theme==='dark'?'overview-dark':'overview-light',thermal:'thermal-control',sensors:'sensors',electricity:'electricity-'+theme};
      const names={overview:'ShowMac live metrics with sampled temperature history',thermal:'ShowMac fan presets and editable temperature-to-RPM curve',sensors:'ShowMac sensor overview with readable names and recent trends',electricity:'ShowMac electricity history and cost estimate preview with sample power readings'};
      image.src=new URL('assets/'+language+'/'+files[value]+'.png',siteBase);image.alt=language==='zh'?{overview:'ShowMac 实时监测、温度趋势和当前读数',thermal:'ShowMac 温度控制档位与风扇曲线',sensors:'ShowMac 传感器名称、读数与近期趋势',electricity:'ShowMac 用电统计与电费估算界面预览，使用示例功率数据'}[value]:names[value];
      const label=document.querySelector('#features .window-label');
      if(label)label.textContent=value==='electricity'?(language==='zh'?'界面预览 · 示例功率数据':'UI preview · sample power data'):(language==='zh'?'真实应用界面':'Actual app interface');
      document.querySelectorAll('[data-screen]').forEach(button=>{const active=button.dataset.screen===value;button.classList.toggle('active',active);button.setAttribute('aria-pressed',String(active));});
    }
  }
  document.querySelector('#language-toggle')?.addEventListener('click',()=>{
    const next=language==='en'?'zh':'en';save('showmac-language',next);
    document.cookie='showmac_language='+next+'; Path='+siteBase.pathname+'; Max-Age=31536000; SameSite=Lax'+(location.protocol==='https:'?'; Secure':'');
    location.assign(new URL(relativePath.replace(/^(en|zh)/,next)+location.search+location.hash,siteBase));
  });
  document.querySelector('#theme-toggle')?.addEventListener('click',()=>setTheme(theme==='dark'?'light':'dark'));
  document.querySelectorAll('[data-screen]').forEach(button=>button.addEventListener('click',()=>setScreen(button.dataset.screen)));
  setLanguage(language);setTheme(theme);
  if(document.querySelector('#download-cards')){
    fetch(new URL('release.json',siteBase)).then(response=>{if(!response.ok)throw Error('metadata');return response.json();}).then(data=>{
      release=data;
      Object.entries(data.builds).forEach(([arch,build])=>{
        const label=document.querySelector(`[data-arch-size="${arch}"]`);
        if(label)label.textContent=`v${data.version} · ${(build.bytes/1024/1024).toFixed(1)} MB · macOS ${data.minimumMacOS}+`;
      });
    }).catch(()=>{});
    document.querySelectorAll('.hash-copy').forEach(button=>button.addEventListener('click',async()=>{
      const hash=release?.builds[button.dataset.arch]?.sha256;
      if(!hash){toast(language==='zh'?'请使用下方校验值文件。':'Use the checksum file linked below.');return;}
      let copied=false;
      try{if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(hash);copied=true;}}catch{}
      if(!copied){
        const field=document.createElement('textarea');field.value=hash;field.setAttribute('readonly','');field.style.cssText='position:fixed;top:0;left:-10000px';document.body.append(field);field.select();
        try{copied=document.execCommand('copy');}catch{}field.remove();
      }
      if(copied)toast(language==='zh'?'SHA-256 已复制':'SHA-256 copied');
      else{
        let dialog=document.querySelector('#checksum-dialog');
        if(!dialog){dialog=document.createElement('dialog');dialog.id='checksum-dialog';dialog.innerHTML='<form method="dialog"><h2>SHA-256</h2><textarea readonly aria-label="SHA-256 checksum" rows="3" style="width:100%;min-width:240px;max-width:75vw"></textarea><p></p><button class="button secondary" value="close">Close / 关闭</button></form>';document.body.append(dialog);}
        dialog.querySelector('textarea').value=hash;dialog.querySelector('p').textContent=language==='zh'?'选择并复制校验值。':'Select and copy the checksum.';dialog.showModal();dialog.querySelector('textarea').select();
      }
    }));
  }
  const svg=document.querySelector('#curve-chart');
  if(!svg)return;
  const templates={auto:[[40,10],[55,25],[68,50],[80,78],[90,100]],quiet:[[40,4],[55,12],[68,34],[80,68],[90,100]],balanced:[[40,10],[55,25],[68,50],[80,78],[90,100]],boost:[[40,24],[55,45],[68,67],[80,90],[90,100]]};
  let points=templates.auto.map(p=>[...p]),dragging=null,originalPoints=null;
  const x=t=>65+(t-30)/70*790,y=p=>260-p/100*230;
  const readout=([t,p])=>`${t.toFixed(1)}°C → ${Math.round(1000+p*50)} RPM`;
  function curvePercent(t){
    if(t<=points[0][0])return points[0][1];
    for(let i=1;i<points.length;i++)if(t<=points[i][0]){
      const [a,b]=points[i-1],[c,d]=points[i];return b+(d-b)*(t-a)/(c-a);
    }
    return points[points.length-1][1];
  }
  function renderSources(){
    const controls=[...document.querySelectorAll('[data-curve-source]')];
    const selected=controls.filter(input=>input.checked);
    controls.forEach(input=>{input.disabled=selected.length===1&&input.checked;});
    if(!selected.length)return;
    const temperature=Math.max(...selected.map(input=>Number(input.value)));
    const percent=curvePercent(temperature);
    document.querySelector('#curve-source-readout').textContent=(selected.length>1?'MAX':selected[0].dataset.curveSource)+` ${readout([temperature,percent])}`;
    const marker=document.querySelector('#curve-input-marker');marker.setAttribute('cx',x(temperature));marker.setAttribute('cy',y(percent));
  }
  function selectMode(mode){document.querySelectorAll('[data-mode]').forEach(b=>{const active=b.dataset.mode===mode;b.classList.toggle('selected',active);b.setAttribute('aria-pressed',String(active));});}
  function render(){
    const positions=points.map(([t,p])=>[x(t),y(p)]);
    document.querySelector('#curve-path').setAttribute('d',positions.map(([a,b],i)=>(i?'L':'M')+a.toFixed(1)+' '+b.toFixed(1)).join(' '));
    document.querySelector('#curve-area').setAttribute('d',`M${positions[0][0]} 260 `+positions.map(([a,b])=>`L${a} ${b}`).join(' ')+` L${positions[positions.length-1][0]} 260 Z`);
    handles.forEach((handle,i)=>{const [t,p]=points[i];handle.setAttribute('cx',x(t));handle.setAttribute('cy',y(p));handle.setAttribute('aria-label',(language==='zh'?`控制点 ${i+1}：`:`Point ${i+1}: `)+readout([t,p]));handle.setAttribute('aria-valuenow',Math.round(1000+p*50));});
    renderSources();
  }
  function update(index,t,p){
    const last=index===points.length-1;
    if(last&&originalPoints)points=originalPoints.map(point=>[...point]);
    const lowerT=index?points[index-1][0]+2:30,upperT=last?90:points[index+1][0]-2;
    const lowerP=index&&!last?points[index-1][1]:0,upperP=last?100:points[index+1][1];
    points[index]=[Math.min(upperT,Math.max(lowerT,t)),Math.min(upperP,Math.max(lowerP,p))];
    if(last)for(let i=0;i<index;i++)points[i][1]=Math.min(points[i][1],points[index][1]);
    document.querySelector('#curve-readout').textContent=readout(points[index]);selectMode('custom');render();
  }
  const handles=points.map((point,index)=>{
    const handle=document.createElementNS('http://www.w3.org/2000/svg','circle');handle.classList.add('curve-handle');handle.setAttribute('r','7');handle.setAttribute('tabindex','0');handle.setAttribute('role','slider');handle.setAttribute('aria-valuemin','1000');handle.setAttribute('aria-valuemax','6000');
    handle.addEventListener('pointerdown',event=>{event.preventDefault();dragging=index;originalPoints=points.map(point=>[...point]);handle.setPointerCapture(event.pointerId);handle.focus();});
    handle.addEventListener('pointermove',event=>{if(dragging!==index)return;const matrix=svg.getScreenCTM();if(!matrix)return;const location=new DOMPoint(event.clientX,event.clientY).matrixTransform(matrix.inverse());update(index,30+(location.x-65)/790*70,(260-location.y)/230*100);});
    for(const type of ['pointerup','pointercancel','lostpointercapture'])handle.addEventListener(type,()=>{dragging=null;originalPoints=null;});
    handle.addEventListener('keydown',event=>{const [t,p]=points[index];const movement={ArrowLeft:[t-0.1,p],ArrowRight:[t+0.1,p],ArrowUp:[t,p+1],ArrowDown:[t,p-1]}[event.key];if(movement){event.preventDefault();update(index,...movement);}});
    document.querySelector('#curve-handles').append(handle);return handle;
  });
  document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>{const mode=button.dataset.mode;if(templates[mode])points=templates[mode].map(p=>[...p]);selectMode(mode);document.querySelector('#curve-readout').textContent=readout(points[2]);render();}));
  document.querySelectorAll('[data-curve-source]').forEach(input=>input.addEventListener('change',renderSources));
  render();
})();
