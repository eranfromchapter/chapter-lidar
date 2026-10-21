// "What revision N adds" (web-review §6.3.1, addendum D7): up to six change tiles, the state of
// the revision and what happens to the previous one.

import { Card } from "@/components/hub/Card";
import { plural } from "@/lib/format";
import { visibleTiles, type ChangeTile } from "@/lib/revision-diff";

export interface RevisionDiffCardProps {
  readonly revision: number;
  /** "from the phone, not sealed yet", "sealed, checks running", ... */
  readonly state: string;
  readonly tiles: readonly ChangeTile[];
}

export function RevisionDiffCard({ revision, state, tiles }: RevisionDiffCardProps) {
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
        <span className="text-12 text-muted">
          Revision {revision - 1} stays unchanged and keeps its verdict. The station checks revision{" "}
          {revision} as a whole package and issues a new spatial report.
        </span>
      </div>
    </Card>
  );
}
