(() => {
  'use strict';
  const button=document.querySelector('#checkout-open');
  const status=document.querySelector('#checkout-status');
  if(!button||!status)return;
  const zh=document.documentElement.lang.startsWith('zh');
  const currency=zh?'CNY':'USD';
  const say=(en,cn)=>{status.textContent=zh?cn:en;};
  let config=null,initializing=null,paddle=null,opening=false;
  function loadSDK(){
    return new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src='https://cdn.paddle.com/paddle/v2/paddle.js';
      script.onload=()=>window.Paddle?resolve(window.Paddle):reject(Error('sdk'));
      script.onerror=()=>{script.remove();reject(Error('sdk'));};
      document.head.append(script);
    });
  }
  async function initialize(){
    const sdk=await loadSDK();
    sdk.Environment.set('sandbox');
    sdk.Initialize({token:config.clientToken,eventCallback:event=>{
      if(event.name==='checkout.completed') {
        say('Sandbox checkout reports completion. Confirm the test transaction in Paddle. No real payment or license delivery has occurred.','沙盒结账已报告完成，请在 Paddle 后台核对测试订单。没有真实扣款，也未交付正式授权。');
      } else if(event.name==='checkout.error'||event.name==='checkout.payment.failed') {
        say('The test checkout did not complete. Try again or check the sandbox configuration.','测试结账未完成，请重试或检查沙盒配置。');
      } else if(event.name==='checkout.closed') {
        opening=false;button.disabled=false;
      }
    }});
    return sdk;
  }
  fetch(new URL('/api/billing/sandbox-config?currency='+currency,location.origin),{cache:'no-store'})
    .then(r=>{if(!r.ok)throw Error('config');return r.json();})
    .then(value=>{
      if(value.ready!==true||value.environment!=='sandbox'||!/^test_[a-zA-Z0-9_]{10,150}$/.test(value.clientToken||'')||!/^pri_[a-z0-9]{26}$/.test(value.priceId||'')||value.currency!==currency||value.unitAmount!==(zh?590:100))throw Error('config');
      config=value;button.disabled=false;
      say('Sandbox settings are configured. Click to connect to Paddle test checkout. Only use test payment details.','沙盒参数已配置，点击后连接 Paddle 测试结账。请仅使用测试支付资料。');
    }).catch(()=>say('The sandbox account and test prices have not been connected yet. Checkout stays disabled.','尚未连接沙盒账户和测试价格，测试支付暂未启用。'));
  button.addEventListener('click',async()=>{
    if(!config||opening)return;
    opening=true;button.disabled=true;
    say('Opening test checkout…','正在打开测试结账…');
    try {
      if(!initializing)initializing=initialize();
      paddle=await initializing;
      paddle.Checkout.open({items:[{priceId:config.priceId,quantity:1}],settings:{displayMode:'overlay',locale:zh?'zh-Hans':'en',theme:document.documentElement.dataset.theme==='light'?'light':'dark',showAddTaxId:false}});
    } catch {
      opening=false;button.disabled=false;
      say('Could not open the test checkout. Check the connection and sandbox settings, then reload.','无法打开测试结账，请检查网络和沙盒配置后刷新页面。');
    }
  });
})();
