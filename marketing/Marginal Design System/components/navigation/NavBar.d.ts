import * as React from 'react';

/**
 * Marginal's marketing nav: translucent paper bar, 64px tall, hairline bottom rule,
 * app icon + wordmark on the left, one violet CTA on the right.
 * @startingPoint section="Navigation" subtitle="Sticky translucent site header" viewport="700x120"
 */
export interface NavBarLink { id?: string; label: string; href?: string }
export interface NavBarProps {
  /** Path to assets/marginal-icon.png, relative to the *page*. Omitted = wordmark only. */
  logoSrc?: string;
  brand?: string;
  links?: NavBarLink[];
  cta?: { label: string; href?: string; onClick?: () => void };
  active?: string;
  onNavigate?: (id: string) => void;
  style?: React.CSSProperties;
}
export function NavBar(props: NavBarProps): JSX.Element;
