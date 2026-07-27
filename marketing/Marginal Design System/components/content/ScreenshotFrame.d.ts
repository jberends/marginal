import * as React from 'react';

/**
 * 20px-radius frame with a soft warm shadow, used for every product shot on the
 * site. Pass children to frame a live recreation instead of a bitmap.
 * @startingPoint section="Content" subtitle="Product screenshot frame" viewport="700x400"
 */
export interface ScreenshotFrameProps {
  src?: string;
  alt?: string;
  caption?: string;
  /** Forces the framed content's theme, independent of the page. */
  theme?: 'light' | 'dark';
  style?: React.CSSProperties;
  children?: React.ReactNode;
}
export function ScreenshotFrame(props: ScreenshotFrameProps): JSX.Element;
