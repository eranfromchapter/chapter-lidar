"use client";

import { useActionState } from "react";
import { EMPTY_VALUES, LIMITS, type DecisionFormState } from "@/lib/decisions";

export interface DecisionSourceOption {
  readonly path: string;
  readonly label: string;
}

export interface DecisionFormProps {
  readonly packageId: string;
  readonly sources: readonly DecisionSourceOption[];
  readonly action: (state: DecisionFormState, form: FormData) => Promise<DecisionFormState>;
}

const INITIAL: DecisionFormState = { status: "idle", attempt: 0 };

/** Logs the source used for one modeling decision (screen-review decision form). */
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
      <div className="field">
        <label htmlFor="el">Element or area</label>
        <input
          id="el"
          name="element"
          required
          maxLength={LIMITS.element}
          defaultValue={values.element}
          placeholder="Floor 1 · kitchen east wall"
        />
      </div>
      <div className="field">
        <label htmlFor="src">Source used</label>
        <select id="src" name="source" required defaultValue={values.source}>
          <option value="" disabled>
            Choose a package file
          </option>
          {sources.map((source) => (
            <option key={source.path} value={source.path}>
              {source.label}
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label htmlFor="dec">Decision</label>
        <input
          id="dec"
          name="decision"
          required
          maxLength={LIMITS.decision}
          defaultValue={values.decision}
          placeholder="Modeled as native Revit wall, 4 520 mm"
        />
      </div>
      <div className="field">
        <label htmlFor="unc">Remaining uncertainty and next check</label>
        <input
          id="unc"
          name="note"
          maxLength={LIMITS.note}
          defaultValue={values.note}
          placeholder="Wall thickness unknown; verify at demo"
        />
      </div>
      <div className="decision-form__footer">
        <button type="submit" className="button-primary" disabled={pending}>
          {pending ? "Saving…" : "Save decision"}
        </button>
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
      </div>
    </form>
  );
}
