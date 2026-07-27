const DS=()=>window.MarginalDesignSystem_dac766;

function ToolbarButtons({theme,onTheme}){
  const {Button}=DS();
  return (<>
    <Button variant="ghost" size="sm">Copy as Markdown</Button>
    <Button variant="ghost" size="sm" onClick={onTheme}>{theme==='light'?'Dark':'Light'}</Button>
  </>);
}

function EditorApp({height=620}){
  const {WindowChrome,TabBar,MarkdownDoc,Shortcut}=DS();
  const docs = window.MARGINAL_DOCS;
  const [activeId,setActiveId]=React.useState(docs[0].id);
  const [open,setOpen]=React.useState(docs.map(d=>d.id));
  const [theme,setTheme]=React.useState('light');
  const [cursor,setCursor]=React.useState({});
  const tabs=open.map(id=>{const d=docs.find(x=>x.id===id);return {id,title:d.title,dirty:d.dirty}});
  const doc=docs.find(d=>d.id===activeId)||docs[0];
  const ci=cursor[activeId]===undefined?0:cursor[activeId];
  return (
    <WindowChrome height={height} theme={theme} title={doc.title} subtitle={doc.path}
      toolbar={<ToolbarButtons theme={theme} onTheme={()=>setTheme(t=>t==='light'?'dark':'light')}/>}
      tabs={<TabBar tabs={tabs} activeId={activeId} onSelect={setActiveId}
        onClose={id=>{const rest=open.filter(x=>x!==id);if(rest.length){setOpen(rest);if(id===activeId)setActiveId(rest[0])}}}
        onNew={()=>setOpen(docs.map(d=>d.id))}/>}>
      <div onClick={e=>{
        const el=e.target.closest('[data-block]');
        if(el)setCursor(c=>({...c,[activeId]:Number(el.dataset.block)}));
      }}>
        <BlockWrap><MarkdownDoc blocks={doc.blocks} cursorIndex={ci}/></BlockWrap>
      </div>
      <div style={{position:'sticky',bottom:0,display:'flex',justifyContent:'space-between',
        padding:'6px 16px',fontSize:'var(--text-3xs)',color:'var(--text-subtle)',
        borderTop:'1px solid var(--border-hairline)',background:'var(--surface-chrome)'}}>
        <span>{doc.path}/{doc.title}</span>
        <span style={{display:'flex',gap:16,alignItems:'center'}}>
          <span>Markdown</span><Shortcut keys={['⌘','1']}/>
        </span>
      </div>
    </WindowChrome>
  );
}

/* tags each rendered top-level block so clicking one moves the caret */
function BlockWrap({children}){
  const ref=React.useRef(null);
  React.useEffect(()=>{
    const root=ref.current&&ref.current.firstElementChild;
    if(!root)return;
    Array.from(root.children).forEach((el,i)=>el.dataset.block=i);
  });
  return <div ref={ref}>{children}</div>;
}

Object.assign(window,{EditorApp});
