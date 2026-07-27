import React from 'react';

export function ScreenshotFrame({src,alt='',caption,theme='light',style,children}){
  return (
    <figure style={{margin:0,...style}}>
      <div data-theme={theme} style={{borderRadius:'var(--radius-frame)',overflow:'hidden',
        background:'var(--surface-page)',border:'1px solid var(--border-hairline)',
        boxShadow:'var(--shadow-frame)'}}>
        {children||<img src={src} alt={alt} style={{display:'block',width:'100%',height:'auto'}}/>}
      </div>
      {caption&&<figcaption style={{marginTop:'var(--space-3)',textAlign:'center',
        fontSize:'var(--text-2xs)',color:'var(--text-subtle)'}}>{caption}</figcaption>}
    </figure>
  );
}
