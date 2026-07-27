import * as React from 'react';

/**
 * Warm-gray site footer: brand blurb, up to three link columns, hairline base rule
 * carrying the licence and author line.
 * @startingPoint section="Navigation" subtitle="Site footer with link columns" viewport="700x300"
 */
export interface FooterColumn { title: string; links: { label: string; href?: string }[] }
export interface FooterProps {
  /** Path to assets/marginal-icon.png, relative to the *page*. Omitted = wordmark only. */
  logoSrc?: string;
  columns?: FooterColumn[];
  note?: string;
  license?: string;
  author?: string;
  style?: React.CSSProperties;
}
export function Footer(props: FooterProps): JSX.Element;
