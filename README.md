# Marginal

A native, lightweight markdown editor and beautiful viewer for macOS.

Open a `.md` file, write, and see it rendered beautifully as you type — bold, italic, headers, links, tables, code blocks, and images all render inline, with markdown syntax revealing itself only where your cursor is. No projects, no folders, no sidebar. Good at one job: being your default markdown editor.

> **Status: 🚧 Phase 2 complete (formatting engine: inline code, fenced code blocks with basic highlighting, blockquotes, horizontal rules).** Tables, images, AI, visual polish, and export are not yet implemented — see [`specs`](specs) and [`plans`](plans).

## Why

Existing options are either too heavy (Electron-based editors), too raw (syntax-highlighted plain text editors), or come with project/notes management you didn't ask for. Marginal aims to do exactly one thing well: open a markdown file and let you write and read it beautifully, fast, natively.

## Planned features

- Live WYSIWYG editing with reveal-on-cursor markdown syntax (bold, italic, strikethrough, underline, headers, links)
- Live editable table grid
- Inline images (paste/drag-and-drop supported)
- Code blocks with basic syntax highlighting
- `View ▸ Show Source` raw markdown toggle, plus `⌘⌥C` to copy raw markdown from any selection
- Native macOS tabs and windows, autosave, Versions, Open Recent
- Light and dark modes designed to Apple's Human Interface Guidelines
- Adjustable font size (`⌘+`/`⌘-`) and font family (sans/serif/mono)
- Optional AI writing assistant using your own API key (BYOK) — rewrite, critique, or "roast" your writing
- Registers as a handler for `.md` / `.markdown` files

## Requirements

- macOS 14 (Sonoma) or later

## Building from source

Build instructions will be added once the Xcode project is scaffolded.

## Contributing

Contributions are welcome once the initial implementation lands. See [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Support the project

Marginal is free and always will be. If you'd like to support development, donation links will be added here once the project website is live.

## License

Licensed under the [Apache License 2.0](LICENSE).
