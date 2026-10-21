// web-review §9.3 / addendum D6: optional HUB and intake guide links from the server
// environment: https only, templates with their placeholders, values URL-encoded, invalid
// values ignored with one warning naming the variable, never the value.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  hubAppUrl,
  hubFilesUrl,
  intakeGuideUrl,
  resetLinkWarnings,
  safeExternalLink,
} from "@/lib/links";

let warn: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  resetLinkWarnings();
  warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
});

afterEach(() => {
  warn.mockRestore();
});

describe("plain links", () => {
  it("are null when unset or blank", () => {
    expect(hubAppUrl({})).toBeNull();
    expect(intakeGuideUrl({ INTAKE_GUIDE_URL: "  " })).toBeNull();
    expect(warn).not.toHaveBeenCalled();
  });

  it("accept https only and warn once per variable without the value", () => {
    expect(hubAppUrl({ HUB_APP_URL: "https://hub.example" })).toBe("https://hub.example/");
    expect(hubAppUrl({ HUB_APP_URL: "http://hub.example" })).toBeNull();
    expect(hubAppUrl({ HUB_APP_URL: "javascript:alert(1)" })).toBeNull();
    expect(warn).toHaveBeenCalledTimes(1);
    expect(String(warn.mock.calls[0]?.[0])).toContain("HUB_APP_URL");
    expect(String(warn.mock.calls[0]?.[0])).not.toContain("hub.example");
    expect(intakeGuideUrl({ INTAKE_GUIDE_URL: "not a url" })).toBeNull();
    expect(warn).toHaveBeenCalledTimes(2);
  });
});

describe("HUB files template", () => {
  const env = {
    HUB_FILES_URL_TEMPLATE: "https://hub.example/deals/{dealId}/files?folder={folder}",
  };

  it("fills in the deal and the folder, URL-encoded", () => {
    expect(hubFilesUrl("4417203", "Capture/b8dbc48a/r1", env)).toBe(
      "https://hub.example/deals/4417203/files?folder=Capture%2Fb8dbc48a%2Fr1",
    );
    expect(hubFilesUrl("a/b c", "x", env)).toBe(
      "https://hub.example/deals/a%2Fb%20c/files?folder=x",
    );
  });

  it("is ignored without both placeholders or when not https", () => {
    expect(
      hubFilesUrl("1", "f", { HUB_FILES_URL_TEMPLATE: "https://hub.example/deals" }),
    ).toBeNull();
    expect(
      hubFilesUrl("1", "f", { HUB_FILES_URL_TEMPLATE: "http://hub.example/{dealId}/{folder}" }),
    ).toBeNull();
    expect(hubFilesUrl("1", "f", {})).toBeNull();
    // One warning per variable, however often it is read.
    expect(warn).toHaveBeenCalledTimes(1);
    expect(String(warn.mock.calls[0]?.[0])).toContain("HUB_FILES_URL_TEMPLATE");
  });
});

describe("station links", () => {
  it("follow the station's HUB deal link only when it is https", () => {
    expect(safeExternalLink("https://hub.example/deals/1")).toBe("https://hub.example/deals/1");
    expect(safeExternalLink("http://hub.example/deals/1")).toBeNull();
    expect(safeExternalLink(undefined)).toBeNull();
  });
});
