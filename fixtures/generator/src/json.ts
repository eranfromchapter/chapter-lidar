// Prettier-formatted JSON bytes, so committed generated JSON passes `npm run format:check`.
// The Prettier config is resolved from the repository root, never from the output folder, so a
// temporary output folder gives the same bytes as the committed one.

import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as prettier from "prettier";
import { utf8 } from "./util.js";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

let optionsPromise: Promise<prettier.Options> | undefined;

function options(): Promise<prettier.Options> {
  optionsPromise ??= prettier
    .resolveConfig(join(repoRoot, "fixtures", "generated", "x.json"))
    .then((config) => ({ ...(config ?? {}), parser: "json" }));
  return optionsPromise;
}

/** Formats a JSON value as Prettier would format a .json file. */
export async function jsonBytes(value: unknown): Promise<Uint8Array> {
  return utf8(await prettier.format(JSON.stringify(value), await options()));
}
