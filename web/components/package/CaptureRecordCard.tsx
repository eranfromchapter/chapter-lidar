// "Capture record" (web-review §6.4.9 card 1, addendum D1): what the operator recorded on site.

import { notScannedRooms, notScannedText } from "@chapter/capture-contract";
import { Card } from "@/components/hub/Card";
import { StatusGlyph } from "@/components/hub/StatusGlyph";
import { compassRecordText } from "@/lib/compass";
import { MODE_LABEL } from "@/lib/format";
import type { CaptureRecord, ReportSummary } from "@/lib/station-types";
import { AsideRow } from "./AsideRow";

export interface CaptureRecordCardProps {
  readonly record: CaptureRecord | undefined;
  readonly report?: ReportSummary;
}

/** Each capture's coverage notes, one per line, prefixed by the capture with several. */
export function coverageNotesText(record: CaptureRecord): string {
  const notes = record.captures
    .filter((capture) => (capture.coverageNotes ?? "").trim().length > 0)
    .map((capture) =>
      record.captures.length > 1
        ? `${capture.label}: ${(capture.coverageNotes ?? "").trim()}`
        : (capture.coverageNotes ?? "").trim(),
    );
  return notes.length === 0 ? "None" : notes.join("\n");
}

export function CaptureRecordCard({ record, report }: CaptureRecordCardProps) {
  if (record === undefined) {
    return (
      <Card padding="md" label="Capture record">
        <div className="hub-stack hub-stack--10">
          <span className="hub-eyebrow">Capture record</span>
          <span className="text-13 text-muted">
            The capture record is available once the package is sealed.
          </span>
        </div>
      </Card>
    );
  }
  const modes = [...new Set(record.captures.map((capture) => MODE_LABEL[capture.mode]))];
  const notScanned = notScannedRooms(record).length;
  const scanned = report?.floors?.reduce((sum, floor) => sum + floor.roomsScanned, 0);
  return (
    <Card padding="md" label="Capture record">
      <div className="hub-stack hub-stack--10">
        <span className="hub-eyebrow">Capture record</span>
        <div>
          <AsideRow label="Address" glyph>
            {record.address.confirmedOnSite ? (
              <>
                <StatusGlyph kind="circle" color="var(--status-success)" />
                Confirmed on site
              </>
            ) : (
              <>
                <StatusGlyph kind="square" color="var(--status-danger)" />
                Not confirmed on site
              </>
            )}
          </AsideRow>
          <AsideRow label="Floors">
            {record.captures.length} · {modes.join(", ")}
          </AsideRow>
          <AsideRow label="Rooms">
            {scanned === undefined
              ? `${notScanned} not scanned`
              : `${scanned} scanned · ${notScanned} not scanned`}
          </AsideRow>
          <AsideRow label="Not scanned" wraps>
            {notScannedText(record)}
          </AsideRow>
          <AsideRow label="Coverage notes" wraps>
            {coverageNotesText(record)}
          </AsideRow>
          <AsideRow label="Compass" wraps>
            {compassRecordText(record)}
          </AsideRow>
          <AsideRow label="Device">
            {record.device.marketingName ?? record.device.model} · app {record.app.version}
          </AsideRow>
          <AsideRow label="Operator">{record.operator.name}</AsideRow>
        </div>
      </div>
    </Card>
  );
}
