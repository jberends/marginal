import React from 'react';

export function TabBar({tabs=[],activeId,onSelect,onClose,onNew,style}){
  return (
    <div style={{height:'var(--tabbar-h)',flex:'0 0 auto',display:'flex',alignItems:'stretch',
      background:'var(--surface-panel)',borderBottom:'1px solid var(--border-hairline)',...style}}>
      {tabs.map((t,i)=>{
        const on=t.id===activeId;
        return (
          <div key={t.id} onClick={()=>onSelect&&onSelect(t.id)}
            style={{display:'flex',alignItems:'center',gap:'var(--space-2)',padding:'0 var(--space-3)',
              minWidth:130,maxWidth:220,cursor:'default',position:'relative',
              borderRight:'1px solid var(--border-hairline)',
              background:on?'var(--surface-page)':'transparent',
              transition:'background var(--dur-fast) var(--ease-standard)'}}>
            <span style={{flex:1,fontSize:'var(--text-2xs)',fontWeight:on?'var(--weight-medium)':'var(--weight-regular)',
              color:on?'var(--text-heading)':'var(--text-muted)',whiteSpace:'nowrap',overflow:'hidden',
              textOverflow:'ellipsis'}}>{t.dirty?'• ':''}{t.title}</span>
            <span style={{fontSize:'var(--text-3xs)',color:'var(--text-subtle)'}}>⌘{i+1}</span>
            {onClose&&<span onClick={e=>{e.stopPropagation();onClose(t.id)}}
              style={{fontSize:'var(--text-2xs)',color:'var(--text-subtle)',cursor:'pointer',lineHeight:1}}>×</span>}
          </div>
        );
      })}
      {onNew&&<div onClick={onNew} style={{display:'flex',alignItems:'center',padding:'0 var(--space-4)',
        fontSize:'var(--text-sm)',color:'var(--text-subtle)',cursor:'pointer'}}>+</div>}
    </div>
  );
}
