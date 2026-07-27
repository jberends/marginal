The app window shell. Every Marginal screen recreation starts here.

```jsx
<WindowChrome title="release-notes.md" subtitle="~/Notes" tabs={<TabBar .../>}
  toolbar={<Button variant="ghost" size="sm">Copy as HTML</Button>}>
  <MarkdownDoc blocks={blocks} />
</WindowChrome>
```

52px toolbar, real macOS traffic-light colours (#FF5F57 / #FEBC2E / #28C840), hairline bottom rule. No custom window buttons.
