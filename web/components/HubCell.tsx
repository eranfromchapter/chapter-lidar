// The "In the HUB" cell of the package tables (web-review §6.1): the station's publication
// state in words; breaks only between phrases and before a date.

import type { CellTone } from "@/lib/review";
import { Phrases } from "./Phrases";

const PUBLISHED = "Published ";

export function HubCell({ hub }: { readonly hub: { text: string; tone: CellTone } }) {
  const className =
    hub.tone === "muted"
      ? "hub-table__muted"
      : hub.tone === "danger"
        ? "hub-table__danger"
        : undefined;
  return (
    <td className={className}>
      {hub.text.startsWith(PUBLISHED) ? (
        <>
          Published <span className="phrase">{hub.text.slice(PUBLISHED.length)}</span>
        </>
      ) : (
        <Phrases text={hub.text} />
      )}
    </td>
  );
}
