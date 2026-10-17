import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { FastifyRequest } from "fastify";
import { audit, writeAudit } from "../../src/core/audit.js";
import type { Principal } from "../../src/core/auth.js";
import { USER_OID, fakeDatabase } from "./helpers.js";

const principal: Principal = {
  kind: "user",
  userId: USER_OID,
  name: "Dana Field",
  tenantId: "t",
  roles: ["capture"],
};

function fakeRequest(db = fakeDatabase(), who: Principal | null = principal) {
  return {
    db,
    request: { principal: who, id: "req-1", server: { db } } as unknown as FastifyRequest,
  };
}

describe("audit", () => {
  it("writes who, what, which target and the request id", async () => {
    const { db, request } = fakeRequest();
    const id = await audit(
      request,
      "package.create",
      { type: "package", id: "p-1" },
      { revision: 1 },
    );
    assert.equal(id, 1);
    assert.equal(db.queries.length, 1);
    const [query] = db.queries;
    assert.match(query?.text ?? "", /INSERT INTO audit_log/);
    assert.deepEqual(query?.values, [
      "user",
      USER_OID,
      "Dana Field",
      ["capture"],
      "package.create",
      "package",
      "p-1",
      JSON.stringify({ revision: 1 }),
      "req-1",
    ]);
  });

  it("uses the transaction executor when one is given", async () => {
    const pool = fakeDatabase();
    const tx = fakeDatabase();
    const { request } = fakeRequest(pool);
    await audit(request, "file.verify", { type: "package_file", id: "p-1/a.dxf" }, {}, tx);
    assert.equal(pool.queries.length, 0);
    assert.equal(tx.queries.length, 1);
  });

  it("strips secrets from details", async () => {
    const { db, request } = fakeRequest();
    await audit(
      request,
      "upload_session.create",
      { type: "package", id: "p-1" },
      {
        files: [
          { path: "a.las", url: "https://acct.blob.core.windows.net/o/a.las?sv=1&sig=SECRET" },
        ],
        sasToken: "sv=1&sig=SECRET",
      },
    );
    const details = String(db.queries[0]?.values[7]);
    assert.ok(!details.includes("SECRET"), details);
    assert.match(details, /\[redacted\]/);
  });

  it("refuses requests without a principal and invalid names", async () => {
    const { request } = fakeRequest(fakeDatabase(), null);
    await assert.rejects(audit(request, "package.create", { type: "package" }), /principal/);
    const db = fakeDatabase();
    const actor = { type: "user" as const, id: USER_OID };
    await assert.rejects(writeAudit(db, { actor, action: "Create", target: { type: "package" } }));
    await assert.rejects(writeAudit(db, { actor, action: "package", target: { type: "package" } }));
    await assert.rejects(
      writeAudit(db, { actor, action: "package.create", target: { type: "Package" } }),
    );
    await assert.rejects(
      writeAudit(db, { actor: { type: "user" }, action: "package.create", target: { type: "p" } }),
    );
    assert.equal(db.queries.length, 0);
  });

  it("allows system actors without an id", async () => {
    const db = fakeDatabase();
    await writeAudit(db, {
      actor: { type: "system", name: "station-worker" },
      action: "job.retry",
      target: { type: "job", id: "j-1" },
    });
    assert.equal(db.queries[0]?.values[0], "system");
    assert.equal(db.queries[0]?.values[1], null);
  });
});
