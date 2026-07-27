import * as React from 'react';

/**
 * The only button in Marginal. Primary is violet and reserved for the single
 * most important action on a view; secondary is the hairline paper button;
 * ghost is for toolbar-weight actions.
 * @startingPoint section="Core" subtitle="Primary, secondary and ghost buttons" viewport="700x150"
 */
export interface ButtonProps {
  /** Visual weight. Only one primary per view. */
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  /** Renders an <a> instead of a <button>. */
  href?: string;
  disabled?: boolean;
  fullWidth?: boolean;
  iconLeft?: React.ReactNode;
  iconRight?: React.ReactNode;
  type?: 'button' | 'submit' | 'reset';
  onClick?: (e: React.MouseEvent) => void;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function Button(props: ButtonProps): JSX.Element;
