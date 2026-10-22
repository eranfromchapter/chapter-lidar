// The white topbar of every review page (web-review §3.2): the page title, the project search
// and "Open the HUB" when HUB_APP_URL is set.

import { Button } from "@/components/hub/Button";
import { hubAppUrl } from "@/lib/links";
import { SearchField } from "./SearchField";

export interface TopbarProps {
  readonly title: string;
  /** The current search, prefilled on the Projects page. */
  readonly query?: string;
}

export function Topbar({ title, query }: TopbarProps) {
  const hub = hubAppUrl();
  return (
    <header className="topbar">
      <h1 className="topbar__title" title={title.length > 0 ? title : undefined}>
        {title}
      </h1>
      <div className="topbar__actions">
        <SearchField query={query} />
        {hub === null ? null : (
          <Button variant="outline" size="sm" href={hub} external className="topbar__hub">
            Open the HUB
          </Button>
        )}
      </div>
    </header>
  );
}
