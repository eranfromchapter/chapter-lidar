// Shared test data: a two-capture package held in memory, its verdict and capture record, and
// helpers to publish it against the fake HUB and read the report text.

import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import type { CaptureRecord, Role, Verdict } from "@chapter/capture-contract";
import { extractText, getDocumentProxy } from "unpdf";
import {
  HubPublisher,
  MemoryPublicationStore,
  type HubApi,
  type HubPublisherOptions,
  type PackageFileRecord,
  type PublishPackage,
  type PublishRequest,
} from "../src/index.js";
import { FAKE_DEAL_ID, FakeHub, createFakeHubApi } from "../src/fake/index.js";

export const REVIEW_BASE_URL = "https://review.capture.example.test";
export const MIB = 1024 * 1024;

export function sha256(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

const LIMITED_EXAMPLE = JSON.parse(
  readFileSync(
    new URL("../../../contract/examples/verdict/valid/limited.json", import.meta.url),
    "utf8",
  ),
) as Verdict;

export interface TestPackageOptions {
  readonly dealId?: string;
  /** Size of floor-1's plan.pdf (default small). */
  readonly planPdfBytes?: number;
  readonly verdict?: Partial<Verdict>;
}

export interface TestPackage {
  readonly pkg: PublishPackage;
  readonly verdict: Verdict;
  readonly captureRecord: CaptureRecord;
  readonly files: Map<string, Uint8Array>;
  readonly manifestBytes: Uint8Array;
  /** Paths read through readFile, in order. */
  readonly reads: string[];
  request(overrides?: Partial<PublishRequest>): PublishRequest;
  /** (folder, name) of every file that must be uploaded. */
  expectedUploads(): Array<{ folder: string; name: string }>;
}

function bytesOf(text: string, size?: number): Uint8Array {
  if (size === undefined) {
    return new TextEncoder().encode(text);
  }
  const data = new Uint8Array(size);
  const seed = new TextEncoder().encode(text);
  for (let i = 0; i < size; i += 1) {
    data[i] = seed[i % seed.length] ?? 0;
  }
  return data;
}

const MIME: Partial<Record<Role, string>> = {
  plan_dxf: "image/vnd.dxf",
  rooms_csv: "text/csv",
  plan_pdf: "application/pdf",
  spatial_report_pdf: "application/pdf",
  plan_png: "image/png",
  mesh_glb: "model/gltf-binary",
  point_cloud_las: "application/vnd.las",
  photo: "image/jpeg",
  capture_record: "application/json",
  field_controls: "application/json",
};

export function makeTestPackage(options: TestPackageOptions = {}): TestPackage {
  const packageId = randomUUID();
  const visitId = randomUUID();
  const dealId = options.dealId ?? FAKE_DEAL_ID;
  const captures = [
    { captureId: randomUUID(), areaKey: "floor-1", label: "Floor 1" },
    { captureId: randomUUID(), areaKey: "floor-2", label: "Floor 2" },
  ];
  const files = new Map<string, Uint8Array>();
  const records: PackageFileRecord[] = [];
  const add = (path: string, role: Role, data: Uint8Array, capture?: (typeof captures)[number]) => {
    files.set(path, data);
    records.push({
      path,
      role,
      sha256: sha256(data),
      bytes: data.byteLength,
      ...(MIME[role] === undefined ? {} : { mime: MIME[role] }),
      ...(capture === undefined ? {} : { captureId: capture.captureId, areaKey: capture.areaKey }),
    });
  };
  add(
    `Source Register/${visitId}/capture-record.json`,
    "capture_record",
    bytesOf(`{"record":"${visitId}"}`),
  );
  add(
    `Field Measurements/${visitId}/field-controls.json`,
    "field_controls",
    bytesOf(`{"controls":"${visitId}"}`),
  );
  for (const capture of captures) {
    const dir = `Original Exports/${capture.areaKey}/${capture.captureId}`;
    add(`${dir}/plan.dxf`, "plan_dxf", bytesOf(`DXF ${capture.captureId}`), capture);
    add(`${dir}/rooms.csv`, "rooms_csv", bytesOf(`room,area\n${capture.label},12.0\n`), capture);
    add(
      `${dir}/plan.pdf`,
      "plan_pdf",
      bytesOf(
        `%PDF plan ${capture.captureId}`,
        capture.areaKey === "floor-1" ? options.planPdfBytes : undefined,
      ),
      capture,
    );
    add(
      `${dir}/spatial-report.pdf`,
      "spatial_report_pdf",
      bytesOf(`%PDF report ${capture.captureId}`),
      capture,
    );
    add(`${dir}/plan.png`, "plan_png", bytesOf(`PNG ${capture.captureId}`), capture);
    add(`${dir}/mesh.glb`, "mesh_glb", bytesOf(`glTF ${capture.captureId}`), capture);
    add(`${dir}/points.las`, "point_cloud_las", bytesOf(`LASF ${capture.captureId}`), capture);
    add(
      `Site Photos/${capture.areaKey}/${capture.captureId}/photo-0001.jpg`,
      "photo",
      bytesOf(`JPEG ${capture.captureId}`),
      capture,
    );
  }
  const manifestPath = `Source Register/${visitId}/manifest.json`;
  const manifestBytes = bytesOf(
    `${JSON.stringify({ packageId, visitId, files: records.map((r) => r.path) }, null, 2)}\n`,
  );
  const pkg: PublishPackage = {
    packageId,
    dealId,
    visitId,
    revision: 1,
    manifestPath,
    manifestSha256: sha256(manifestBytes),
    manifestBytes: manifestBytes.byteLength,
    files: records,
  };
  const verdict: Verdict = {
    ...LIMITED_EXAMPLE,
    verdictId: randomUUID(),
    packageId,
    visitId,
    revision: 1,
    ...options.verdict,
  };
  const captureRecord: CaptureRecord = {
    schemaVersion: "1.0.0",
    visitId,
    hub: { dealId, projectName: "Fixture project" },
    address: {
      formatted: "100 Example Street, Testville, NY 00000",
      confirmedOnSite: true,
      confirmedAt: "2026-10-17T13:58:20Z",
    },
    operator: { name: "Test Operator" },
    device: {
      model: "iPhone17,1",
      marketingName: "iPhone 16 Pro",
      osName: "iOS",
      osVersion: "26.0.1",
      hasLidar: true,
    },
    app: { version: "1.0.0", build: "test" },
    visitedAt: "2026-10-17T13:55:00Z",
    captures: captures.map((capture) => ({
      captureId: capture.captureId,
      areaKey: capture.areaKey,
      label: capture.label,
      mode: "floor" as const,
      units: { length: "m" as const, display: "metric" as const },
      capturedAt: "2026-10-17T14:02:11Z",
      coverageNotes: "",
      omittedRooms: [],
      inaccessibleRooms: [],
    })) as unknown as CaptureRecord["captures"],
  };
  const reads: string[] = [];
  return {
    pkg,
    verdict,
    captureRecord,
    files,
    manifestBytes,
    reads,
    request: (overrides = {}) => ({
      pkg,
      verdict,
      captureRecord,
      readManifest: async () => manifestBytes,
      readFile: async (path: string) => {
        reads.push(path);
        const data = files.get(path);
        if (data === undefined) {
          throw new Error(`no file ${path}`);
        }
        return data;
      },
      ...overrides,
    }),
    expectedUploads: () => {
      const visit = `Capture/${visitId}/r1`;
      const out = [
        { folder: visit, name: `verdict-report-${verdict.verdictId}.pdf` },
        { folder: visit, name: "manifest.json" },
      ];
      for (const record of records) {
        if (
          ["plan_dxf", "rooms_csv", "plan_pdf", "spatial_report_pdf", "plan_png"].includes(
            record.role,
          ) &&
          record.bytes <= 45 * MIB
        ) {
          out.push({
            folder: `Capture/${record.areaKey}/${record.captureId}/r1`,
            name: record.path.slice(record.path.lastIndexOf("/") + 1),
          });
        }
      }
      return out;
    },
  };
}

export interface Harness {
  readonly hub: FakeHub;
  readonly api: HubApi;
  readonly store: MemoryPublicationStore;
  readonly publisher: HubPublisher;
  readonly sleeps: number[];
}

/** Publisher over the in-process fake HUB, without real sleeping or jitter. */
export function harness(
  options: { hub?: FakeHub; api?: HubApi } & Partial<Omit<HubPublisherOptions, "hub">> = {},
): Harness {
  const { hub: fakeHub, api: customApi, store: customStore, ...rest } = options;
  const fake = createFakeHubApi(fakeHub ?? new FakeHub());
  const api = customApi ?? fake.api;
  const store =
    customStore instanceof MemoryPublicationStore ? customStore : new MemoryPublicationStore();
  const sleeps: number[] = [];
  const publisher = new HubPublisher({
    hub: api,
    store,
    reviewBaseUrl: REVIEW_BASE_URL,
    jitter: false,
    sleep: async (ms) => {
      sleeps.push(ms);
    },
    ...rest,
  });
  return { hub: fake.hub, api, store, publisher, sleeps };
}

/** (folder, name) pairs of the documents stored in the fake HUB. */
export function storedPairs(hub: FakeHub): Array<{ folder: string; name: string }> {
  return hub.documents.map((doc) => ({ folder: doc.folder, name: doc.name }));
}

export function sortPairs(pairs: Array<{ folder: string; name: string }>): string[] {
  return pairs.map((pair) => `${pair.folder}/${pair.name}`).sort();
}

/** All text of a PDF (every page). */
export async function pdfText(data: Uint8Array): Promise<string> {
  const pdf = await getDocumentProxy(new Uint8Array(data));
  const { text } = await extractText(pdf, { mergePages: true });
  return text;
}

/** Text without any whitespace, for comparisons that ignore line wrapping. */
export function squash(text: string): string {
  return text.replace(/\s+/g, "");
}
