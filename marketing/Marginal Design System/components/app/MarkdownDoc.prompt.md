The document canvas. This is the product — get it right and everything else follows.

```jsx
<MarkdownDoc cursorIndex={0} blocks={[
  {type:"h",level:1,text:"Release notes"},
  {type:"p",parts:[{v:"Files stay "},{code:".md"},{v:" on disk."}]},
  {type:"tasks",items:[{text:"Ship tabs",done:true},{text:"Ship export"}]}
]} />
```

720px measure, 16px/1.5 body, headings at 30/24/20px weight 600. Markers (#, **, >) are --text-subtle and only visible on the cursor block — fade at 120ms, never slide.
