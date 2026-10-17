import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { REDACTED, isSecretKey, redactSecrets, redactString } from "../../src/core/redact.js";
import { toApiDateTime } from "../../src/core/time.js";

const JWT =
  "eyJhbGciOiJSUzI1NiIsImtpZCI6IjEifQ.eyJzdWIiOiIxMjM0NTY3ODkwIiwicm9sZXMiOlsiYmltIl19.c2lnbmF0dXJlLWJ5dGVz";

describe("redactSecrets", () => {
  it("redacts values under secret-looking keys at any depth", () => {
    const out = redactSecrets({
      token: "abc",
      accessToken: "abc",
      nested: { password: "p", client_secret: "s", apiKey: "k", AccountKey: "a" },
      list: [{ authorization: "Bearer x" }, { connectionString: "Server=x" }],
      sasUrl: "https://acct.blob.core.windows.net/originals/a?sv=1&sig=abc",
    }) as Record<string, unknown>;
    assert.deepEqual(out, {
      token: REDACTED,
      accessToken: REDACTED,
      nested: {
        password: REDACTED,
        client_secret: REDACTED,
        apiKey: REDACTED,
        AccountKey: REDACTED,
      },
      list: [{ authorization: REDACTED }, { connectionString: REDACTED }],
      sasUrl: REDACTED,
    });
  });

  it("keeps ordinary contract fields", () => {
    const value = {
      packageId: "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b",
      areaKey: "floor-1",
      sha256: "a".repeat(64),
      bytes: 12,
      path: "Original Exports/floor-1/plan.dxf",
      ruleId: "floors.registration.landmarks_shared",
      revision: 2,
      sealed: true,
      note: null,
    };
    assert.deepEqual(redactSecrets(value), value);
    assert.equal(isSecretKey("areaKey"), false);
    assert.equal(isSecretKey("sha256"), false);
  });

  it("strips the query of SAS and token URLs, wherever they appear", () => {
    assert.equal(
      redactString("https://acct.blob.core.windows.net/originals/p/a.las?sv=2024&se=x&sig=AbC%3D"),
      `https://acct.blob.core.windows.net/originals/p/a.las?${REDACTED}`,
    );
    assert.equal(redactString("https://example.com/cb#access_token=xyz"), "https://example.com/cb");
    assert.equal(
      redactString("https://hub.example.com/api/projects/123?page=2"),
      "https://hub.example.com/api/projects/123?page=2",
    );
    assert.equal(
      // Fake credentials, assembled at runtime so secret scanners do not flag the test.
      redactString(["postgres://station", "hunter2@db:5432/station"].join(":")),
      "postgres://db:5432/station",
    );
  });

  it("redacts JWTs, bearer strings and connection string keys inside text", () => {
    assert.equal(redactString(JWT), REDACTED);
    assert.equal(redactString(`token was ${JWT} ok`), `token was ${REDACTED} ok`);
    assert.equal(
      redactString("Authorization: Bearer abc.def"),
      `Authorization: Bearer ${REDACTED}`,
    );
    assert.equal(
      redactString(
        "DefaultEndpointsProtocol=https;AccountName=a;AccountKey=xyz==;EndpointSuffix=c",
      ),
      `DefaultEndpointsProtocol=https;AccountName=a;AccountKey=${REDACTED};EndpointSuffix=c`,
    );
  });

  it("serializes dates and errors without leaking messages", () => {
    const out = redactSecrets({
      at: new Date("2026-10-17T14:02:11.000Z"),
      error: new Error(`HUB said ${JWT}`),
    });
    assert.deepEqual(out, {
      at: "2026-10-17T14:02:11.000Z",
      error: { name: "Error", message: `HUB said ${REDACTED}` },
    });
  });
});

describe("toApiDateTime", () => {
  it("formats UTC with whole seconds", () => {
    assert.equal(toApiDateTime(new Date("2026-10-17T14:02:11.987Z")), "2026-10-17T14:02:11Z");
    assert.throws(() => toApiDateTime(new Date("nope")), RangeError);
  });
});
