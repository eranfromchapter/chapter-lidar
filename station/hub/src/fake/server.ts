// The fake HUB over HTTP on a loopback port, for tests and the end-to-end run (the worker in
// HUB_MODE=live pointed at it). Bodies over the upload cap are refused with 413 before they are
// read to the end.

import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { FakeHub, MULTIPART_OVERHEAD_BYTES, type FakeHubOptions } from "./hub.js";

export interface FakeHubServer {
  /** Base URL, for example http://127.0.0.1:41234 (HUB_BASE_URL). */
  readonly url: string;
  readonly hub: FakeHub;
  close(): Promise<void>;
}

async function send(res: ServerResponse, response: Response): Promise<void> {
  const body = Buffer.from(await response.arrayBuffer());
  res.statusCode = response.status;
  response.headers.forEach((value, key) => res.setHeader(key, value));
  res.setHeader("content-length", body.byteLength);
  res.end(body);
}

function readBody(req: IncomingMessage, limit: number): Promise<Buffer | "too_large"> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let total = 0;
    let over = false;
    req.on("data", (chunk: Buffer) => {
      if (over) {
        return;
      }
      total += chunk.byteLength;
      if (total > limit) {
        over = true;
        chunks.length = 0;
        resolve("too_large");
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (!over) {
        resolve(Buffer.concat(chunks));
      }
    });
    req.on("error", reject);
  });
}

/** Starts the fake HUB on 127.0.0.1 (random port unless given). */
export async function startFakeHubServer(
  options: FakeHubOptions & { readonly hub?: FakeHub; readonly port?: number } = {},
): Promise<FakeHubServer> {
  const hub = options.hub ?? new FakeHub(options);
  const limit = hub.maxUploadBytes + MULTIPART_OVERHEAD_BYTES;

  const server = createServer((req, res) => {
    void (async () => {
      const method = (req.method ?? "GET").toUpperCase();
      const url = new URL(req.url ?? "/", "http://127.0.0.1");
      const declared = Number(req.headers["content-length"] ?? "0");
      if (Number.isFinite(declared) && declared > limit) {
        res.setHeader("connection", "close");
        await send(res, hub.tooLarge(method, url.pathname));
        req.destroy();
        return;
      }
      const body =
        method === "GET" || method === "HEAD" ? Buffer.alloc(0) : await readBody(req, limit);
      if (body === "too_large") {
        res.setHeader("connection", "close");
        await send(res, hub.tooLarge(method, url.pathname));
        req.destroy();
        return;
      }
      const headers = new Headers();
      for (const [key, value] of Object.entries(req.headers)) {
        if (typeof value === "string") {
          headers.set(key, value);
        } else if (Array.isArray(value)) {
          headers.set(key, value.join(", "));
        }
      }
      const request = new Request(url, {
        method,
        headers,
        ...(body.byteLength > 0 ? { body } : {}),
      });
      await send(res, await hub.handle(request));
    })().catch(() => {
      if (!res.headersSent) {
        res.statusCode = 500;
      }
      res.end();
    });
  });

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(options.port ?? 0, "127.0.0.1", () => resolve());
  });
  const { port } = server.address() as AddressInfo;
  return {
    url: `http://127.0.0.1:${port}`,
    hub,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.closeAllConnections();
        server.close((error) => (error ? reject(error) : resolve()));
      }),
  };
}
