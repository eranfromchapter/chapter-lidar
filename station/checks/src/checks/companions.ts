// Check 6: mesh companions (glTF buffers and images, OBJ material libraries, MTL textures)
// resolve by relative path to files listed in the manifest.

import type { FileEntry } from "@chapter/capture-contract";
import { resolveRelative, type CheckContext } from "../context.js";
import { NO_ACTION, finding, scopeOf } from "../finding.js";
import { decodeDataUri, type BufferSource, type GltfFile } from "../parsers/gltf.js";
import type { CheckOutput, StationFinding } from "../types.js";

/** Decodes a glTF uri (percent-encoded per RFC 3986). */
function decodeUri(uri: string): string {
  try {
    return decodeURIComponent(uri);
  } catch {
    return uri;
  }
}

/** Bytes of a companion referenced from `from`, when it is listed and present. */
function companionBytes(
  ctx: CheckContext,
  from: string,
  reference: string,
): Uint8Array | undefined {
  const path = resolveRelative(from, reference);
  if (path === undefined || !ctx.listed(path)) {
    return undefined;
  }
  return ctx.bytes(path);
}

/** Buffer source for a parsed glTF: BIN chunk, data: URI or a listed companion file. */
export function gltfBuffers(ctx: CheckContext, entry: FileEntry, gltf: GltfFile): BufferSource {
  return (index: number) => {
    const buffer = gltf.json.buffers?.[index];
    if (buffer === undefined) {
      return undefined;
    }
    if (buffer.uri === undefined) {
      return index === 0 && gltf.container === "glb" ? gltf.bin : undefined;
    }
    if (buffer.uri.startsWith("data:")) {
      return decodeDataUri(buffer.uri);
    }
    return companionBytes(ctx, entry.path, decodeUri(buffer.uri));
  };
}

export function checkCompanions(ctx: CheckContext): CheckOutput {
  const findings: StationFinding[] = [];
  const resolvedByCapture = new Map<string, string[]>();
  const note = (entry: FileEntry, text: string) => {
    const key = entry.captureId ?? "";
    resolvedByCapture.set(key, [...(resolvedByCapture.get(key) ?? []), text]);
  };
  let meshFiles = 0;

  for (const entry of ctx.entries) {
    const parsed = ctx.readable(entry);
    if (parsed === undefined) {
      continue;
    }
    const name = entry.path.split("/").pop() ?? entry.path;
    const base = { filePath: entry.path, ...scopeOf(entry) };

    if (parsed.kind === "gltf") {
      meshFiles += 1;
      const gltf = parsed.value;
      const buffers = gltf.json.buffers ?? [];
      const source = gltfBuffers(ctx, entry, gltf);
      buffers.forEach((buffer, index) => {
        const label =
          buffer.uri === undefined
            ? `buffer ${index} (embedded)`
            : `buffer ${index} "${buffer.uri}"`;
        const bytes = source(index);
        const needed = buffer.byteLength ?? 0;
        if (bytes === undefined) {
          const embedded = buffer.uri === undefined;
          const target = embedded
            ? undefined
            : resolveRelative(entry.path, decodeUri(buffer.uri as string));
          if (target !== undefined && ctx.listed(target) && ctx.bytes(target) === undefined) {
            return; // Listed but not uploaded: check 1 reports the missing file.
          }
          findings.push(
            finding({
              ruleId: "companions.resolve",
              severity: "blocker",
              message: embedded
                ? "GLB geometry buffer has no BIN chunk; the mesh has no geometry data."
                : "glTF geometry buffer does not resolve to a file in the package; the mesh cannot be opened.",
              ...base,
              measured: embedded
                ? `${label}: no BIN chunk`
                : `${label} -> ${target ?? "outside the package"}: not in the package`,
              expected: embedded
                ? "GLB with its BIN chunk"
                : "every buffer embedded or present next to the mesh under its original name",
              nextAction: `Re-export ${name} as a self-contained GLB (or include its buffer file unchanged) and re-upload.`,
            }),
          );
          return;
        }
        if (bytes.length < needed) {
          findings.push(
            finding({
              ruleId: "companions.resolve",
              severity: "blocker",
              message:
                "glTF geometry buffer is shorter than declared; the mesh data is incomplete.",
              ...base,
              measured: `${label}: ${bytes.length} bytes`,
              expected: `at least ${needed} bytes`,
              nextAction: `Re-export ${name} on the device and re-upload the package.`,
            }),
          );
          return;
        }
        note(entry, `${name} ${label}`);
      });
      for (const [index, image] of (gltf.json.images ?? []).entries()) {
        if (image.uri === undefined || image.uri.startsWith("data:")) {
          continue;
        }
        const target = resolveRelative(entry.path, decodeUri(image.uri));
        if (target !== undefined && ctx.listed(target)) {
          note(entry, `${name} image "${image.uri}"`);
          continue;
        }
        findings.push(
          finding({
            ruleId: "companions.resolve",
            severity: "limitation",
            message:
              "glTF texture image does not resolve to a file in the package; geometry is usable without it.",
            ...base,
            measured: `image ${index} "${image.uri}" -> ${target ?? "outside the package"}: not in the package`,
            expected: "every image embedded or present next to the mesh under its original name",
            nextAction: `Include the texture "${image.uri}" next to ${name} under its original name, or re-export a self-contained GLB.`,
          }),
        );
      }
      continue;
    }

    const references =
      parsed.kind === "obj"
        ? { list: parsed.value.mtllibs, what: "material library", kind: "OBJ" }
        : parsed.kind === "mtl"
          ? { list: parsed.value.textures, what: "texture", kind: "MTL" }
          : undefined;
    if (references === undefined) {
      continue;
    }
    meshFiles += 1;
    for (const reference of references.list) {
      const target = resolveRelative(entry.path, reference);
      if (target !== undefined && ctx.listed(target)) {
        note(entry, `${name} -> ${reference}`);
        continue;
      }
      findings.push(
        finding({
          ruleId: "companions.resolve",
          severity: "limitation",
          message: `${references.kind} ${references.what} does not resolve to a file in the package; geometry is usable without it.`,
          ...base,
          measured: `"${reference}" -> ${target ?? "outside the package"}: not in the package`,
          expected: "companions present under their original names and relative paths",
          nextAction: `Include "${reference}" next to ${name} under its original name and re-upload.`,
        }),
      );
    }
  }

  if (meshFiles === 0) {
    findings.push(
      finding({
        ruleId: "companions.resolve",
        severity: "info",
        message: "No GLB, glTF, OBJ or MTL file to check for companions.",
        filePath: ctx.manifestPath,
        measured: "0 mesh files",
        nextAction: NO_ACTION,
      }),
    );
    return { findings, notApplicable: true };
  }
  for (const capture of ctx.captures()) {
    const resolved = resolvedByCapture.get(capture.captureId);
    if (resolved === undefined) {
      continue;
    }
    const failed = findings.some((item) => item.captureId === capture.captureId);
    if (!failed) {
      findings.push(
        finding({
          ruleId: "companions.resolve",
          severity: "info",
          message: `Every mesh companion of ${capture.label} resolves by relative path.`,
          filePath: ctx.capturePath(capture.captureId),
          ...scopeOf(capture),
          measured: resolved.join("; "),
          expected: "companions resolve by relative path",
          nextAction: NO_ACTION,
        }),
      );
    }
  }
  return { findings };
}
