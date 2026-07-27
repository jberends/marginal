import React from 'react';

function Light({color}){return <span style={{width:12,height:12,borderRadius:'50%',background:color,display:'block'}}/>;}

export function WindowChrome({title,subtitle,theme='light',toolbar,tabs,height,style,children}){
  return (
    <div data-theme={theme} style={{background:'var(--surface-page)',color:'var(--text-body)',
      fontFamily:'var(--font-ui)',display:'flex',flexDirection:'column',height:height||'100%',
      overflow:'hidden',...style}}>
      <div style={{height:'var(--chrome-h)',flex:'0 0 auto',display:'flex',alignItems:'center',
        gap:'var(--space-3)',padding:'0 var(--space-4)',background:'var(--surface-chrome)',
        borderBottom:'1px solid var(--border-hairline)'}}>
        <div style={{display:'flex',gap:8,alignItems:'center'}}>
          <Light color="#FF5F57"/><Light color="#FEBC2E"/><Light color="#28C840"/>
        </div>
        <div style={{flex:1,textAlign:'center',minWidth:0}}>
          <div style={{fontSize:'var(--text-xs)',fontWeight:'var(--weight-semibold)',color:'var(--text-heading)',
            whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{title}</div>
          {subtitle&&<div style={{fontSize:'var(--text-3xs)',color:'var(--text-subtle)'}}>{subtitle}</div>}
        </div>
        <div style={{display:'flex',alignItems:'center',gap:'var(--space-2)',minWidth:76,justifyContent:'flex-end'}}>{toolbar}</div>
      </div>
      {tabs}
      <div style={{flex:1,minHeight:0,overflow:'auto',background:'var(--surface-page)'}}>{children}</div>
    </div>
  );
}
