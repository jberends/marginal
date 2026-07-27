import React from 'react';

export function FeatureCard({title,body,glyph,shortcut,footer,elevated=false,style,children}){
  return (
    <article style={{background:'var(--surface-card)',border:'1px solid var(--border-hairline)',
      borderRadius:'var(--radius-card)',padding:'var(--space-5)',
      boxShadow:elevated?'var(--shadow-raised)':'none',display:'flex',flexDirection:'column',
      gap:'var(--space-2)',...style}}>
      {glyph&&<div style={{fontSize:20,lineHeight:1,color:'var(--text-subtle)',marginBottom:'var(--space-1)',
        fontFamily:'var(--font-code)'}}>{glyph}</div>}
      <div style={{display:'flex',alignItems:'baseline',justifyContent:'space-between',gap:'var(--space-3)'}}>
        <h3 style={{fontSize:'var(--text-base)',fontWeight:'var(--weight-semibold)',color:'var(--text-heading)',
          letterSpacing:'var(--tracking-snug)',margin:0}}>{title}</h3>
        {shortcut}
      </div>
      {body&&<p style={{fontSize:'var(--text-sm)',lineHeight:'var(--leading-relaxed)',color:'var(--text-muted)',margin:0}}>{body}</p>}
      {children}
      {footer&&<div style={{marginTop:'var(--space-2)',fontSize:'var(--text-2xs)',color:'var(--text-subtle)'}}>{footer}</div>}
    </article>
  );
}
