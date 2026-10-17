// F11 AC5 support: the PII scan script finds emails, phone numbers and street addresses, allows
// the documented placeholder addresses, and the committed fixtures are clean.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { repoRoot } from "../src/json.js";
import { generatorDir } from "./helpers.js";

const script = join(generatorDir, "scripts", "scan-pii.mjs");

function scan(dir: string, cwd = repoRoot): { status: number | null; output: string } {
  const result = spawnSync(process.execPath, [script, dir], { cwd, encoding: "utf8" });
  return { status: result.status, output: `${result.stdout}${result.stderr}` };
}

// Offending strings are assembled at run time so that this file itself stays clean.
const email = ["jane.doe", "mail.example"].join("@") + ".com";
const phone = ["(212)", " 555-", "0143"].join("");
const phonePlain = ["646", "555", "0187"].join("-");
const street = ["24", "Maple", "Street"].join(" ");
const street2 = ["1500", "Bay", "Road"].join(" ");

describe("scan-pii.mjs", () => {
  it("passes on the committed fixtures (the AC5 command)", () => {
    const result = scan("fixtures");
    assert.equal(result.status, 0, result.output);
    assert.match(result.output, /0 hit\(s\)/);
  });

  it("exits non-zero and prints each offender", () => {
    const dir = mkdtempSync(join(tmpdir(), "chapter-pii-"));
    try {
      mkdirSync(join(dir, "nested"));
      writeFileSync(join(dir, "a.json"), JSON.stringify({ contact: email }));
      writeFileSync(join(dir, "nested", "b.txt"), `call ${phone} or ${phonePlain}\n`);
      writeFileSync(join(dir, "nested", "c.csv"), `site,${street}, Testville\n${street2}\n`);
      const result = scan(dir);
      assert.equal(result.status, 1);
      for (const needle of [email, phone, phonePlain, street, street2]) {
        assert.ok(result.output.includes(needle), `reports ${needle}`);
      }
      assert.match(result.output, /email/);
      assert.match(result.output, /phone/);
      assert.match(result.output, /street address/);
      assert.match(result.output, /5 hit\(s\)/);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("allows the two documented placeholder addresses and nothing similar", () => {
    const dir = mkdtempSync(join(tmpdir(), "chapter-pii-"));
    try {
      writeFileSync(
        join(dir, "ok.json"),
        '{"a":"100 Example Street, Testville, NY 00000","b":"200 Sample Avenue, Testville, NY 00000"}\n',
      );
      assert.equal(scan(dir).status, 0);
      writeFileSync(join(dir, "bad.json"), `{"a":"${street}, Testville, NY 00000"}\n`);
      const result = scan(dir);
      assert.equal(result.status, 1);
      assert.ok(result.output.includes(street));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("ignores binary files, node_modules and the numbers in plan files", () => {
    const dir = mkdtempSync(join(tmpdir(), "chapter-pii-"));
    try {
      writeFileSync(
        join(dir, "blob.bin"),
        Buffer.concat([Buffer.from([0, 1, 2]), Buffer.from(email)]),
      );
      mkdirSync(join(dir, "node_modules"));
      writeFileSync(join(dir, "node_modules", "x.txt"), email);
      writeFileSync(
        join(dir, "plan.dxf"),
        "  10\n4000.000\n  20\n-3000.000\n  30\n0.0\nv 1.000000 2.700000 3.000000\n",
      );
      assert.equal(scan(dir).status, 0);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("reads a pii-allowlist.txt at the scanned root", () => {
    const dir = mkdtempSync(join(tmpdir(), "chapter-pii-"));
    try {
      writeFileSync(join(dir, "x.txt"), `${street}\n`);
      assert.equal(scan(dir).status, 1);
      writeFileSync(join(dir, "pii-allowlist.txt"), `# reviewed\n${street}\n`);
      assert.equal(scan(dir).status, 0);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
