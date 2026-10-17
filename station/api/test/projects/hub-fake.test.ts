// The fake HubClient and the shared "confirmed address only" rule.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  FAKE_HUB_DEALS,
  FIXTURE_DEAL_ADDRESS,
  FIXTURE_DEAL_ID,
  FakeHubClient,
} from "../../src/hub/fake.js";
import { normalizeDeal, normalizeDeals, type RawHubDeal } from "../../src/hub/normalize.js";

function raw(overrides: Partial<RawHubDeal> = {}): RawHubDeal {
  return {
    dealId: "deal-1",
    projectName: "Kitchen",
    address: "1 Main Street, New York, NY 10001",
    addressConfirmed: true,
    updatedAt: "2026-10-01T00:00:00Z",
    ...overrides,
  };
}

describe("FakeHubClient", () => {
  it("returns the fixture deal with its exact address", async () => {
    const hub = new FakeHubClient();
    const project = await hub.getProject(FIXTURE_DEAL_ID);
    assert.ok(project);
    assert.equal(project.dealId, "fixture-deal-0001");
    assert.equal(project.address.formatted, "100 Example Street, Testville, NY 00000");
    assert.equal(FIXTURE_DEAL_ADDRESS, "100 Example Street, Testville, NY 00000");
  });

  it("never returns the deal without a confirmed address", async () => {
    const unconfirmed = FAKE_HUB_DEALS.filter((deal) => deal.addressConfirmed !== true);
    assert.equal(unconfirmed.length, 1, "the fake must hold one deal without a confirmed address");
    const hub = new FakeHubClient();
    const listed = await hub.listProjects();
    assert.deepEqual(
      listed.map((project) => project.dealId),
      ["fixture-deal-0001", "fixture-deal-0002"],
    );
    assert.equal(await hub.getProject(String(unconfirmed[0]?.dealId)), null);
  });

  it("is deterministic", async () => {
    assert.deepEqual(
      await new FakeHubClient().listProjects(),
      await new FakeHubClient().listProjects(),
    );
  });

  it("answers null for an unknown deal", async () => {
    assert.equal(await new FakeHubClient().getProject("no-such-deal"), null);
  });
});

describe("normalizeDeal", () => {
  it("accepts a deal with a confirmed single-line address", () => {
    assert.deepEqual(normalizeDeal(raw()), {
      ok: true,
      project: {
        dealId: "deal-1",
        projectName: "Kitchen",
        address: { formatted: "1 Main Street, New York, NY 10001" },
        updatedAtMs: Date.UTC(2026, 9, 1),
      },
    });
  });

  it("keeps the address exactly as the HUB shows it", () => {
    const result = normalizeDeal(raw({ address: "  12 Example Lane,  Apt 3 " }));
    assert.ok(result.ok);
    assert.equal(result.project.address.formatted, "  12 Example Lane,  Apt 3 ");
  });

  const rejected: [string, Partial<RawHubDeal>, string][] = [
    ["confirmation false", { addressConfirmed: false }, "address_not_confirmed"],
    ["confirmation as a string", { addressConfirmed: "true" }, "address_not_confirmed"],
    ["no confirmation field", { addressConfirmed: undefined }, "confirmation_missing"],
    ["null confirmation", { addressConfirmed: null }, "confirmation_missing"],
    ["no address", { address: undefined }, "invalid_address"],
    ["a blank address", { address: "   " }, "invalid_address"],
    ["a multi-line address", { address: "1 Main St\nNew York" }, "invalid_address"],
    ["an address object", { address: { street: "1 Main St" } }, "invalid_address"],
    ["a too long address", { address: "x".repeat(301) }, "invalid_address"],
    ["no dealId", { dealId: undefined }, "invalid_deal_id"],
    ["an empty dealId", { dealId: "" }, "invalid_deal_id"],
    ["a too long dealId", { dealId: "d".repeat(65) }, "invalid_deal_id"],
    ["a fractional dealId", { dealId: 1.5 }, "invalid_deal_id"],
  ];
  for (const [label, overrides, reason] of rejected) {
    it(`skips a deal with ${label}`, () => {
      assert.deepEqual(normalizeDeal(raw(overrides)), { ok: false, reason });
    });
  }

  it("turns a numeric dealId into a string and omits a blank name", () => {
    const result = normalizeDeal(raw({ dealId: 4452, projectName: "  " }));
    assert.ok(result.ok);
    assert.equal(result.project.dealId, "4452");
    assert.equal("projectName" in result.project, false);
  });

  it("cuts a long project name to 200 characters", () => {
    const result = normalizeDeal(raw({ projectName: "n".repeat(250) }));
    assert.ok(result.ok);
    assert.equal(result.project.projectName?.length, 200);
  });
});

describe("normalizeDeals", () => {
  it("orders most recently updated first, undated last, and drops duplicates", () => {
    const result = normalizeDeals([
      raw({ dealId: "old", updatedAt: "2026-01-01T00:00:00Z" }),
      raw({ dealId: "undated-a", updatedAt: undefined }),
      raw({ dealId: "new", updatedAt: "2026-10-01T00:00:00Z" }),
      raw({ dealId: "undated-b", updatedAt: "not a date" }),
      raw({ dealId: "new", updatedAt: "2026-10-02T00:00:00Z", address: "Other" }),
      raw({ dealId: "pending", addressConfirmed: false }),
    ]);
    assert.deepEqual(
      result.projects.map((project) => project.dealId),
      ["new", "old", "undated-a", "undated-b"],
    );
    assert.equal(result.duplicates, 1);
    assert.deepEqual(result.skipped, { address_not_confirmed: 1 });
  });
});
