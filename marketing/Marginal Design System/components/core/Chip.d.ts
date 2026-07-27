import * as React from 'react';

/** Small 4px-radius label: version tags, "Apache 2.0", inline code pills. */
export interface ChipProps { tone?: 'neutral' | 'accent' | 'code'; style?: React.CSSProperties; children?: React.ReactNode }
export function Chip(props: ChipProps): JSX.Element;
