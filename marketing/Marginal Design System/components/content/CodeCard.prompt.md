Mimics the code block Marginal renders inside a document — reuse it on the site so page and app agree pixel for pixel.

```jsx
<CodeCard lang="markdown" lines={[
  [{t:'k',v:'## '},{v:'Heading'}],
  [{t:'c',v:'a comment line'}]
]} />
```

Token keys: k keyword, s string, n number, c comment, f function, p punctuation. Only use the --syn-* tokens for colour.
