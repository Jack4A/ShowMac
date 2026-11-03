(() => {
  'use strict';
  const root=document.documentElement;
  const stored=key=>{try{return localStorage.getItem(key);}catch{return null;}};
  const save=(key,value)=>{try{localStorage.setItem(key,value);}catch{}};
  let language=stored('showmac-language')==='zh'?'zh':'en';
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
    language=value;root.lang=value==='zh'?'zh-CN':'en';save('showmac-language',value);
    document.querySelectorAll('[data-en][data-zh]').forEach(el=>{el.innerHTML=el.dataset[value];});
    const toggle=document.querySelector('#language-toggle');
    if(toggle){toggle.textContent=value==='en'?'中文':'EN';toggle.setAttribute('aria-label',value==='en'?'切换到中文':'Switch to English');}
    updateThemeLabel();
  }
  function updateThemeLabel(){
    const toggle=document.querySelector('#theme-toggle');
    if(toggle)toggle.setAttribute('aria-label',language==='zh'?(theme==='dark'?'切换到浅色主题':'切换到深色主题'):(theme==='dark'?'Switch to light appearance':'Switch to dark appearance'));
  }
  function setTheme(value){theme=value;root.dataset.theme=value;save('showmac-theme',value);updateThemeLabel();setScreen(screen);}
  function setScreen(value){
    screen=value;
    const image=document.querySelector('#product-screenshot');
    if(image){
      const files={overview:theme==='dark'?'overview-dark':'overview-light',thermal:'thermal-control',sensors:'sensors'};
      const names={overview:'ShowMac live metrics with sampled temperature history',thermal:'ShowMac fan presets and editable temperature-to-RPM curve',sensors:'ShowMac sensor overview with readable names and recent trends'};
      image.src='assets/'+files[value]+'.png';image.alt=names[value];
      document.querySelectorAll('[data-screen]').forEach(button=>{const active=button.dataset.screen===value;button.classList.toggle('active',active);button.setAttribute('aria-pressed',String(active));});
    }
  }
  document.querySelector('#language-toggle')?.addEventListener('click',()=>setLanguage(language==='en'?'zh':'en'));
  document.querySelector('#theme-toggle')?.addEventListener('click',()=>setTheme(theme==='dark'?'light':'dark'));
  document.querySelectorAll('[data-screen]').forEach(button=>button.addEventListener('click',()=>setScreen(button.dataset.screen)));
  setLanguage(language);setTheme(theme);
  if(document.querySelector('#download-cards')){
    fetch('release.json').then(response=>{if(!response.ok)throw Error('metadata');return response.json();}).then(data=>{
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
  let points=templates.auto.map(p=>[...p]),dragging=null;
  const x=t=>65+(t-30)/70*790,y=p=>260-p/100*230;
  function selectMode(mode){document.querySelectorAll('[data-mode]').forEach(b=>{const active=b.dataset.mode===mode;b.classList.toggle('selected',active);b.setAttribute('aria-pressed',String(active));});}
  function render(){
    const positions=points.map(([t,p])=>[x(t),y(p)]);
    document.querySelector('#curve-path').setAttribute('d',positions.map(([a,b],i)=>(i?'L':'M')+a.toFixed(1)+' '+b.toFixed(1)).join(' '));
    document.querySelector('#curve-area').setAttribute('d',`M${positions[0][0]} 260 `+positions.map(([a,b])=>`L${a} ${b}`).join(' ')+` L${positions[positions.length-1][0]} 260 Z`);
    handles.forEach((handle,i)=>{const [t,p]=points[i];handle.setAttribute('cx',x(t));handle.setAttribute('cy',y(p));handle.setAttribute('aria-label',`Point ${i+1}: ${t}°C, ${1000+p*50} RPM`);handle.setAttribute('aria-valuenow',1000+p*50);});
  }
  function update(index,t,p){
    const lowerT=index?points[index-1][0]+2:30,upperT=index===points.length-1?95:points[index+1][0]-2;
    const lowerP=index?points[index-1][1]:0,upperP=index===points.length-1?100:points[index+1][1];
    points[index]=[Math.round(Math.min(upperT,Math.max(lowerT,t))),index===points.length-1?100:Math.round(Math.min(upperP,Math.max(lowerP,p)))];
    const point=points[index];document.querySelector('#curve-readout').textContent=`${point[0]}°C → ${1000+point[1]*50} RPM`;selectMode('custom');render();
  }
  const handles=points.map((point,index)=>{
    const handle=document.createElementNS('http://www.w3.org/2000/svg','circle');handle.classList.add('curve-handle');handle.setAttribute('r','7');handle.setAttribute('tabindex','0');handle.setAttribute('role','slider');handle.setAttribute('aria-valuemin','1000');handle.setAttribute('aria-valuemax','6000');
    handle.addEventListener('pointerdown',event=>{event.preventDefault();dragging=index;handle.setPointerCapture(event.pointerId);handle.focus();});
    handle.addEventListener('pointermove',event=>{if(dragging!==index)return;const matrix=svg.getScreenCTM();if(!matrix)return;const location=new DOMPoint(event.clientX,event.clientY).matrixTransform(matrix.inverse());update(index,30+(location.x-65)/790*70,(260-location.y)/230*100);});
    for(const type of ['pointerup','pointercancel','lostpointercapture'])handle.addEventListener(type,()=>{dragging=null;});
    handle.addEventListener('keydown',event=>{const [t,p]=points[index];const movement={ArrowLeft:[t-1,p],ArrowRight:[t+1,p],ArrowUp:[t,p+2],ArrowDown:[t,p-2]}[event.key];if(movement){event.preventDefault();update(index,...movement);}});
    document.querySelector('#curve-handles').append(handle);return handle;
  });
  document.querySelectorAll('[data-mode]').forEach(button=>button.addEventListener('click',()=>{const mode=button.dataset.mode;if(templates[mode])points=templates[mode].map(p=>[...p]);selectMode(mode);const [t,p]=points[2];document.querySelector('#curve-readout').textContent=`${t}°C → ${1000+p*50} RPM`;render();}));
  render();
})();
