"use client";

// The decision form (web-review §6.4.7): element, the source used (option keys built on the
// server, §6.4.8), the decision and the remaining uncertainty. The server action checks the
// session and role, resolves the key against the package and lets the station record the author
// and time.

import { useActionState } from "react";
import { EMPTY_VALUES, LIMITS, type DecisionFormState, type SourceGroup } from "@/lib/decisions";
import { Button } from "./hub/Button";
import { Select } from "./hub/Select";
import { TextField } from "./hub/TextField";

export interface DecisionFormProps {
  readonly packageId: string;
  readonly sources: readonly SourceGroup[];
  readonly action: (state: DecisionFormState, form: FormData) => Promise<DecisionFormState>;
}

const INITIAL: DecisionFormState = { status: "idle", attempt: 0 };

export function DecisionForm({ packageId, sources, action }: DecisionFormProps) {
  const [state, formAction, pending] = useActionState(action, INITIAL);
  const values = state.status === "error" ? state.values : EMPTY_VALUES;
  return (
    // Remounted after each answer so the fields show the echoed values (or clear after a save).
    <form
      key={state.attempt}
      action={formAction}
      className="decision-form"
      aria-label="Log a decision"
    >
      <input type="hidden" name="packageId" value={packageId} />
      <TextField
        id="decision-element"
        name="element"
        label="Element or area"
        required
        maxLength={LIMITS.element}
        defaultValue={values.element}
        placeholder="Floor 1 · kitchen east wall"
      />
      <Select
        id="decision-source"
        name="source"
        label="Source used"
        required
        defaultValue={values.source}
        options={[{ value: "", label: "Choose a source", disabled: true }]}
        groups={sources}
      />
      <TextField
        id="decision-decision"
        name="decision"
        label="Decision"
        required
        maxLength={LIMITS.decision}
        defaultValue={values.decision}
        placeholder="Modeled as a native Revit wall, 4,520 mm"
      />
      <TextField
        id="decision-note"
        name="note"
        label="Remaining uncertainty and next check"
        maxLength={LIMITS.note}
        defaultValue={values.note}
        placeholder="Wall thickness unknown; verify at demolition"
      />
      <div className="decision-form__footer">
        <span className="text-12 text-muted">
          Saved through the station with your name and time. Entries cannot be edited, only followed
          by a new one.
        </span>
        <div className="decision-form__submit">
          {state.status === "error" ? (
            <span role="alert" className="form-message form-message--error">
              {state.message}
            </span>
          ) : null}
          {state.status === "saved" ? (
            <span role="status" className="form-message form-message--saved">
              {state.message}
            </span>
          ) : null}
          <Button type="submit" variant="primary" size="md" disabled={pending}>
            {pending ? "Saving…" : "Save decision"}
          </Button>
        </div>
      </div>
    </form>
  );
}
