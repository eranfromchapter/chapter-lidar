// "Field controls" (web-review §6.4.9 card 2): the independent tape and laser measurements of the
// visit, as the station parsed them at sealing.

import { Card } from "@/components/hub/Card";
import { fileDownloadRoute } from "@/lib/files-view";
import { formatMm, plural } from "@/lib/format";
import type { CaptureRecord, FieldControls, StationPackage } from "@/lib/station-types";
import { AsideRow } from "./AsideRow";

export interface FieldControlsCardProps {
  readonly pkg: StationPackage;
}

/** " · tape", " · laser", " · tape and laser" by the instruments the controls used. */
export function methodsSuffix(controls: FieldControls): string {
  const methods = new Set<string>();
  for (const item of controls.distances) methods.add(item.measurement.method);
  for (const item of controls.ceilingHeights) methods.add(item.measurement.method);
  for (const item of controls.openings) methods.add(item.width.method);
  for (const item of controls.floorToFloor) methods.add(item.measurement.method);
  if (methods.size === 0) {
    return "";
  }
  const ordered = ["tape", "laser"].filter((method) => methods.has(method));
  return ` · ${ordered.join(" and ")}`;
}

function DistanceRows({
  controls,
  record,
  axis,
}: {
  readonly controls: FieldControls;
  readonly record: CaptureRecord | undefined;
  readonly axis: "A" | "B";
}) {
  const captures = record?.captures ?? [];
  const name = `long distance ${axis}`;
  if (captures.length <= 1) {
    const found = controls.distances.find((item) => item.axis === axis);
    return (
      <AsideRow
        label={`Long distance ${axis}`}
        mono={found !== undefined}
        muted={found === undefined}
      >
        {found === undefined ? "Not recorded" : formatMm(found.measurement.valueMm)}
      </AsideRow>
    );
  }
  return (
    <>
      {captures.map((capture) => {
        const found = controls.distances.find(
          (item) => item.axis === axis && item.capture.captureId === capture.captureId,
        );
        return (
          <AsideRow
            key={capture.captureId}
            label={`${capture.label} · ${name}`}
            mono={found !== undefined}
            muted={found === undefined}
          >
            {found === undefined ? "Not recorded" : formatMm(found.measurement.valueMm)}
          </AsideRow>
        );
      })}
    </>
  );
}

export function FieldControlsCard({ pkg }: FieldControlsCardProps) {
  const file = pkg.files.find((item) => item.role === "field_controls");
  const controls = pkg.fieldControls;
  let body;
  if (pkg.status === "uploading") {
    body = (
      <span className="text-13 text-muted">
        Field controls are shown once the package is sealed.
      </span>
    );
  } else if (file === undefined) {
    body = <span className="text-13 text-muted">No field controls in this package.</span>;
  } else if (controls === undefined) {
    body = (
      <span className="text-13 text-muted">
        The station has not read the field controls of this package yet.{" "}
        {file.status === "verified" ? (
          <a href={fileDownloadRoute(pkg.packageId, file.path)} rel="nofollow">
            Download field-controls.json
          </a>
        ) : null}
      </span>
    );
  }
  const record = pkg.captureRecord;
  const oneFloor = (record?.captures.length ?? pkg.captures.length) <= 1;
  return (
    <Card padding="md" label="Field controls">
      <div className="hub-stack hub-stack--10">
        <span className="hub-eyebrow">
          Field controls{controls === undefined ? "" : methodsSuffix(controls)}
        </span>
        {body ??
          (controls === undefined || file === undefined ? null : (
            <>
              <div>
                <DistanceRows controls={controls} record={record} axis="A" />
                <DistanceRows controls={controls} record={record} axis="B" />
                <AsideRow label="Ceiling heights">
                  {plural(controls.ceilingHeights.length, "room")}
                </AsideRow>
                <AsideRow label="Openings">{controls.openings.length}</AsideRow>
                <AsideRow label="Floor to floor · landmarks">
                  {oneFloor && controls.floorToFloor.length === 0 && controls.landmarks.length === 0
                    ? "none · one floor"
                    : `${controls.floorToFloor.length} · ${controls.landmarks.length}`}
                </AsideRow>
              </div>
              <span className="text-12 text-muted">
                Tolerance: within 1% or 1 in (25.4 mm), whichever is larger.{" "}
                {file.status === "verified" ? (
                  <a href={fileDownloadRoute(pkg.packageId, file.path)} rel="nofollow">
                    Download field-controls.json
                  </a>
                ) : null}
              </span>
            </>
          ))}
      </div>
    </Card>
  );
}
