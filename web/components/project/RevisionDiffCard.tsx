// "What revision N adds" (web-review §6.3.1, addendum D7): up to six change tiles, the state of
// the revision and what happens to the revision it is compared with.

import { Card } from "@/components/hub/Card";
import { plural } from "@/lib/format";
import { visibleTiles, type ChangeTile } from "@/lib/revision-diff";

/** The revision the new one is compared with, and whether the station gave it a verdict. */
export interface RevisionBase {
  readonly revision: number;
  readonly hasVerdict: boolean;
}

export interface RevisionDiffCardProps {
  readonly revision: number;
  /** "from the phone, not sealed yet", "sealed, checks running", ... */
  readonly state: string;
  readonly tiles: readonly ChangeTile[];
  /** Absent when the station no longer has the revision this one supersedes. */
  readonly base?: RevisionBase;
}

/** The footer: what stays of the compared revision and what the station does with this one. */
export function revisionFooter(revision: number, base: RevisionBase | undefined): string {
  if (base === undefined) {
    return `The station checks revision ${revision} as a whole package and issues its spatial report.`;
  }
  if (base.hasVerdict) {
    return `Revision ${base.revision} stays unchanged and keeps its verdict. The station checks revision ${revision} as a whole package and issues a new spatial report.`;
  }
  return `Revision ${base.revision} stays unchanged. The station checks revision ${revision} as a whole package and issues its spatial report.`;
}

export function RevisionDiffCard({ revision, state, tiles, base }: RevisionDiffCardProps) {
  const { shown, more } = visibleTiles(tiles);
  const titleId = `revision-${revision}-adds`;
  return (
    <Card padding="md" labelledBy={titleId}>
      <div className="hub-stack hub-stack--10">
        <div className="card-head">
          <h3 className="card-title" id={titleId}>
            What revision {revision} adds
          </h3>
          <span className="card-head__aside">{state}</span>
        </div>
        {shown.length === 0 ? null : (
          <div className="tiles">
            {shown.map((tile, index) => (
              <div key={`${tile.title}-${index}`} className="tile">
                <div className="tile__title">{tile.title}</div>
                <div className="tile__sub">{tile.sub}</div>
              </div>
            ))}
          </div>
        )}
        {more === 0 ? null : (
          <span className="text-13 text-muted">+{plural(more, "more change", "more changes")}</span>
        )}
        <span className="text-12 text-muted">{revisionFooter(revision, base)}</span>
      </div>
    </Card>
  );
}
