(() => {
  'use strict';

  const nav = document.querySelector('[data-liquid-nav]');
  const center = nav?.querySelector('.nav-center');
  const lens = nav?.querySelector('.nav-lens');
  const items = center ? [...center.querySelectorAll('[data-nav-topic]')] : [];
  if (!nav || !center || !lens || !items.length) return;

  const navConfig = { glassThickness:34,bezelWidth:34,ior:1.4,scaleRatio:.72,blur:.35,specularOpacity:.48,specularSat:.2,balancedSpecular:true };
  const lensConfig = { glassThickness:30,bezelWidth:30,ior:1.4,scaleRatio:.92,blur:0,specularOpacity:.58,specularSat:.1,balancedSpecular:true };
  const targets = new Map();
  let defs;

  const clamp=(n,min,max)=>Math.min(max,Math.max(min,n));
  const surface=x=>Math.pow(1-Math.pow(1-x,4),.25);

  function profile(thickness,bezel,ior,samples=128){
    const eta=1/ior,out=new Float64Array(samples);
    for(let i=0;i<samples;i++){
      const x=i/samples,y=surface(x),dx=x<1?.0001:-.0001,deriv=(surface(x+dx)-y)/dx,mag=Math.hypot(deriv,1);
      const nx=-deriv/mag,ny=-1/mag,dot=ny,k=1-eta*eta*(1-dot*dot);
      if(k<0)continue;
      const sq=Math.sqrt(k),rx=-(eta*dot+sq)*nx,ry=eta-(eta*dot+sq)*ny;
      out[i]=rx*((y*bezel+thickness)/ry);
    }
    return out;
  }

  function displacement(w,h,r,bezel,p,maxDisp){
    const canvas=document.createElement('canvas'),ctx=canvas.getContext('2d');canvas.width=w;canvas.height=h;
    const image=ctx.createImageData(w,h),data=image.data;for(let i=0;i<data.length;i+=4){data[i]=128;data[i+1]=128;data[i+3]=255}
    const r2=r*r,r12=(r+1)**2,rb2=Math.max(r-bezel,0)**2,wb=w-r*2,hb=h-r*2,s=p.length;
    for(let py=0;py<h;py++)for(let px=0;px<w;px++){
      const x=px<r?px-r:px>=w-r?px-r-wb:0,y=py<r?py-r:py>=h-r?py-r-hb:0,d2=x*x+y*y;
      if(d2>r12||d2<rb2)continue;const dist=Math.sqrt(d2);if(!dist)continue;
      const opacity=d2<r2?1:1-(dist-r)/(Math.sqrt(r12)-r);if(opacity<=0)continue;
      const index=Math.min((((r-dist)/bezel)*s)|0,s-1),disp=p[index]||0,offset=(py*w+px)*4;
      data[offset]=(128+(-x/dist*disp/maxDisp)*127*opacity+.5)|0;data[offset+1]=(128+(-y/dist*disp/maxDisp)*127*opacity+.5)|0;
    }
    ctx.putImageData(image,0,0);return canvas.toDataURL();
  }

  function specular(w,h,r,bezel,balanced){
    const canvas=document.createElement('canvas'),ctx=canvas.getContext('2d');canvas.width=w;canvas.height=h;
    const image=ctx.createImageData(w,h),data=image.data,r2=r*r,r12=(r+1)**2,rb2=Math.max(r-bezel,0)**2,wb=w-r*2,hb=h-r*2,angle=Math.PI/3,sx=Math.cos(angle),sy=Math.sin(angle);
    for(let py=0;py<h;py++)for(let px=0;px<w;px++){
      const x=px<r?px-r:px>=w-r?px-r-wb:0,y=py<r?py-r:py>=h-r?py-r-hb:0,d2=x*x+y*y;
      if(d2>r12||d2<rb2)continue;const dist=Math.sqrt(d2);if(!dist)continue;
      const side=r-dist,opacity=d2<r2?1:1-(dist-r)/(Math.sqrt(r12)-r);if(opacity<=0)continue;
      const dot=balanced?1:Math.abs(x/dist*sx-y/dist*sy),edge=Math.sqrt(Math.max(0,1-(1-side)**2)),coefficient=dot*edge,color=(255*coefficient)|0,index=(py*w+px)*4;
      data[index]=color;data[index+1]=color;data[index+2]=color;data[index+3]=(color*coefficient*opacity)|0;
    }
    ctx.putImageData(image,0,0);return canvas.toDataURL();
  }

  function svg(tag,attributes){const node=document.createElementNS('http://www.w3.org/2000/svg',tag);Object.entries(attributes).forEach(([key,value])=>node.setAttribute(key,value));return node}
  function ensureDefs(){
    if(defs?.isConnected)return;const root=svg('svg',{width:0,height:0});root.style.cssText='position:fixed;width:0;height:0;pointer-events:none';defs=svg('defs',{});root.append(defs);document.documentElement.append(root);
  }

  function buildFilter(id,w,h,r,cfg){
    const bezel=Math.min(cfg.bezelWidth,r-1,Math.min(w,h)/2-1),p=profile(cfg.glassThickness,bezel,cfg.ior),max=Math.max(...p.map(Math.abs))||1;
    const filter=svg('filter',{id,x:0,y:0,width:w,height:h,filterUnits:'userSpaceOnUse',primitiveUnits:'userSpaceOnUse','color-interpolation-filters':'sRGB'});
    const blur=svg('feGaussianBlur',{in:'SourceGraphic',stdDeviation:cfg.blur,result:'blurred'}),map=svg('feImage',{href:displacement(w,h,r,bezel,p,max),x:0,y:0,width:w,height:h,result:'map'}),displace=svg('feDisplacementMap',{in:'blurred',in2:'map',scale:max*cfg.scaleRatio,xChannelSelector:'R',yChannelSelector:'G',result:'displaced'}),shine=svg('feImage',{href:specular(w,h,r,bezel*2.5,cfg.balancedSpecular),x:0,y:0,width:w,height:h,result:'shine'}),fade=svg('feComponentTransfer',{in:'shine',result:'faded'}),alpha=svg('feFuncA',{type:'linear',slope:cfg.specularOpacity}),blend=svg('feBlend',{in:'faded',in2:'displaced',mode:'normal'});
    fade.append(alpha);filter.append(blur,map,displace,shine,fade,blend);return filter;
  }

  function applyGlass(element,config){
    if(targets.has(element))return targets.get(element);ensureDefs();
    const layer=document.createElement('div');layer.className='lg-layer';layer.style.cssText='position:absolute;inset:0;z-index:0;pointer-events:none;';element.prepend(layer);
    let filter,timer;
    const rebuild=()=>{clearTimeout(timer);timer=setTimeout(()=>{const w=Math.round(element.offsetWidth),h=Math.round(element.offsetHeight);if(w<4||h<4)return;const r=Math.max(2,Math.min(Number(element.dataset.radius)||20,w/2,h/2));filter?.remove();const id=`nav-lg-${Math.random().toString(36).slice(2)}`;filter=buildFilter(id,w,h,r,config);defs.append(filter);layer.style.borderRadius=`${r}px`;layer.style.backdropFilter=`url(#${id})`;layer.style.webkitBackdropFilter=`url(#${id})`;},16)};
    const observer=new ResizeObserver(rebuild);observer.observe(element);const instance={rebuild,destroy(){observer.disconnect();filter?.remove();layer.remove()}};targets.set(element,instance);rebuild();return instance;
  }

  applyGlass(nav,navConfig);applyGlass(lens,lensConfig);

  const threshold=6,overshoot=22;let active=Math.max(0,items.findIndex(item=>item.classList.contains('active'))),target=active,pointer=null,startX=0,startY=0,dragging=false,itemWidth=0,finishTimer;
  const metrics=index=>({left:items[index].offsetLeft,width:items[index].offsetWidth,center:items[index].offsetLeft+items[index].offsetWidth/2});
  const localX=clientX=>{const rect=center.getBoundingClientRect();return(clientX-rect.left)*(center.clientWidth/rect.width)};
  const nearest=x=>items.reduce((best,_,index)=>Math.abs(x-metrics(index).center)<Math.abs(x-metrics(best).center)?index:best,0);
  function setActive(index){active=index;items.forEach((item,i)=>item.classList.toggle('active',i===index))}
  function snap(index,animate=true){const m=metrics(index),old=lens.style.transition;if(!animate)lens.style.transition='none';lens.style.left=`${m.left}px`;lens.style.width=`${m.width}px`;if(!animate){lens.offsetWidth;lens.style.transition=old}targets.get(lens)?.rebuild()}
  function glow(event,alpha){const rect=nav.getBoundingClientRect();nav.style.setProperty('--gx',`${event.clientX-rect.left}px`);nav.style.setProperty('--gy',`${event.clientY-rect.top}px`);nav.style.setProperty('--ga',alpha)}
  function begin(event,index){clearTimeout(finishTimer);pointer=event.pointerId;target=index;startX=event.clientX;startY=event.clientY;itemWidth=metrics(index).width;lens.classList.add('interacting');nav.classList.add('engaged');glow(event,.24);targets.get(lens)?.rebuild();window.addEventListener('pointermove',move);window.addEventListener('pointerup',end);window.addEventListener('pointercancel',cancel)}
  function move(event){if(event.pointerId!==pointer)return;if(!dragging&&(Math.abs(event.clientX-startX)>threshold||Math.abs(event.clientY-startY)>threshold)){dragging=true;center.classList.add('dragging')}glow(event,dragging?.18:.22);if(!dragging)return;const x=localX(event.clientX),left=clamp(x-itemWidth/2,-overshoot,center.clientWidth-itemWidth+overshoot);lens.style.left=`${left}px`;lens.style.width=`${itemWidth}px`;target=nearest(x);targets.get(lens)?.rebuild()}
  function clear(){window.removeEventListener('pointermove',move);window.removeEventListener('pointerup',end);window.removeEventListener('pointercancel',cancel)}
  function settle(){center.classList.remove('dragging');setActive(target);snap(target);finishTimer=setTimeout(()=>{lens.classList.remove('interacting');nav.classList.remove('engaged');nav.style.setProperty('--ga',0)},500)}
  function end(event){if(event.pointerId!==pointer)return;clear();settle();pointer=null;dragging=false}
  function cancel(event){if(event.pointerId!==pointer)return;clear();target=active;snap(active);settle();pointer=null;dragging=false}
  items.forEach((item,index)=>item.addEventListener('pointerdown',event=>{if(!event.isPrimary||event.button!==0)return;event.preventDefault();begin(event,index)}));

  const sections=[document.querySelector('#top'),document.querySelector('#settings'),document.querySelector('#privacy')];let frame=false;
  function sync(){frame=false;if(pointer!==null)return;const marker=scrollY+innerHeight*.28;let index=0;sections.forEach((section,i)=>{if(section&&section.offsetTop<=marker)index=i});target=index;setActive(index);snap(index)}
  addEventListener('scroll',()=>{if(!frame){frame=true;requestAnimationFrame(sync)}},{passive:true});addEventListener('resize',()=>snap(active,false));requestAnimationFrame(()=>snap(active,false));
})();
