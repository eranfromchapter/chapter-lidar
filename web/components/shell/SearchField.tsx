// The topbar search (web-review §3.2): a pill that searches projects by address, deal or capture
// id. A plain GET form to the Projects page; no script.

import { SearchIcon } from "@/components/hub/icons";
import { QUERY_MAX } from "@/lib/review";

export function SearchField({ query = "" }: { readonly query?: string }) {
  return (
    <form role="search" action="/" method="get" className="topbar__search">
      <label className="search-pill">
        <SearchIcon size={16} stroke="var(--text-muted)" />
        <input
          className="search-pill__input"
          type="search"
          name="q"
          maxLength={QUERY_MAX}
          autoComplete="off"
          placeholder="Address, deal or capture id"
          aria-label="Search projects"
          defaultValue={query}
        />
      </label>
    </form>
  );
}
