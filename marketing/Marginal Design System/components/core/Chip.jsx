import React from 'react';

export function Chip({tone='neutral',children,style}){
  const tones={
    neutral:{background:'var(--surface-panel)',color:'var(--text-muted)',border:'1px solid var(--border-hairline)'},
    accent:{background:'var(--accent-tint)',color:'var(--accent)',border:'1px solid transparent'},
    code:{background:'var(--surface-code)',color:'var(--text-code)',border:'1px solid var(--border-hairline)',fontFamily:'var(--font-code)'}
  };
  return <span style={{display:'inline-flex',alignItems:'center',gap:'var(--space-1)',
    padding:'3px 8px',borderRadius:'var(--radius-chip)',fontSize:'var(--text-2xs)',
    fontWeight:'var(--weight-medium)',lineHeight:1.4,letterSpacing:'var(--tracking-snug)',
    ...tones[tone],...style}}>{children}</span>;
}
