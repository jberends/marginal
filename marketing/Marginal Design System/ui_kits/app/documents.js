window.MARGINAL_DOCS=[
 {id:'notes',title:'release-notes.md',path:'~/Notes',blocks:[
  {type:'h',level:1,text:'Marginal 1.4'},
  {type:'p',parts:[{v:'Tabs land in this release. Open as many documents as you like in one window and move between them with '},{code:'⌘1'},{v:'–'},{code:'⌘9'},{v:'.'}]},
  {type:'h',level:2,text:'What changed'},
  {type:'tasks',items:[{text:'Native macOS tab bar',done:true},{text:'Copy as Markdown / Copy as HTML',done:true},{text:'Emoji :shortcodes: in headings'},{text:'Per-window theme override'}]},
  {type:'h',level:2,text:'Rendering'},
  {type:'p',parts:[{v:'Code blocks are measured against Notion pixel by pixel — '},{bold:'10px radius'},{v:', warm gray fill, hairline border.'}]},
  {type:'code',lang:'swift',lines:[
    [{t:'k',v:'func '},{t:'f',v:'render'},{v:'('},{t:'p',v:'_ '},{v:'doc: '},{t:'k',v:'Document'},{v:') {'}],
    [{v:'  '},{t:'k',v:'let '},{v:'measure = '},{t:'n',v:'720'},{v:'  '},{t:'c',v:'// document column'}],
    [{v:'  layout.'},{t:'f',v:'flow'},{v:'(doc, width: measure)'}],
    [{v:'}'}]]},
  {type:'quote',text:'No split pane. No raw-syntax soup. The document is the editor.'},
  {type:'table',head:['Shortcut','Action'],rows:[['⌘1–⌘9','Switch tab'],['⌘⇧C','Copy as HTML'],['⌘T','New tab']]}
 ]},
 {id:'draft',title:'essay-draft.md',path:'~/Writing',dirty:true,blocks:[
  {type:'h',level:1,text:'On the margins'},
  {type:'p',text:'A note in the margin is a second voice — quieter than the text, but reading the same line.'},
  {type:'h',level:3,text:'Three things'},
  {type:'ol',items:['The file is the truth.','The rendering is a courtesy.','Both are yours to keep.']},
  {type:'hr'},
  {type:'p',parts:[{v:'Filed under '},{link:'#writing'},{v:'.'}]}
 ]},
 {id:'readme',title:'README.md',path:'~/src/marginal',blocks:[
  {type:'h',level:1,text:'Marginal'},
  {type:'p',parts:[{v:'A native macOS WYSIWYG markdown editor. Apache 2.0. '},{code:'brew install marginal'}]},
  {type:'h',level:2,text:'Build'},
  {type:'code',lang:'bash',lines:[
    [{t:'p',v:'$ '},{v:'git clone git@github.com:marginal/marginal.git'}],
    [{t:'p',v:'$ '},{v:'xcodebuild -scheme Marginal'}]]},
  {type:'p',text:'Files stay plain markdown. No database, no lock-in, works with git.'}
 ]}
];