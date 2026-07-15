(() => {
  const graph=document.querySelector('[data-privacy-graph]');
  if(!graph)return;
  const svg=graph.querySelector('.privacy-edges'),origin=graph.querySelector('.privacy-origin'),nodes=[...graph.querySelectorAll('.privacy-node')],reduced=matchMedia('(prefers-reduced-motion: reduce)').matches;
  const lines=nodes.map(()=>{const line=document.createElementNS('http://www.w3.org/2000/svg','line');svg.append(line);return line});
  let visible=true,frame=0;
  const observer=new IntersectionObserver(entries=>{visible=entries[0]?.isIntersecting??true;if(visible&&!frame)frame=requestAnimationFrame(draw)},{rootMargin:'100px'});observer.observe(graph);
  function draw(now=0){
    frame=0;const bounds=graph.getBoundingClientRect(),source=origin.getBoundingClientRect(),sx=source.left-bounds.left+source.width/2,sy=source.top-bounds.top+source.height/2;
    nodes.forEach((node,index)=>{const radius=node.offsetWidth/2,pad=8,baseX=Number(node.dataset.x)*bounds.width,baseY=Number(node.dataset.y)*bounds.height,phase=index*1.37,x=reduced?baseX:baseX+Math.sin(now/1800+phase)*7,y=reduced?baseY:baseY+Math.cos(now/2100+phase)*6,cx=Math.min(bounds.width-radius-pad,Math.max(radius+pad,x)),cy=Math.min(bounds.height-radius-pad,Math.max(radius+pad,y));node.style.left=`${cx-radius}px`;node.style.top=`${cy-radius}px`;lines[index].setAttribute('x1',sx);lines[index].setAttribute('y1',sy);lines[index].setAttribute('x2',cx);lines[index].setAttribute('y2',cy)});
    if(visible&&!reduced)frame=requestAnimationFrame(draw);
  }
  addEventListener('resize',()=>{if(!frame)frame=requestAnimationFrame(draw)});frame=requestAnimationFrame(draw);
})();
