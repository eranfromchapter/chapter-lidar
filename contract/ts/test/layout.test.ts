// Layout constants, role enum and visit-role list agree with contract/schema.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { LAYOUT, ROLES, SCHEMAS, VISIT_ROLES, isVisitRole } from "../src/index.js";
import { layoutPath, schemaDir } from "../src/node.js";
import { readJson } from "./paths.js";

interface Defs {
  $defs: Record<string, { enum?: string[] }>;
  properties: { layoutVersion: { const: string } };
}

const manifest = SCHEMAS.manifest as unknown as Defs;

describe("layout and roles", () => {
  it("LAYOUT equals contract/schema/layout.json", () => {
    assert.deepEqual(LAYOUT, readJson(layoutPath));
  });

  it("schemaDir points at contract/schema", () => {
    assert.ok(schemaDir.replaceAll("\\", "/").endsWith("/contract/schema/"));
  });

  it("ROLES equals manifest $defs/role", () => {
    assert.deepEqual([...ROLES], manifest.$defs["role"]?.enum);
  });

  it("VISIT_ROLES equals manifest $defs/visitRole", () => {
    assert.deepEqual([...VISIT_ROLES], manifest.$defs["visitRole"]?.enum);
  });

  it("manifest $defs/visitRole equals the roles of layout folders with scope visit", () => {
    const visitFolderRoles = LAYOUT.folders
      .filter((folder) => folder.scope === "visit")
      .flatMap((folder) => [...folder.roles] as string[])
      .sort();
    assert.deepEqual([...(manifest.$defs["visitRole"]?.enum ?? [])].sort(), visitFolderRoles);
  });

  it("every role belongs to exactly one layout folder and every folder role is a role", () => {
    const folderRoles = LAYOUT.folders.flatMap((folder) => [...folder.roles] as string[]);
    assert.equal(new Set(folderRoles).size, folderRoles.length, "a role is in two folders");
    assert.deepEqual([...folderRoles].sort(), [...ROLES].sort());
  });

  it("manifest layoutVersion matches layout.json", () => {
    assert.equal(manifest.properties.layoutVersion.const, LAYOUT.layoutVersion);
  });

  it("isVisitRole is true exactly for visit roles", () => {
    for (const role of ROLES) {
      assert.equal(isVisitRole(role), (VISIT_ROLES as readonly string[]).includes(role), role);
    }
  });
});
