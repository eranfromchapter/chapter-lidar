// The footer QR code (spec 11.1 qr.test.ts): its modules, drawn to a PNG, decode to the review
// URL; the same URL gives the same modules.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import jsqrModule from "jsqr";
import { PNG } from "pngjs";
import { qrModules } from "../../src/report/layout/page.js";

// jsqr is CommonJS with a default export: the function is `default` under Node's interop and the
// import itself under tsx's.
type Decode = typeof jsqrModule.default;
const jsQR: Decode =
  (jsqrModule as unknown as { default?: Decode }).default ?? (jsqrModule as unknown as Decode);

const URL_424 = "https://review.capture.example.test/packages/b8dbc48a-f67f-4fd1-9859-7cfc2edaad7e";

/** The modules as a PNG (4 px per module, 4-module quiet zone), then read back. */
function rendered(url: string): { data: Uint8ClampedArray; width: number; height: number } {
  const { size, dark } = qrModules(url);
  const scale = 4;
  const quiet = 4;
  const side = (size + quiet * 2) * scale;
  const png = new PNG({ width: side, height: side });
  for (let y = 0; y < side; y += 1) {
    for (let x = 0; x < side; x += 1) {
      const row = Math.floor(y / scale) - quiet;
      const col = Math.floor(x / scale) - quiet;
      const ink = row >= 0 && col >= 0 && row < size && col < size && dark(row, col);
      const at = (y * side + x) * 4;
      png.data[at] = png.data[at + 1] = png.data[at + 2] = ink ? 0x1f : 0xfa;
      png.data[at + 3] = 255;
    }
  }
  const back = PNG.sync.read(PNG.sync.write(png));
  return { data: new Uint8ClampedArray(back.data), width: back.width, height: back.height };
}

const matrix = (url: string) => {
  const { size, dark } = qrModules(url);
  return Array.from({ length: size }, (_, row) =>
    Array.from({ length: size }, (_, col) => (dark(row, col) ? 1 : 0)).join(""),
  );
};

describe("review link QR code", () => {
  it("decodes to the package's review URL", () => {
    const image = rendered(URL_424);
    const code = jsQR(image.data, image.width, image.height);
    assert.equal(code?.data, URL_424);
  });

  it("is the smallest code for the URL (error correction L)", () => {
    // 84 bytes: version 5 (37 modules) with error correction L, about 0.8 pt per module at 30 pt;
    // M would need version 6 (41 modules).
    assert.equal(qrModules(URL_424).size, 37);
  });

  it("gives the same modules for the same URL", () => {
    assert.deepEqual(matrix(URL_424), matrix(`${URL_424}`));
    assert.notDeepEqual(matrix(URL_424), matrix(`${URL_424.slice(0, -1)}0`));
  });
});
