import React from 'react';

export function Footer({logoSrc,columns=[],note,license='Apache 2.0',author='Jochem Berends',style}){
  return (
    <footer style={{borderTop:'1px solid var(--border-hairline)',background:'var(--surface-panel)',
      padding:'var(--space-9) var(--space-5) var(--space-6)',...style}}>
      <div style={{maxWidth:'var(--content-max)',margin:'0 auto',display:'grid',
        gridTemplateColumns:'minmax(200px,1.3fr) repeat('+Math.max(columns.length,1)+',1fr)',gap:'var(--space-8)'}}>
        <div>
          <div style={{display:'flex',alignItems:'center',gap:'var(--space-2)',marginBottom:'var(--space-3)'}}>
            {logoSrc&&<img src={logoSrc} alt="" width={22} height={22} style={{display:'block',borderRadius:5}}/>}
            <span style={{fontSize:'var(--text-sm)',fontWeight:'var(--weight-semibold)',color:'var(--text-heading)'}}>Marginal</span>
          </div>
          <p style={{fontSize:'var(--text-xs)',color:'var(--text-muted)',maxWidth:'32ch',lineHeight:'var(--leading-relaxed)'}}>
            {note||'A native macOS markdown editor. Your files stay plain text.'}
          </p>
        </div>
        {columns.map(col=>(
          <div key={col.title}>
            <h4 style={{fontSize:'var(--text-3xs)',fontWeight:'var(--weight-semibold)',textTransform:'uppercase',
              letterSpacing:'var(--tracking-wide)',color:'var(--text-subtle)',marginBottom:'var(--space-3)'}}>{col.title}</h4>
            <ul style={{listStyle:'none',margin:0,padding:0,display:'grid',gap:'var(--space-2)'}}>
              {col.links.map(l=>(
                <li key={l.label}><a href={l.href||'#'} style={{fontSize:'var(--text-xs)',color:'var(--text-muted)',textDecoration:'none'}}>{l.label}</a></li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div style={{maxWidth:'var(--content-max)',margin:'var(--space-8) auto 0',paddingTop:'var(--space-4)',
        borderTop:'1px solid var(--border-hairline)',display:'flex',justifyContent:'space-between',gap:'var(--space-4)',
        fontSize:'var(--text-3xs)',color:'var(--text-subtle)'}}>
        <span>{license} · Open source</span><span>Made by {author}</span>
      </div>
    </footer>
  );
}
