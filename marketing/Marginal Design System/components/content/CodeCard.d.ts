import * as React from 'react';

/**
 * The rounded code-block card exactly as Marginal renders it in a document:
 * warm-gray fill, hairline border, 10px radius, language label and Copy affordance.
 * @startingPoint section="Content" subtitle="Rendered code block with syntax colours" viewport="700x260"
 */
export interface CodeToken { t?: 'k' | 's' | 'n' | 'c' | 'f' | 'p'; v: string }
export interface CodeCardProps {
  lang?: string;
  filename?: string;
  /** One entry per line; each line is a token array, or a plain string. */
  lines?: (CodeToken[] | string)[];
  copyable?: boolean;
  style?: React.CSSProperties;
}
export function CodeCard(props: CodeCardProps): JSX.Element;
