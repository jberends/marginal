import React from 'react';
import { CodeCard } from '../content/CodeCard.jsx';

const H={1:{fontSize:'30px',mt:'var(--space-6)'},2:{fontSize:'24px',mt:'var(--space-6)'},3:{fontSize:'20px',mt:'var(--space-5)'}};

/* Markers sit in the left gutter so the text column never shifts when the caret moves. */
function Marker({children,visible}){
  return <span style={{position:'absolute',right:'100%',paddingRight:'.25em',fontWeight:'var(--weight-regular)',
    color:'var(--text-subtle)',opacity:visible?1:0,pointerEvents:'none',
    transition:'opacity var(--dur-fast) var(--ease-standard)'}}>{children}</span>;
}

function Inline({parts=[]}){
  return <>{parts.map((p,i)=>{
    if(p.code) return <code key={i} style={{background:'var(--surface-code)',color:'var(--text-code)',
      padding:'1px 5px',borderRadius:'var(--radius-chip)',fontSize:'.875em',border:'1px solid var(--border-hairline)'}}>{p.code}</code>;
    if(p.bold) return <strong key={i} style={{fontWeight:'var(--weight-semibold)'}}>{p.bold}</strong>;
    if(p.link) return <a key={i} href="#" style={{color:'var(--text-accent)'}}>{p.link}</a>;
    return <span key={i}>{p.v}</span>;
  })}</>;
}

export function MarkdownDoc({blocks=[],cursorIndex=-1,maxWidth='var(--doc-max)',style}){
  return (
    <div style={{maxWidth,margin:'0 auto',padding:'var(--space-8) var(--space-6) var(--space-11)',
      fontSize:'var(--text-base)',lineHeight:'var(--leading-normal)',color:'var(--text-body)',...style}}>
      {blocks.map((b,i)=>{
        const focus=i===cursorIndex;
        if(b.type==='h'){const h=H[b.level]||H[3];
          return <h2 key={i} style={{fontSize:h.fontSize,fontWeight:'var(--weight-semibold)',
            color:'var(--text-heading)',letterSpacing:'var(--tracking-tight)',lineHeight:'var(--leading-snug)',
            margin:0,marginTop:i?h.mt:0,marginBottom:'var(--space-2)',position:'relative'}}>
            <Marker visible={focus}>{'#'.repeat(b.level)}</Marker>{b.text}</h2>;}
        if(b.type==='p')
          return <p key={i} style={{margin:'var(--space-3) 0'}}><Inline parts={b.parts||[{v:b.text}]}/></p>;
        if(b.type==='quote')
          return <blockquote key={i} style={{margin:'var(--space-4) 0',padding:'var(--space-1) 0 var(--space-1) var(--space-4)',
            borderLeft:'3px solid var(--border-strong)',color:'var(--text-muted)'}}>{b.text}</blockquote>;
        if(b.type==='code')
          return <CodeCard key={i} lang={b.lang} lines={b.lines} copyable={false} style={{margin:'var(--space-4) 0'}}/>;
        if(b.type==='tasks')
          return <ul key={i} style={{listStyle:'none',margin:'var(--space-3) 0',padding:0,display:'grid',gap:'var(--space-2)'}}>
            {b.items.map((it,j)=>(
              <li key={j} style={{display:'flex',alignItems:'flex-start',gap:'var(--space-2)'}}>
                <span style={{width:16,height:16,marginTop:3,borderRadius:'var(--radius-xs)',flex:'0 0 auto',
                  border:'1px solid '+(it.done?'transparent':'var(--border-strong)'),
                  background:it.done?'var(--accent)':'transparent',color:'var(--accent-on)',
                  fontSize:11,display:'flex',alignItems:'center',justifyContent:'center'}}>{it.done?'✓':''}</span>
                <span style={{color:it.done?'var(--text-subtle)':'var(--text-body)',
                  textDecoration:it.done?'line-through':'none'}}>{it.text}</span>
              </li>))}
          </ul>;
        if(b.type==='ol')
          return <ol key={i} style={{margin:'var(--space-3) 0',paddingLeft:'var(--space-5)',display:'grid',gap:'var(--space-2)'}}>
            {b.items.map((it,j)=><li key={j}>{it}</li>)}</ol>;
        if(b.type==='table')
          return <table key={i} style={{width:'100%',borderCollapse:'collapse',margin:'var(--space-4) 0',
            fontSize:'var(--text-sm)',border:'1px solid var(--border-hairline)'}}>
            <thead><tr>{b.head.map((h,j)=><th key={j} style={{textAlign:'left',padding:'8px 12px',
              background:'var(--surface-panel)',borderBottom:'1px solid var(--border-hairline)',
              borderRight:j<b.head.length-1?'1px solid var(--border-hairline)':'none',
              fontWeight:'var(--weight-semibold)',fontSize:'var(--text-xs)',color:'var(--text-heading)'}}>{h}</th>)}</tr></thead>
            <tbody>{b.rows.map((r,j)=><tr key={j}>{r.map((c,k)=><td key={k} style={{padding:'8px 12px',
              borderBottom:j<b.rows.length-1?'1px solid var(--border-hairline)':'none',
              borderRight:k<r.length-1?'1px solid var(--border-hairline)':'none',color:'var(--text-body)'}}>{c}</td>)}</tr>)}</tbody>
          </table>;
        if(b.type==='hr') return <hr key={i}/>;
        return null;
      })}
    </div>
  );
}
