import * as React from 'react';

/** A single macOS key cap, e.g. ⌘ or 1. Use real glyphs (⌘ ⇧ ⌥ ⌃ ↩), never spelled-out words. */
export interface KeyCapProps { size?: 'sm' | 'md'; style?: React.CSSProperties; children?: React.ReactNode }
export function KeyCap(props: KeyCapProps): JSX.Element;

/** A key sequence rendered as adjacent caps: keys={['⌘','1']}. */
export interface ShortcutProps { keys: string[]; style?: React.CSSProperties }
export function Shortcut(props: ShortcutProps): JSX.Element;
