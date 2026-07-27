const DS=()=>window.MarginalDesignSystem_dac766;

const Wrap=({children,style})=> <div style={{maxWidth:'var(--content-max)',margin:'0 auto',padding:'0 var(--space-6)',...style}}>{children}</div>;

function Eyebrow({children}){
  return <div style={{fontSize:'var(--text-3xs)',textTransform:'uppercase',letterSpacing:'var(--tracking-wide)',
    color:'var(--text-subtle)',fontWeight:'var(--weight-semibold)',marginBottom:'var(--space-3)'}}>{children}</div>;
}

function MiniEditor({theme='light'}){
  const {WindowChrome,TabBar,MarkdownDoc,Button}=DS();
  const blocks=[
    {type:'h',level:1,text:'Marginal 1.4'},
    {type:'p',parts:[{v:'Tabs land in this release. Move between documents with '},{code:'⌘1'},{v:'–'},{code:'⌘9'},{v:'.'}]},
    {type:'tasks',items:[{text:'Native macOS tab bar',done:true},{text:'Copy as HTML',done:true},{text:'Emoji :shortcodes:'}]},
    {type:'code',lang:'swift',lines:[
      [{t:'k',v:'let '},{v:'measure = '},{t:'n',v:'720'},{v:'  '},{t:'c',v:'// document column'}]]},
    {type:'quote',text:'No split pane. The document is the editor.'}
  ];
  return <WindowChrome theme={theme} height={430} title="release-notes.md" subtitle="~/Notes"
    toolbar={<Button variant="ghost" size="sm">Copy as HTML</Button>}
    tabs={<TabBar tabs={[{id:'a',title:'release-notes.md'},{id:'b',title:'essay-draft.md',dirty:true}]} activeId="a"/>}>
    <MarkdownDoc blocks={blocks} cursorIndex={0} maxWidth="600px"/>
  </WindowChrome>;
}

function Hero({theme,onTheme}){
  const {Button,Chip,ScreenshotFrame}=DS();
  return (
    <section style={{padding:'var(--space-11) 0 var(--space-9)'}}>
      <Wrap style={{textAlign:'center'}}>
        <img src="../../assets/marginal-icon.png" width="88" height="88" alt="" style={{display:'block',margin:'0 auto var(--space-5)'}}/>
        <h1 style={{fontSize:'var(--text-display)',fontWeight:'var(--weight-semibold)',letterSpacing:'-0.03em',
          lineHeight:1.05,margin:'0 auto',maxWidth:'16ch',color:'var(--text-heading)'}}>Markdown that reads the way it renders.</h1>
        <p style={{fontSize:'var(--text-h3)',color:'var(--text-muted)',lineHeight:'var(--leading-relaxed)',
          maxWidth:'var(--measure-narrow)',margin:'var(--space-5) auto 0'}}>
          A native macOS editor for plain <code style={{background:'var(--surface-code)',color:'var(--text-code)',padding:'2px 6px',borderRadius:'var(--radius-chip)',border:'1px solid var(--border-hairline)',fontSize:'.85em'}}>.md</code> files
          that renders while you type — no split pane, no syntax soup.
        </p>
        <div style={{display:'flex',gap:'var(--space-3)',justifyContent:'center',marginTop:'var(--space-6)'}}>
          <Button variant="primary" size="lg" href="#download">Download for macOS</Button>
          <Button variant="secondary" size="lg" href="#source">View source</Button>
        </div>
        <div style={{display:'flex',gap:'var(--space-2)',justifyContent:'center',marginTop:'var(--space-4)'}}>
          <Chip>Apache 2.0</Chip><Chip>Universal · Apple silicon</Chip>
          <button onClick={onTheme} style={{font:'inherit',fontSize:'var(--text-2xs)',background:'transparent',
            border:'1px solid var(--border-hairline)',borderRadius:'var(--radius-chip)',padding:'3px 8px',
            color:'var(--text-muted)',cursor:'pointer'}}>{theme==='light'?'Preview dark':'Preview light'}</button>
        </div>
      </Wrap>
      <Wrap style={{marginTop:'var(--space-9)'}}>
        <ScreenshotFrame theme={theme} caption="Marginal 1.4 — one window, many documents"><MiniEditor theme={theme}/></ScreenshotFrame>
      </Wrap>
    </section>
  );
}

const FEATURES=[
  {glyph:'##',title:'Marks hide themselves',body:'Syntax markers fade out as you type and reappear only around the cursor. The page never jumps.'},
  {glyph:'▤',title:'Notion-grade rendering',body:'Tables with real grids, rounded code cards with highlighting, checkboxes, auto-renumbered lists — measured pixel by pixel.'},
  {glyph:'.md',title:'Plain files, always',body:'No database, no lock-in. Your documents are markdown on disk and diff cleanly in git.'},
  {glyph:'⌘',title:'Tabs in one window',body:'The real macOS tab bar, with ⌘1–⌘9 to switch.',shortcut:['⌘','1']},
  {glyph:'⌥',title:'Native AppKit',body:'Instant launch, low memory. It feels like a Mac app because it is one.'},
  {glyph:'◑',title:'Light and dark',body:'Follows the system appearance, and copies out as Markdown or as HTML.',shortcut:['⌘','⇧','C']}
];

function Features(){
  const {FeatureCard,Shortcut}=DS();
  return (
    <section style={{padding:'var(--space-9) 0',borderTop:'1px solid var(--border-hairline)'}}>
      <Wrap>
        <Eyebrow>What it does</Eyebrow>
        <h2 style={{fontSize:'var(--text-display-sm)',fontWeight:'var(--weight-semibold)',letterSpacing:'-0.02em',maxWidth:'20ch',color:'var(--text-heading)'}}>Everything the file already said.</h2>
        <div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:'var(--space-4)',marginTop:'var(--space-7)'}}>
          {FEATURES.map(ft=><FeatureCard key={ft.title} glyph={ft.glyph} title={ft.title} body={ft.body}
            shortcut={ft.shortcut?<Shortcut keys={ft.shortcut}/>:null}/>)}
        </div>
      </Wrap>
    </section>
  );
}

function PlainText(){
  const {Button,CodeCard}=DS();
  return (
    <section style={{padding:'var(--space-9) 0',background:'var(--surface-panel)',borderTop:'1px solid var(--border-hairline)'}}>
      <Wrap style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:'var(--space-8)',alignItems:'center'}}>
        <div>
          <Eyebrow>No lock-in</Eyebrow>
          <h2 style={{fontSize:'var(--text-h1)',fontWeight:'var(--weight-semibold)',letterSpacing:'-0.02em',color:'var(--text-heading)'}}>What you see on the left is what sits on disk.</h2>
          <p style={{fontSize:'var(--text-base)',color:'var(--text-muted)',lineHeight:'var(--leading-relaxed)',marginTop:'var(--space-4)',maxWidth:'42ch'}}>
            Marginal edits the file itself. Close the app and your notes are still markdown — readable in any editor, committable to any repo.
          </p>
          <div style={{display:'flex',gap:'var(--space-2)',marginTop:'var(--space-5)'}}>
            <Button variant="secondary">Read the docs</Button>
          </div>
        </div>
        <CodeCard lang="markdown" filename="release-notes.md" lines={[
          [{t:'k',v:'# '},{v:'Marginal 1.4'}],
          [{v:''}],
          [{v:'Tabs land in this release.'}],
          [{v:''}],
          [{t:'k',v:'## '},{v:'What changed'}],
          [{t:'p',v:'- [x] '},{v:'Native macOS tab bar'}],
          [{t:'p',v:'- [ ] '},{v:'Emoji '},{t:'s',v:':shortcodes:'}]
        ]}/>
      </Wrap>
    </section>
  );
}

const KEYS=[
  {keys:['⌘','1'],label:'Switch to tab one'},
  {keys:['⌘','T'],label:'New tab'},
  {keys:['⌘','⇧','C'],label:'Copy as HTML'},
  {keys:['⌘','⌥','C'],label:'Copy as Markdown'}
];

function Shortcuts(){
  const {Shortcut}=DS();
  return (
    <section style={{padding:'var(--space-9) 0',borderTop:'1px solid var(--border-hairline)'}}>
      <Wrap>
        <Eyebrow>Keyboard</Eyebrow>
        <h2 style={{fontSize:'var(--text-h1)',fontWeight:'var(--weight-semibold)',letterSpacing:'-0.02em',color:'var(--text-heading)'}}>Hands stay where they are.</h2>
        <div style={{display:'grid',gridTemplateColumns:'repeat(2,1fr)',gap:'var(--space-2) var(--space-8)',marginTop:'var(--space-6)'}}>
          {KEYS.map(k=>(
            <div key={k.label} style={{display:'flex',alignItems:'center',justifyContent:'space-between',
              gap:'var(--space-4)',padding:'var(--space-3) 0',borderBottom:'1px solid var(--border-hairline)'}}>
              <span style={{fontSize:'var(--text-sm)',color:'var(--text-body)'}}>{k.label}</span>
              <Shortcut keys={k.keys}/>
            </div>
          ))}
        </div>
      </Wrap>
    </section>
  );
}

function Download(){
  const {Button}=DS();
  return (
    <section id="download" style={{padding:'var(--space-10) 0',borderTop:'1px solid var(--border-hairline)',textAlign:'center'}}>
      <Wrap>
        <h2 style={{fontSize:'var(--text-display-sm)',fontWeight:'var(--weight-semibold)',letterSpacing:'-0.02em',color:'var(--text-heading)'}}>Free, open, and yours.</h2>
        <p style={{fontSize:'var(--text-base)',color:'var(--text-muted)',marginTop:'var(--space-3)'}}>macOS 13 or later · Universal · Apache 2.0</p>
        <div style={{display:'flex',gap:'var(--space-3)',justifyContent:'center',marginTop:'var(--space-5)'}}>
          <Button variant="primary" size="lg">Download Marginal</Button>
          <Button variant="ghost" size="lg">Read the source</Button>
        </div>
      </Wrap>
    </section>
  );
}

function SiteApp(){
  const {NavBar,Footer}=DS();
  const [theme,setTheme]=React.useState('light');
  return (
    <div>
      <NavBar logoSrc="../../assets/marginal-icon.png"
        links={[{id:'features',label:'Features'},{id:'shortcuts',label:'Shortcuts'},{id:'docs',label:'Docs'},{id:'source',label:'Source'}]}
        active="features" cta={{label:'Download',href:'#download'}}/>
      <Hero theme={theme} onTheme={()=>setTheme(t=>t==='light'?'dark':'light')}/>
      <Features/>
      <PlainText/>
      <Shortcuts/>
      <Download/>
      <Footer logoSrc="../../assets/marginal-icon.png" columns={[
        {title:'Product',links:[{label:'Features'},{label:'Shortcuts'},{label:'Changelog'}]},
        {title:'Source',links:[{label:'GitHub'},{label:'Licence'},{label:'Issues'}]},
        {title:'Elsewhere',links:[{label:'Mastodon'},{label:'RSS'}]}
      ]}/>
    </div>
  );
}
Object.assign(window,{SiteApp,Hero,Features,PlainText,Shortcuts,Download,MiniEditor});
