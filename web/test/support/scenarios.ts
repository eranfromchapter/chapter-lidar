// The station data the review screen is drawn with (artboards 2h, 2i, 2j), built from the
// generated fixture packages: five projects as on the Projects artboard, the 424 sample with
// revision 2 in progress on the phone, and extra states for the status cards. Used by the
// component tests and the end-to-end station (web/e2e/mock-station.ts).

import type { Verdict } from "@chapter/capture-contract";
import type {
  HubProject,
  ModelingDecision,
  NextRevisionNotice,
  ReportSummary,
  StationPackage,
} from "@/lib/station-types";
import type { FakeStationData } from "./fake-station";
import { DEALS, IDS } from "./scenario-ids";
import {
  checkFixture,
  loadFixture,
  readJson,
  stationPackage,
  verdictFor,
  type FixturePackage,
} from "./fixtures";

export { DEALS, IDS };

/** The station's HUB deal page of a deal (station config HUB_WEB_DEAL_URL_TEMPLATE). */
export function hubDealUrl(dealId: string): string {
  return `https://hub.example/deals/${dealId}`;
}

const SAMPLE_REPORT_READY: ReportSummary = {
  status: "ready",
  generatedAt: "2026-10-17T15:20:44Z",
  pages: 28,
  bytes: 3_204_118,
  sha256: "e21f5c0d9b8a7f6e5d4c3b2a19087f6e5d4c3b2a19087f6e5d4c3b2a190888a0",
  checksPage: 4,
  floors: [
    {
      captureId: "33ede7f4-cfcb-4cd6-9af5-7daffee829a9",
      areaKey: "floor-1",
      roomsScanned: 12,
      roomsUnlabeled: 5,
      floorAreaSqFt: 807.5,
    },
  ],
  hub: { state: "uploaded" },
};

/** The sample's verdict-limited.json (fixtures/report/424-west-end). */
export function sampleLimitedVerdict(): Verdict {
  return readJson<Verdict>("fixtures/report/424-west-end/verdict-limited.json");
}

/** Revision 2 of the 424 sample as the phone describes it while it is not sealed. */
export function sampleNextRevision(verdict: Verdict, updatedAt: string): NextRevisionNotice {
  return {
    revision: 2,
    updatedAt,
    updatedBy: "Test Operator",
    changes: [
      {
        kind: "added",
        subject: "capture",
        title: "Primary closet",
        detail: "Scanned · one room · 5 files",
        ...(verdict.nextActions[0] === undefined
          ? {}
          : { answersNextAction: verdict.nextActions[0] }),
      },
      {
        kind: "added",
        subject: "field_control",
        title: "Room 4 ceiling height",
        detail: "Field control · 2,490 mm · 8' 2\"",
        method: "tape",
      },
      {
        kind: "added",
        subject: "photos",
        title: "3 photos",
        detail: "Primary closet · general, ceiling, opening",
      },
    ],
  };
}

function sampleDecisions(pkg: StationPackage): ModelingDecision[] {
  const file = (role: string) => pkg.files.find((item) => item.role === role)?.path ?? "";
  const controls = pkg.files.find((item) => item.role === "field_controls")?.path ?? "";
  const capture = { captureId: "33ede7f4-cfcb-4cd6-9af5-7daffee829a9", areaKey: "floor-1" };
  return [
    {
      decisionId: "d0000001-0000-4000-8000-000000000001",
      packageId: pkg.packageId,
      element: "Living Room walls",
      decision: "native Revit walls from plan.dxf, checked against Distance A",
      ...capture,
      sources: [{ path: file("plan_dxf") }, { path: controls, controlId: "floor-1-distance-a" }],
      note: "uncertainty: wall thickness; check at demolition",
      decidedBy: { name: "Robin Revit", userId: "44444444-4444-4444-8444-444444444444" },
      decidedAt: "2026-10-17T16:05:00Z",
    },
    {
      decisionId: "d0000001-0000-4000-8000-000000000002",
      packageId: pkg.packageId,
      element: "Kitchen cabinetry",
      decision: "mesh linked as reference only; not modeled",
      ...capture,
      sources: [{ path: file("mesh_glb") }],
      note: "uncertainty: none for the preliminary plan",
      decidedBy: { name: "Robin Revit", userId: "44444444-4444-4444-8444-444444444444" },
      decidedAt: "2026-10-17T16:22:00Z",
    },
    {
      decisionId: "d0000001-0000-4000-8000-000000000003",
      packageId: pkg.packageId,
      element: "Room 4 ceiling",
      decision: "height from the room schedule, marked approx.; volume not used",
      ...capture,
      sources: [{ path: file("rooms_csv") }],
      note: "next check: tape on the next visit (revision 2)",
      decidedBy: { name: "Dana BIM", userId: "11111111-1111-4111-8111-111111111111" },
      decidedAt: "2026-10-17T16:40:00Z",
    },
  ];
}

function minutesBefore(now: Date, minutes: number): string {
  const time = new Date(now.getTime() - minutes * 60_000);
  time.setUTCMilliseconds(0);
  return time.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Re-ids a fixture package (several drawn packages come from one fixture). */
function withIds(
  fixture: FixturePackage,
  ids: { packageId: string; revision?: number; supersedesPackageId?: string },
): FixturePackage {
  return {
    ...fixture,
    manifest: {
      ...fixture.manifest,
      packageId: ids.packageId,
      ...(ids.revision === undefined ? {} : { revision: ids.revision }),
      ...(ids.supersedesPackageId === undefined
        ? {}
        : { supersedesPackageId: ids.supersedesPackageId }),
    },
  };
}

function rechecked(
  fixture: FixturePackage,
  hubAddress: string,
  verdictId: string,
  evaluatedAt: string,
): Verdict {
  const verdict = checkFixture(fixture, hubAddress);
  return verdictFor(verdict, {
    verdictId,
    packageId: fixture.manifest.packageId,
    revision: fixture.manifest.revision,
    evaluatedAt,
  });
}

export interface ScenarioOptions {
  /** The spatial report of the 424 sample is ready (the plans phase); default pending. */
  readonly reportReady?: boolean;
}

/** The five projects of artboard 2h, with the 424 sample of 2i and 2j. */
export function drawnScenario(now: Date, options: ScenarioOptions = {}): FakeStationData {
  const packages: StationPackage[] = [];
  const verdicts: Record<string, Verdict> = {};

  // 424 West End Ave, Apt 4K: revision 1 Limited and published; revision 2 on the phone.
  const sample = loadFixture("sample-424/package");
  const sampleVerdict = sampleLimitedVerdict();
  const westEnd = stationPackage(sample, {
    dealId: DEALS.westEnd,
    createdAt: "2026-10-17T15:05:12Z",
    createdBy: "Test Operator",
    verdict: sampleVerdict,
    checksStartedAt: "2026-10-17T15:20:31Z",
    checksFinishedAt: "2026-10-17T15:20:44Z",
    publication: "published",
    publishedAt: "2026-10-17T15:21:30Z",
    report: options.reportReady === true ? SAMPLE_REPORT_READY : { status: "pending" },
    hubDealUrl: hubDealUrl(DEALS.westEnd),
    nextRevision: sampleNextRevision(sampleVerdict, minutesBefore(now, 35)),
    updatedAt: minutesBefore(now, 2),
  });
  packages.push(westEnd);
  verdicts[westEnd.packageId] = sampleVerdict;

  // 618 Valley Street: revision 1 uploading from the phone, 67 %, two floors.
  const house = loadFixture("two-floor-house/package");
  packages.push(
    stationPackage(withIds(house, { packageId: IDS.valley1 }), {
      dealId: DEALS.valley,
      createdAt: minutesBefore(now, 50),
      createdBy: "Casey Capture",
      status: "uploading",
      uploaded: 0.67,
      hubDealUrl: hubDealUrl(DEALS.valley),
      updatedAt: minutesBefore(now, 4),
    }),
  );

  // 24 Shawnee Road: revision 1 Blocked (address), revision 2 Ready and published.
  const apartment = loadFixture("two-room-apartment/package");
  const shawnee1 = withIds(apartment, { packageId: IDS.shawnee1, revision: 1 });
  const shawnee2 = withIds(apartment, {
    packageId: IDS.shawnee2,
    revision: 2,
    supersedesPackageId: IDS.shawnee1,
  });
  const address = apartment.captureRecord?.address.formatted ?? "";
  const shawneeVerdict1 = rechecked(
    shawnee1,
    "24 Shawnee Road, Testville, NY 00000",
    "b1000000-0000-4000-8000-000000000001",
    "2026-10-14T16:02:10Z",
  );
  const shawneeVerdict2 = rechecked(
    shawnee2,
    address,
    "b1000000-0000-4000-8000-000000000002",
    "2026-10-16T14:11:52Z",
  );
  const shawneePkg1 = stationPackage(shawnee1, {
    dealId: DEALS.shawnee,
    createdAt: "2026-10-14T15:48:00Z",
    createdBy: "Test Operator",
    verdict: shawneeVerdict1,
    hubDealUrl: hubDealUrl(DEALS.shawnee),
  });
  const shawneePkg2 = stationPackage(shawnee2, {
    dealId: DEALS.shawnee,
    createdAt: "2026-10-16T13:58:00Z",
    createdBy: "Test Operator",
    verdict: shawneeVerdict2,
    publication: "published",
    publishedAt: "2026-10-16T14:13:05Z",
    hubDealUrl: hubDealUrl(DEALS.shawnee),
    updatedAt: minutesBefore(now, 60 * 30),
  });
  packages.push(shawneePkg1, shawneePkg2);
  verdicts[shawneePkg1.packageId] = shawneeVerdict1;
  verdicts[shawneePkg2.packageId] = shawneeVerdict2;

  // A Blocked revision that was never published: the address does not match the HUB's.
  const wrongAddress = withIds(loadFixture("broken/wrong-address/package"), {
    packageId: IDS.blocked1,
  });
  const blockedVerdict = rechecked(
    wrongAddress,
    "15 Example Court, Testville, NY 00000",
    "b1000000-0000-4000-8000-000000000003",
    "2026-10-15T18:30:09Z",
  );
  const blocked = stationPackage(wrongAddress, {
    dealId: DEALS.blocked,
    createdAt: "2026-10-15T18:21:40Z",
    createdBy: "Test Operator",
    verdict: blockedVerdict,
    updatedAt: minutesBefore(now, 60 * 40),
  });
  packages.push(blocked);
  verdicts[blocked.packageId] = blockedVerdict;

  // 131 East 81st Street, Apt 9: revision 1 Ready and published.
  const box = withIds(loadFixture("box-room/package"), { packageId: IDS.east811 });
  const boxVerdict = rechecked(
    box,
    box.captureRecord?.address.formatted ?? "",
    "b1000000-0000-4000-8000-000000000004",
    "2026-10-12T15:40:00Z",
  );
  const east = stationPackage(box, {
    dealId: DEALS.east81,
    createdAt: "2026-10-12T15:30:00Z",
    createdBy: "Test Operator",
    verdict: boxVerdict,
    publication: "published",
    publishedAt: "2026-10-12T15:41:30Z",
    hubDealUrl: hubDealUrl(DEALS.east81),
    updatedAt: minutesBefore(now, 60 * 24 * 9),
  });
  packages.push(east);
  verdicts[east.packageId] = boxVerdict;

  const projects: HubProject[] = [
    {
      dealId: DEALS.westEnd,
      projectName: "424 West End Ave, Apt 4K",
      address: { formatted: sample.captureRecord?.address.formatted ?? "" },
      projectManager: { name: "Sam Rivera" },
    },
    { dealId: DEALS.valley, address: { formatted: "618 Valley Street" } },
    { dealId: DEALS.shawnee, address: { formatted: "24 Shawnee Road" } },
    { dealId: DEALS.blocked, address: { formatted: "15 Example Court" } },
    { dealId: DEALS.east81, address: { formatted: "131 East 81st Street, Apt 9" } },
  ];

  return {
    projects,
    packages,
    verdicts,
    decisions: { [westEnd.packageId]: sampleDecisions(westEnd) },
  };
}

/** No packages at all (the Projects page's empty state). */
export function emptyScenario(): FakeStationData {
  return { projects: [], packages: [], verdicts: {}, decisions: {} };
}

/**
 * The drawn scenario plus packages in the other states the pages draw: checks running, checks
 * that did not finish, two floors with a verdict, an upload the phone replaced, and a legacy
 * package with the retired phone report.
 */
export function statesScenario(now: Date): FakeStationData {
  const data = drawnScenario(now);
  const extra = (
    name: string,
    packageRoot: string,
    dealId: string,
    build: (fixture: FixturePackage) => StationPackage[],
  ) => {
    data.projects.push({ dealId, address: { formatted: name } });
    data.packages.push(...build(loadFixture(packageRoot)));
  };

  extra("9 Checking Lane", "l-shaped-room/package", "4419001", (fixture) => [
    stationPackage(withIds(fixture, { packageId: IDS.checking }), {
      dealId: "4419001",
      createdAt: minutesBefore(now, 20),
      createdBy: "Casey Capture",
      status: "checking",
      checksStartedAt: minutesBefore(now, 3),
    }),
  ]);
  extra("10 Error Street", "l-shaped-room/package", "4419002", (fixture) => [
    stationPackage(withIds(fixture, { packageId: IDS.checkError }), {
      dealId: "4419002",
      createdAt: minutesBefore(now, 90),
      createdBy: "Casey Capture",
      status: "check_error",
      checksStartedAt: minutesBefore(now, 80),
      checksFinishedAt: minutesBefore(now, 79),
    }),
  ]);
  extra("2 Floors Avenue", "two-floor-house/package", "4419003", (fixture) => {
    const own = withIds(fixture, { packageId: IDS.twoFloors });
    const verdict = rechecked(
      own,
      fixture.captureRecord?.address.formatted ?? "",
      "b1000000-0000-4000-8000-000000000005",
      "2026-10-18T13:20:00Z",
    );
    data.verdicts[IDS.twoFloors] = verdict;
    return [
      stationPackage(own, {
        dealId: "4419003",
        createdAt: "2026-10-18T13:01:00Z",
        createdBy: "Test Operator",
        verdict,
        publication: "published",
        publishedAt: "2026-10-18T13:21:00Z",
      }),
    ];
  });
  extra("7 Stopped Road", "box-room/package", "4419004", (fixture) => [
    stationPackage(withIds(fixture, { packageId: IDS.stopped1 }), {
      dealId: "4419004",
      createdAt: minutesBefore(now, 200),
      createdBy: "Casey Capture",
      status: "uploading",
      uploaded: 0.3,
    }),
    stationPackage(
      withIds(fixture, { packageId: IDS.stopped2, revision: 2, supersedesPackageId: IDS.stopped1 }),
      {
        dealId: "4419004",
        createdAt: minutesBefore(now, 30),
        createdBy: "Casey Capture",
        status: "uploading",
        uploaded: 0.9,
      },
    ),
  ]);
  extra("1 Legacy Place", "legacy-1.0.0/package", "4419005", (fixture) => {
    const own = withIds(fixture, { packageId: IDS.legacy });
    const verdict = rechecked(
      own,
      fixture.captureRecord?.address.formatted ?? "",
      "b1000000-0000-4000-8000-000000000006",
      "2026-09-30T15:20:00Z",
    );
    data.verdicts[IDS.legacy] = verdict;
    return [
      stationPackage(own, {
        dealId: "4419005",
        createdAt: "2026-09-30T15:01:00Z",
        createdBy: "Test Operator",
        verdict,
        publication: "published",
        publishedAt: "2026-09-30T15:21:00Z",
      }),
    ];
  });
  return data;
}
