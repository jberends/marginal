import * as React from 'react';

/**
 * macOS-native document tab strip. Shows the ⌘1–⌘9 index on each tab and a
 * bullet for unsaved changes.
 * @startingPoint section="App" subtitle="Document tab strip with ⌘1–⌘9" viewport="700x120"
 */
export interface Tab { id: string; title: string; dirty?: boolean }
export interface TabBarProps {
  tabs: Tab[];
  activeId?: string;
  onSelect?: (id: string) => void;
  onClose?: (id: string) => void;
  onNew?: () => void;
  style?: React.CSSProperties;
}
export function TabBar(props: TabBarProps): JSX.Element;
