import React from 'react';
import { Button } from '../core/Button.jsx';

export function NavBar({logoSrc,brand='Marginal',links=[],cta,onNavigate,active,style}){
  return (
    <header style={{position:'sticky',top:0,zIndex:20,background:'color-mix(in srgb,var(--surface-page) 88%,transparent)',
      backdropFilter:'saturate(180%) blur(20px)',WebkitBackdropFilter:'saturate(180%) blur(20px)',
      borderBottom:'1px solid var(--border-hairline)',...style}}>
      <nav style={{maxWidth:'var(--content-max)',margin:'0 auto',height:64,padding:'0 var(--space-5)',
        display:'flex',alignItems:'center',gap:'var(--space-6)'}}>
        <a href="#" onClick={e=>{e.preventDefault();onNavigate&&onNavigate('home')}}
          style={{display:'flex',alignItems:'center',gap:'var(--space-2)',textDecoration:'none'}}>
          {logoSrc&&<img src={logoSrc} alt="" width={26} height={26} style={{display:'block',borderRadius:6}}/>}
          <span style={{fontSize:'var(--text-base)',fontWeight:'var(--weight-semibold)',
            letterSpacing:'var(--tracking-snug)',color:'var(--text-heading)'}}>{brand}</span>
        </a>
        <ul style={{display:'flex',alignItems:'center',gap:'var(--space-5)',listStyle:'none',margin:0,padding:0,marginRight:'auto'}}>
          {links.map(l=>(
            <li key={l.id||l.label}>
              <a href={l.href||'#'} onClick={e=>{if(onNavigate){e.preventDefault();onNavigate(l.id||l.label)}}}
                style={{fontSize:'var(--text-sm)',fontWeight:'var(--weight-medium)',textDecoration:'none',
                  color:active===(l.id||l.label)?'var(--text-heading)':'var(--text-muted)',
                  transition:'color var(--dur-fast) var(--ease-standard)'}}>{l.label}</a>
            </li>
          ))}
        </ul>
        {cta&&<Button variant="primary" size="sm" href={cta.href} onClick={cta.onClick}>{cta.label}</Button>}
      </nav>
    </header>
  );
}
