import * as React from 'react';

/**
 * A single feature statement on the marketing page. Paper card, hairline border,
 * 10px radius, flat by default — elevate only when the card is interactive.
 * @startingPoint section="Content" subtitle="Feature card grid tile" viewport="700x220"
 */
export interface FeatureCardProps {
  title: string;
  body?: string;
  /** A monospace glyph or unicode mark used as the card's icon. */
  glyph?: React.ReactNode;
  /** Usually a Shortcut element, right-aligned against the title. */
  shortcut?: React.ReactNode;
  footer?: React.ReactNode;
  elevated?: boolean;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function FeatureCard(props: FeatureCardProps): JSX.Element;
