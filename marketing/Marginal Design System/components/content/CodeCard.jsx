import React from 'react';

const TOK={k:'var(--syn-keyword)',s:'var(--syn-string)',n:'var(--syn-number)',c:'var(--syn-comment)',f:'var(--syn-func)',p:'var(--syn-punct)'};

export function CodeCard({lang='swift',lines=[],filename,copyable=true,style}){
  const [copied,setCopied]=React.useState(false);
  return (
    <div style={{background:'var(--surface-code)',border:'1px solid var(--border-hairline)',
      borderRadius:'var(--radius-card)',overflow:'hidden',...style}}>
      <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',
        padding:'var(--space-2) var(--space-3) var(--space-2) var(--space-4)',
        borderBottom:'1px solid var(--border-hairline)'}}>
        <span style={{fontFamily:'var(--font-code)',fontSize:'var(--text-3xs)',color:'var(--text-subtle)',
          letterSpacing:'var(--tracking-wide)'}}>{filename||lang}</span>
        {copyable&&<button onClick={()=>{setCopied(true);setTimeout(()=>setCopied(false),1200)}}
          style={{font:'inherit',fontFamily:'var(--font-ui)',fontSize:'var(--text-3xs)',
            color:copied?'var(--accent)':'var(--text-subtle)',background:'transparent',border:0,
            cursor:'pointer',padding:'2px 4px',transition:'color var(--dur-fast) var(--ease-standard)'}}>
          {copied?'Copied':'Copy'}</button>}
      </div>
      <pre style={{margin:0,padding:'var(--space-4)',overflowX:'auto',
        fontFamily:'var(--font-code)',fontSize:'var(--text-xs)',lineHeight:1.65,color:'var(--text-body)'}}>
        <code>{lines.map((ln,i)=>(
          <div key={i} style={{minHeight:'1.65em',whiteSpace:'pre'}}>
            {(Array.isArray(ln)?ln:[{v:ln}]).map((tk,j)=>
              <span key={j} style={{color:tk.t?TOK[tk.t]:'inherit'}}>{tk.v}</span>)}
          </div>
        ))}</code>
      </pre>
    </div>
  );
}
