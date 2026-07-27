import * as React from 'react';

/**
 * The Marginal app window: macOS traffic lights, centred document title with a
 * folder-path subtitle, a right-hand toolbar slot, and an optional tab strip.
 * @startingPoint section="App" subtitle="macOS window frame" viewport="900x560"
 */
export interface WindowChromeProps {
  title?: string;
  /** Small grey path line under the title, e.g. "~/Notes". */
  subtitle?: string;
  theme?: 'light' | 'dark';
  toolbar?: React.ReactNode;
  /** Usually a TabBar element; sits directly under the toolbar. */
  tabs?: React.ReactNode;
  height?: number | string;
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function WindowChrome(props: WindowChromeProps): JSX.Element;
