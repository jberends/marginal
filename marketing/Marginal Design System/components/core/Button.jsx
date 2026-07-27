import React from 'react';

const pad={sm:'6px 12px',md:'9px 16px',lg:'12px 22px'};
const fs={sm:'var(--text-xs)',md:'var(--text-sm)',lg:'var(--text-base)'};

export function Button({variant='primary',size='md',href,disabled=false,fullWidth=false,iconLeft,iconRight,onClick,type='button',style,children,...rest}){
  const [hover,setHover]=React.useState(false);
  const [press,setPress]=React.useState(false);
  const base={
    display:'inline-flex',alignItems:'center',justifyContent:'center',gap:'var(--space-2)',
    font:'inherit',fontFamily:'var(--font-ui)',fontSize:fs[size],fontWeight:'var(--weight-medium)',
    letterSpacing:'var(--tracking-snug)',lineHeight:1.2,padding:pad[size],
    borderRadius:'var(--radius-sm)',border:'1px solid transparent',cursor:disabled?'default':'pointer',
    textDecoration:'none',width:fullWidth?'100%':'auto',opacity:disabled?0.4:1,
    transition:'background var(--dur-base) var(--ease-standard),color var(--dur-base) var(--ease-standard),border-color var(--dur-base) var(--ease-standard),transform var(--dur-instant) var(--ease-standard)',
    transform:press&&!disabled?'scale(0.985)':'none',whiteSpace:'nowrap'
  };
  const skin={
    primary:{background:press?'var(--accent-press)':hover?'var(--accent-press)':'var(--accent)',color:'var(--accent-on)'},
    secondary:{background:hover?'var(--surface-sunk)':'var(--surface-card)',color:'var(--text-body)',borderColor:'var(--border-hairline)',boxShadow:'0 1px 1px rgba(35,35,35,.03)'},
    ghost:{background:hover?'var(--surface-panel)':'transparent',color:'var(--text-muted)'}
  }[variant];
  const Tag=href?'a':'button';
  return (
    <Tag href={href} type={href?undefined:type} disabled={href?undefined:disabled}
      onClick={disabled?undefined:onClick}
      onMouseEnter={()=>setHover(true)} onMouseLeave={()=>{setHover(false);setPress(false)}}
      onMouseDown={()=>setPress(true)} onMouseUp={()=>setPress(false)}
      style={{...base,...skin,...style}} {...rest}>
      {iconLeft}{children}{iconRight}
    </Tag>
  );
}
