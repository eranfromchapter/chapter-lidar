// "Station" (web-review §6.4.9 card 3, addendum D4): the package's way through the station:
// registered, checks, verdict, HUB publication. Shown to every role.

import { OUTCOME_WORD, type Verdict } from "@chapter/capture-contract";
import { Card } from "@/components/hub/Card";
import { OUTCOME_GLYPH, StatusGlyph, type GlyphKind } from "@/components/hub/StatusGlyph";
import { formatDateTime, formatDayTime, plural } from "@/lib/format";
import type { PackageSummary } from "@/lib/station-types";

export interface StationStep {
  readonly glyph: GlyphKind;
  readonly color: string;
  readonly label: string;
  /** ISO time of the step, or undefined for "—". */
  readonly at?: string;
  /** Words instead of a time ("after upload"). */
  readonly note?: string;
}

const SUCCESS = "var(--status-success)";
const DANGER = "var(--status-danger)";
const WAITING = "var(--text-muted)";

const OUTCOME_COLOR = {
  ready: "var(--status-success)",
  limited: "var(--status-warning)",
  blocked: "var(--status-danger)",
} as const;

/** The four steps of a package (registered, checks, verdict, publication). */
export function stationSteps(pkg: PackageSummary, verdict: Verdict | null): StationStep[] {
  const steps: StationStep[] = [
    { glyph: "circle", color: SUCCESS, label: "Registered", at: pkg.createdAt },
  ];
  switch (pkg.status) {
    case "uploading":
      steps.push({ glyph: "ring", color: WAITING, label: "Checks", note: "after upload" });
      break;
    case "checks_queued":
    case "checking":
      steps.push({
        glyph: "ring",
        color: WAITING,
        label: "Checks running",
        ...(pkg.checks?.startedAt === undefined ? {} : { at: pkg.checks.startedAt }),
      });
      break;
    case "check_error":
      steps.push({ glyph: "square", color: DANGER, label: "Checks did not finish" });
      break;
    case "verdict_ready": {
      const rules = pkg.checks?.rules ?? verdict?.checks.length;
      steps.push({
        glyph: "circle",
        color: SUCCESS,
        label: rules === undefined ? "Checks run" : `Checks run · ${plural(rules, "rule")}`,
        ...(pkg.checks?.finishedAt === undefined ? {} : { at: pkg.checks.finishedAt }),
      });
      break;
    }
  }
  const outcome = verdict?.outcome ?? pkg.verdict?.outcome;
  const evaluatedAt = verdict?.evaluatedAt ?? pkg.verdict?.evaluatedAt;
  steps.push(
    outcome === undefined
      ? { glyph: "ring", color: WAITING, label: "Verdict" }
      : {
          glyph: OUTCOME_GLYPH[outcome],
          color: OUTCOME_COLOR[outcome],
          label: `Verdict · ${OUTCOME_WORD[outcome]}`,
          ...(evaluatedAt === undefined ? {} : { at: evaluatedAt }),
        },
  );
  const publication = pkg.publication;
  if (publication?.status === "published") {
    steps.push({
      glyph: "circle",
      color: SUCCESS,
      label: "Published to the HUB",
      ...(publication.publishedAt === undefined ? {} : { at: publication.publishedAt }),
    });
  } else if (publication?.status === "publish_failed") {
    steps.push({ glyph: "square", color: DANGER, label: "Publishing to the HUB failed" });
  } else if (publication === undefined && outcome === "blocked") {
    steps.push({ glyph: "dash", color: WAITING, label: "Not published · re-seal needed" });
  } else {
    steps.push({ glyph: "ring", color: WAITING, label: "Publishing to the HUB" });
  }
  return steps;
}

export interface StationCardProps {
  readonly pkg: PackageSummary;
  readonly verdict: Verdict | null;
  /** "HUB › Files › Capture › r{n} →" (bim, admin, published and configured). */
  readonly hubFilesUrl?: string | null;
}

export function StationCard({ pkg, verdict, hubFilesUrl }: StationCardProps) {
  const steps = stationSteps(pkg, verdict);
  let previous: string | undefined;
  return (
    <Card padding="md" label="Station">
      <div className="hub-stack hub-stack--10">
        <span className="hub-eyebrow">Station</span>
        <div>
          {steps.map((step) => {
            const time = step.at === undefined ? undefined : formatDayTime(step.at, previous);
            if (step.at !== undefined) {
              previous = step.at;
            }
            return (
              <div key={step.label} className="station-row">
                <StatusGlyph kind={step.glyph} color={step.color} />
                <span className="station-row__label">{step.label}</span>
                <span className="station-row__time">
                  {time === undefined || step.at === undefined ? (
                    (step.note ?? "—")
                  ) : (
                    <time dateTime={step.at} title={formatDateTime(step.at)}>
                      {time}
                    </time>
                  )}
                </span>
              </div>
            );
          })}
        </div>
        {hubFilesUrl === undefined || hubFilesUrl === null ? null : (
          <a className="strong-link" href={hubFilesUrl} target="_blank" rel="noopener noreferrer">
            HUB › Files › Capture › r{pkg.revision} →
            <span className="visually-hidden"> (opens in a new tab)</span>
          </a>
        )}
      </div>
    </Card>
  );
}
