Tab strip for multi-document windows. Max nine tabs get a shortcut index.

```jsx
<TabBar tabs={[{id:"a",title:"notes.md"},{id:"b",title:"draft.md",dirty:true}]}
  activeId="a" onSelect={setActive} onClose={close} onNew={newDoc} />
```

34px tall, warm-gray strip, active tab takes the paper colour of the document below it. Dirty state is a bullet before the filename — never a coloured dot.
