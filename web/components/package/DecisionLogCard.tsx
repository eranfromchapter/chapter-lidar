// "Modeling decision log" on the package page (web-review §6.4.7): the form and every entry of
// this package, oldest first as the station returns them.

import { Card } from "@/components/hub/Card";
import { DecisionForm } from "@/components/DecisionForm";
import { DecisionList } from "@/components/DecisionList";
import { plural } from "@/lib/format";
import type { DecisionContext, DecisionFormState, SourceGroup } from "@/lib/decisions";
import type { ModelingDecision } from "@/lib/station-types";

export interface DecisionLogCardProps {
  readonly packageId: string;
  readonly decisions: readonly ModelingDecision[];
  readonly context: DecisionContext;
  readonly sources: readonly SourceGroup[];
  readonly action: (state: DecisionFormState, form: FormData) => Promise<DecisionFormState>;
}

export function DecisionLogCard({
  packageId,
  decisions,
  context,
  sources,
  action,
}: DecisionLogCardProps) {
  return (
    <Card padding="md" labelledBy="decisions-title" id="decisions">
      <div className="hub-stack hub-stack--16">
        <div className="card-head card-head--center">
          <h3 className="card-title" id="decisions-title">
            Modeling decision log
          </h3>
          <span className="table-head__meta">
            {plural(decisions.length, "entry", "entries")} · the source used for each modeling
            decision, its remaining uncertainty and the next check
          </span>
        </div>
        <DecisionForm packageId={packageId} sources={sources} action={action} />
        <DecisionList entries={decisions.map((decision) => ({ decision, context }))} />
      </div>
    </Card>
  );
}
