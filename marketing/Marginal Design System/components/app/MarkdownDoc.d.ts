import * as React from 'react';

/**
 * Marginal's rendered-document surface — the WYSIWYG canvas. Renders a block
 * list as Notion-grade markdown output; the block at cursorIndex reveals its
 * syntax markers, every other block hides them.
 * @startingPoint section="App" subtitle="Rendered markdown document canvas" viewport="760x560"
 */
export type DocBlock =
  | { type: 'h'; level: 1 | 2 | 3; text: string }
  | { type: 'p'; text?: string; parts?: { v?: string; bold?: string; code?: string; link?: string }[] }
  | { type: 'quote'; text: string }
  | { type: 'code'; lang?: string; lines?: any[] }
  | { type: 'tasks'; items: { text: string; done?: boolean }[] }
  | { type: 'ol'; items: string[] }
  | { type: 'table'; head: string[]; rows: string[][] }
  | { type: 'hr' };
export interface MarkdownDocProps {
  blocks: DocBlock[];
  /** Index of the block holding the caret; its markdown markers fade in. */
  cursorIndex?: number;
  maxWidth?: string;
  style?: React.CSSProperties;
}
export function MarkdownDoc(props: MarkdownDocProps): JSX.Element;
