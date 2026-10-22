// HUB Tabs as links (web-review §2.4): each tab is a link to a URL of the page, the active one
// marked aria-current="page" and underlined in the accent. Server-rendered, no script.

export interface TabItem {
  readonly id: string;
  readonly label: string;
  readonly count?: number;
  readonly href: string;
}

export interface TabsProps {
  readonly items: readonly TabItem[];
  readonly value: string;
  /** Accessible name of the tab bar. */
  readonly label: string;
}

export function Tabs({ items, value, label }: TabsProps) {
  return (
    <nav className="hub-tabs" aria-label={label}>
      {items.map((item) => (
        <a
          key={item.id}
          href={item.href}
          className="hub-tab"
          aria-current={item.id === value ? "page" : undefined}
        >
          {item.label}
          {item.count === undefined ? null : <span className="hub-tab__count">{item.count}</span>}
        </a>
      ))}
    </nav>
  );
}
