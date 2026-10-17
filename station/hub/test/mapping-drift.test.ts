// Drift guard: the HUB deal lookup and the auth header of station-hub must stay identical to the
// station API's (station/api/src/hub/mapping.ts). Both are NOT CONFIRMED with the HUB team; when
// one side changes, this test makes the other change too.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HUB_API_MAPPING } from "../../api/src/hub/mapping.js";
import { HUB_PUBLISH_MAPPING } from "../src/mapping.js";

describe("HUB mapping drift guard", () => {
  it("uses the station API's deal lookup path and envelope", () => {
    assert.equal(HUB_PUBLISH_MAPPING.listDeals.path, HUB_API_MAPPING.listDeals.path);
    assert.equal(HUB_PUBLISH_MAPPING.listDeals.itemsPath, HUB_API_MAPPING.listDeals.itemsPath);
  });

  it("uses the station API's deal field names", () => {
    assert.deepEqual({ ...HUB_PUBLISH_MAPPING.dealFields }, { ...HUB_API_MAPPING.fields });
  });

  it("uses the station API's auth header and scheme", () => {
    assert.equal(HUB_PUBLISH_MAPPING.auth.header, HUB_API_MAPPING.auth.header);
    assert.equal(HUB_PUBLISH_MAPPING.auth.scheme, HUB_API_MAPPING.auth.scheme);
  });

  it("uploads through the spec's route and multipart field", () => {
    assert.equal(HUB_PUBLISH_MAPPING.upload.path, "/api/projects/{dealId}/document-media/upload");
    assert.equal(HUB_PUBLISH_MAPPING.upload.fileField, "files");
  });
});
