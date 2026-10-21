// The station and blob store of the end-to-end tests (web-review §12.4): an HTTP server that
// answers the station API (/v1, the fake station of the component tests over HTTP) from the
// drawn scenario, serves the fixture files behind the short-lived links it hands out (/blob),
// and lets the tests switch scenarios (/__control). Local test data only; no network.
//
//   node --import tsx e2e/mock-station.ts      (TSX_TSCONFIG_PATH=e2e/tsconfig.json)

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createFakeStation, type FakeStation } from "../test/support/fake-station";
import { loadFixture } from "../test/support/fixtures";
import { drawnScenario, emptyScenario, statesScenario } from "../test/support/scenarios";

const PORT = Number(process.env.E2E_STATION_PORT ?? "3917");
const BASE = `http://127.0.0.1:${PORT}`;

/** Fixture packages the scenarios use, for the bytes behind download links. */
const FIXTURE_ROOTS = [
  "sample-424/package",
  "two-floor-house/package",
  "two-room-apartment/package",
  "broken/wrong-address/package",
  "box-room/package",
  "l-shaped-room/package",
  "legacy-1.0.0/package",
];

const blobs = new Map<string, Uint8Array>();
for (const root of FIXTURE_ROOTS) {
  for (const [path, bytes] of loadFixture(root).files) {
    if (!blobs.has(path)) {
      blobs.set(path, bytes);
    }
  }
}

/** A one-page placeholder standing in for the station's spatial report PDF. */
const REPORT_PDF = new TextEncoder().encode(
  "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n",
);

type ScenarioName = "drawn" | "empty" | "states";

function build(name: ScenarioName, reportReady: boolean): FakeStation {
  const now = new Date();
  const data =
    name === "empty"
      ? emptyScenario()
      : name === "states"
        ? statesScenario(now)
        : drawnScenario(now, { reportReady });
  // The review screen sends the signed-in user's station token; this station takes any.
  return createFakeStation(data, { blobBase: `${BASE}/blob`, acceptAnyToken: true });
}

let station = build("drawn", false);

async function body(request: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of request) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function send(
  response: ServerResponse,
  status: number,
  content: string | Uint8Array,
  type = "text/plain; charset=utf-8",
): void {
  response.writeHead(status, { "content-type": type, "cache-control": "no-store" });
  response.end(content);
}

const server = createServer((request, response) => {
  void (async () => {
    const url = new URL(request.url ?? "/", BASE);
    if (url.pathname === "/health") {
      send(response, 200, "ok");
      return;
    }
    if (url.pathname === "/__control" && request.method === "POST") {
      const control = JSON.parse((await body(request)) || "{}") as {
        scenario?: ScenarioName;
        reportReady?: boolean;
        failWith?: number;
      };
      station = build(control.scenario ?? "drawn", control.reportReady === true);
      if (control.failWith !== undefined) {
        station.failWith = control.failWith;
      }
      send(response, 200, "ok");
      return;
    }
    if (url.pathname === "/__calls") {
      send(
        response,
        200,
        JSON.stringify(station.calls.map(({ method, path, status }) => ({ method, path, status }))),
        "application/json",
      );
      return;
    }
    if (url.pathname.startsWith("/blob/originals/")) {
      const path = decodeURIComponent(url.pathname.slice("/blob/originals/".length));
      const bytes = blobs.get(path);
      if (bytes === undefined) {
        send(response, 404, "No such blob.");
        return;
      }
      const type = path.endsWith(".png")
        ? "image/png"
        : path.endsWith(".json")
          ? "application/json"
          : "application/octet-stream";
      send(response, 200, bytes, type);
      return;
    }
    if (url.pathname.startsWith("/blob/reports/")) {
      send(response, 200, REPORT_PDF, "application/pdf");
      return;
    }
    if (url.pathname.startsWith("/v1/")) {
      const text = request.method === "POST" ? await body(request) : undefined;
      const answer = await station.fetch(url, {
        method: request.method ?? "GET",
        headers: Object.fromEntries(
          Object.entries(request.headers).filter(
            (entry): entry is [string, string] => typeof entry[1] === "string",
          ),
        ),
        ...(text === undefined ? {} : { body: text }),
      });
      send(
        response,
        answer.status,
        new Uint8Array(await answer.arrayBuffer()),
        answer.headers.get("content-type") ?? "application/json",
      );
      return;
    }
    send(response, 404, "Unknown path.");
  })().catch((error: unknown) => {
    console.error("[mock-station]", error);
    send(response, 500, "Mock station error.");
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[mock-station] listening on ${BASE}`);
});
