// The verdict of a package as a badge (web-review §2.4): the outcome's word and shape once the
// station has a verdict, else the package state in words without a shape.

import { OUTCOME_WORD } from "@chapter/capture-contract";
import type { Outcome, PackageStatus } from "@/lib/station-types";
import { Badge, type BadgeTone } from "./Badge";
import { OUTCOME_GLYPH, StatusGlyph } from "./StatusGlyph";

const OUTCOME_TONE: Record<Outcome, BadgeTone> = {
  ready: "success",
  limited: "warning",
  blocked: "danger",
};

/** Words of a package without a verdict; an upload the phone stopped is never checked. */
export function pendingWords(status: PackageStatus, stopped = false): string {
  if (stopped) {
    return "Not checked";
  }
  switch (status) {
    case "checking":
      return "Checks running";
    case "check_error":
      return "Checks did not finish";
    default:
      return "Not checked yet";
  }
}

export interface VerdictBadgeProps {
  readonly status: PackageStatus;
  readonly outcome?: Outcome | undefined;
  /** An upload the phone stopped and replaced with a new revision ("Not checked", no "yet"). */
  readonly stopped?: boolean;
  /** Text after the word, for example " · latest". */
  readonly suffix?: string;
  readonly variant?: "soft" | "solid";
}

export function VerdictBadge({
  status,
  outcome,
  stopped = false,
  suffix = "",
  variant = "soft",
}: VerdictBadgeProps) {
  if (outcome === undefined) {
    return (
      <Badge tone="neutral" variant={variant}>
        {pendingWords(status, stopped)}
        {suffix}
      </Badge>
    );
  }
  return (
    <Badge tone={OUTCOME_TONE[outcome]} variant={variant}>
      <StatusGlyph kind={OUTCOME_GLYPH[outcome]} />
      {OUTCOME_WORD[outcome]}
      {suffix}
    </Badge>
  );
}
