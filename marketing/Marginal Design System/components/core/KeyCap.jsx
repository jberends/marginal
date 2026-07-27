import React from 'react';

export function KeyCap({children,size='md',style}){
  const s=size==='sm'
    ?{fontSize:'var(--text-3xs)',padding:'1px 5px',minWidth:18}
    :{fontSize:'var(--text-2xs)',padding:'2px 6px',minWidth:22};
  return (
    <kbd style={{
      display:'inline-flex',alignItems:'center',justifyContent:'center',
      fontFamily:'var(--font-ui)',fontWeight:'var(--weight-medium)',
      color:'var(--text-muted)',background:'var(--surface-card)',
      border:'1px solid var(--border-hairline)',borderBottomColor:'var(--border-strong)',
      borderRadius:'var(--radius-chip)',boxShadow:'var(--shadow-key)',
      lineHeight:1.5,...s,...style}}>{children}</kbd>
  );
}

export function Shortcut({keys,style}){
  return (
    <span style={{display:'inline-flex',alignItems:'center',gap:'var(--space-1)',...style}}>
      {keys.map((k,i)=><KeyCap key={i}>{k}</KeyCap>)}
    </span>
  );
}
