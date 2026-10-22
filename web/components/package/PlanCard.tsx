// The plan card of the package page (web-review §6.4.4, addendum D1): the plan preview of one
// floor with its downloads, orientation, room facts from the spatial report and the rooms not
// scanned. One tab per floor when the package has several.

import { notScannedRooms, notScannedRoomText } from "@chapter/capture-contract";
import { Badge } from "@/components/hub/Badge";
import { Card } from "@/components/hub/Card";
import { Tabs } from "@/components/hub/Tabs";
import { orientationText } from "@/lib/compass";
import { fileDownloadRoute, previewRoute } from "@/lib/files-view";
import { formatSqFt, MODE_LABEL } from "@/lib/format";
import type { CaptureRecord, PackageFile, StationPackage } from "@/lib/station-types";
import { PlanPreview } from "./PlanPreview";

type Capture = CaptureRecord["captures"][number];

export interface PlanCardProps {
  readonly pkg: StationPackage & { captureRecord: CaptureRecord };
  /** The areaKey from ?floor=; the first capture when absent or unknown. */
  readonly floor?: string;
}

function fileOf(
  pkg: StationPackage,
  capture: Capture,
  role: PackageFile["role"],
): PackageFile | undefined {
  return pkg.files.find(
    (file) =>
      file.role === role && file.captureId === capture.captureId && file.status === "verified",
  );
}

/** The capture a plan card shows. */
export function selectedCapture(record: CaptureRecord, floor: string | undefined): Capture {
  const first = record.captures[0] as Capture;
  return record.captures.find((capture) => capture.areaKey === floor) ?? first;
}

function Fact({ label, children }: { readonly label: string; readonly children: string }) {
  return (
    <div className="fact">
      <span className="fact__label">{label}</span>
      <span className="fact__value">{children}</span>
    </div>
  );
}

export function PlanCard({ pkg, floor }: PlanCardProps) {
  const record = pkg.captureRecord;
  const capture = selectedCapture(record, floor);
  const png = fileOf(pkg, capture, "plan_png");
  const dxf = fileOf(pkg, capture, "plan_dxf");
  const sheet = fileOf(pkg, capture, "plan_pdf");
  const facts = pkg.report?.floors?.find((item) => item.captureId === capture.captureId);
  const notScanned = notScannedRooms(record)
    .filter((room) => room.captureId === capture.captureId)
    .map((room) => notScannedRoomText(room));
  const links = [
    { file: png, text: "plan.png" },
    { file: dxf, text: "plan.dxf" },
    { file: sheet, text: "plan sheet PDF" },
  ].filter((link): link is { file: PackageFile; text: string } => link.file !== undefined);

  return (
    <Card padding="md" labelledBy="plan-title" id="plan">
      <div className="hub-stack hub-stack--14">
        <div className="plan-head">
          <div className="plan-head__left">
            <h3 className="card-title" id="plan-title">
              Plan
            </h3>
            <Badge tone="accent">
              {capture.label} · {MODE_LABEL[capture.mode]}
            </Badge>
          </div>
          {links.length === 0 ? null : (
            <div className="plan-links">
              {links.map((link) => (
                <a
                  key={link.text}
                  href={fileDownloadRoute(pkg.packageId, link.file.path)}
                  rel="nofollow"
                  aria-label={`Download ${link.text} of ${capture.label}`}
                >
                  {link.text}
                </a>
              ))}
            </div>
          )}
        </div>
        {record.captures.length > 1 ? (
          <Tabs
            label="Floors"
            value={capture.areaKey}
            items={record.captures.map((item) => ({
              id: item.areaKey,
              label: item.label,
              href: `?floor=${encodeURIComponent(item.areaKey)}#plan`,
            }))}
          />
        ) : null}
        <div className="plan-body">
          <div className="plan-preview">
            {png === undefined ? (
              <p className="plan-preview__message" style={{ margin: 0 }}>
                No plan preview: this capture has no verified plan.png.
              </p>
            ) : (
              <PlanPreview
                src={previewRoute(pkg.packageId, png.path)}
                alt={`Plan of ${capture.label}`}
              />
            )}
          </div>
          <div className="facts">
            <Fact label="Preview">
              From plan.png · fitted, not to scale. Use the plan sheet PDF for the drawing to scale.
            </Fact>
            <Fact label="Orientation">{orientationText(capture)}</Fact>
            {facts === undefined ? null : (
              <Fact label="Rooms">
                {`${facts.roomsScanned} scanned · ${formatSqFt(facts.floorAreaSqFt)}, sum of rooms${
                  facts.roomsUnlabeled > 0 ? ` · ${facts.roomsUnlabeled} unlabeled` : ""
                }`}
              </Fact>
            )}
            <Fact label="Not scanned">
              {notScanned.length === 0 ? "None" : notScanned.join(" · ")}
            </Fact>
          </div>
        </div>
      </div>
    </Card>
  );
}
