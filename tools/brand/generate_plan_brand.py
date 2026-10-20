#!/usr/bin/env python3
"""Writes ios/Packages/PlanExport/Sources/PlanExport/ChapterBrandAssets.swift: the Chapter logo
as vector paths and the Inter fonts (Regular and SemiBold, cut down to the WinAnsi characters)
that the floor plan, plan and report PDFs embed.

    python3 -I tools/brand/generate_plan_brand.py \
        --logo tools/brand/chapter-logo.svg \
        --inter "<path to>/Inter-VariableFont_slnt,wght.ttf"

The logo is the one on hellochapter.com (/images/icons/new-logo.svg). Inter is the Chapter
brand sans (Brand Assets/Fonts on the Chapter OneDrive; SIL Open Font License 1.1, see
ios/Packages/PlanExport/THIRD_PARTY_NOTICES.md). Needs fontTools. The output depends only on
the inputs.
"""

import argparse
import base64
import io
import re
import textwrap
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "ios/Packages/PlanExport/Sources/PlanExport/ChapterBrandAssets.swift"


def winansi_characters():
    """WinAnsi code -> character for codes 32...255 (None where cp1252 has none)."""
    table = {}
    for code in range(32, 256):
        try:
            table[code] = bytes([code]).decode("cp1252")
        except UnicodeDecodeError:
            table[code] = None
    return table


def logo_paths(svg_text):
    """Each <path> of the traced logo as a compact `M x y C ... Z` string in logo units, y up,
    origin at the lower left of the ink; plus the logo's width and height."""
    paths = []
    for tag in re.findall(r"<path\b[^>]*>", svg_text):
        match = re.search(r'\sd="([^"]+)"', tag)
        if match is None:
            continue  # the trace has a few empty paths
        d = match.group(1)
        dx, dy = 0.0, 0.0
        transform = re.search(r'transform="translate\(([-\d.]+),([-\d.]+)\)"', tag)
        if transform:
            dx, dy = float(transform.group(1)), float(transform.group(2))
        commands = []
        for command, numbers in re.findall(r"([MCLZmclz])([^MCLZmclz]*)", d):
            if command not in "MCLZ":
                raise SystemExit(f"unexpected path command {command}")
            values = [float(v) for v in re.findall(r"-?\d*\.?\d+(?:e-?\d+)?", numbers)]
            points = [(values[i] + dx, values[i + 1] + dy) for i in range(0, len(values), 2)]
            commands.append((command, points))
        paths.append(commands)
    xs = [p[0] for path in paths for _, pts in path for p in pts]
    ys = [p[1] for path in paths for _, pts in path for p in pts]
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)
    out = []
    for path in paths:
        parts = []
        for command, points in path:
            parts.append(command)
            for x, y in points:
                parts.append(str(round(x - min_x)))
                parts.append(str(round(max_y - y)))
        out.append(" ".join(parts))
    return out, round(max_x - min_x), round(max_y - min_y)


def inter_instance(source, weight, codes):
    """Inter at `weight`, cut down to the WinAnsi characters, without hinting or layout tables,
    and its PDF metrics in 1/1000 em."""
    font = TTFont(source)
    font = instancer.instantiateVariableFont(font, {"wght": weight, "slnt": 0})
    options = subset.Options()
    options.layout_features = []
    options.hinting = False
    options.glyph_names = False
    options.notdef_outline = True
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.drop_tables += ["GSUB", "GPOS", "GDEF", "STAT", "HVAR", "MVAR", "gasp", "prep",
                            "fpgm", "cvt ", "kern", "DSIG"]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[ord(c) for c in codes.values() if c is not None])
    subsetter.subset(font)
    font.recalcTimestamp = False
    buffer = io.BytesIO()
    font.save(buffer)
    data = buffer.getvalue()

    font = TTFont(io.BytesIO(data))
    upm = font["head"].unitsPerEm
    scale = 1000 / upm
    cmap = font.getBestCmap()
    hmtx = font["hmtx"]
    question = hmtx[cmap[ord("?")]][0]
    widths = []
    for code in range(32, 256):
        char = codes[code]
        glyph = cmap.get(ord(char)) if char is not None else None
        widths.append(round((hmtx[glyph][0] if glyph else question) * scale))
    head = font["head"]
    os2 = font["OS/2"]
    hhea = font["hhea"]
    metrics = {
        "bbox": [round(v * scale) for v in (head.xMin, head.yMin, head.xMax, head.yMax)],
        "ascent": round(hhea.ascent * scale),
        "descent": round(hhea.descent * scale),
        "capHeight": round(os2.sCapHeight * scale),
        "stemV": 80 if weight < 500 else 120,
    }
    return data, widths, metrics


def swift_ints(values, indent):
    lines = textwrap.wrap(", ".join(str(v) for v in values), 96 - len(indent))
    return "\n".join(indent + line for line in lines)


def swift_font(name, postscript, data, widths, metrics):
    encoded = base64.b64encode(data).decode("ascii")
    body = "\n".join("      " + line for line in textwrap.wrap(encoded, 90))
    bbox = ", ".join(str(v) for v in metrics["bbox"])
    return f"""  /// {postscript}: WinAnsi characters only, no hinting.
  static let {name} = EmbeddedFont(
    postScriptName: "{postscript}",
    widths: [
{swift_ints(widths, "      ")}
    ],
    boundingBox: [{bbox}], ascent: {metrics["ascent"]}, descent: {metrics["descent"]},
    capHeight: {metrics["capHeight"]}, stemV: {metrics["stemV"]},
    base64: \"\"\"
{body}
      \"\"\")
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logo", required=True, type=Path)
    parser.add_argument("--inter", required=True, type=Path)
    args = parser.parse_args()

    paths, width, height = logo_paths(args.logo.read_text())
    codes = winansi_characters()
    regular = inter_instance(args.inter, 400, codes)
    semibold = inter_instance(args.inter, 600, codes)

    # Paths separated by "|", wrapped at whitespace so the file stays readable.
    logo = "\n".join("    " + line for line in textwrap.wrap(" | ".join(paths), 92))
    swift = f"""// Generated by tools/brand/generate_plan_brand.py. Do not edit.
// The Chapter logo (hellochapter.com) and Inter (SIL Open Font License 1.1; see
// THIRD_PARTY_NOTICES.md in this package).

import Foundation

enum ChapterBrandAssets {{
  /// A TrueType font embedded in the PDFs, with the metrics the PDF font descriptor needs.
  /// Widths are for WinAnsi codes 32...255, in 1/1000 em.
  struct EmbeddedFont: Sendable {{
    let postScriptName: String
    let widths: [Int]
    let boundingBox: [Int]
    let ascent: Int
    let descent: Int
    let capHeight: Int
    let stemV: Int
    let base64: String

    var data: Data {{ Data(base64Encoded: base64, options: .ignoreUnknownCharacters) ?? Data() }}
  }}

  /// Size of the logo's ink, logo units.
  static let logoWidth = {width}.0
  static let logoHeight = {height}.0

  /// The logo ("chapter" over "RENOVATION") as filled paths, each `M x y`, `C x1 y1 x2 y2 x y`
  /// and `Z` commands in logo units, y up from the lower left of the ink.
  static let logoPaths: [String] = logoPathData.split(separator: "|").map(String.init)

  private static let logoPathData = \"\"\"
{logo}
    \"\"\"

{swift_font("interRegular", "Inter-Regular", *regular)}
{swift_font("interSemiBold", "Inter-SemiBold", *semibold)}}}
"""
    OUTPUT.write_text(swift)
    print(f"wrote {OUTPUT.relative_to(ROOT)}: logo {len(paths)} paths {width}x{height}, "
          f"Inter Regular {len(regular[0])} bytes, SemiBold {len(semibold[0])} bytes")


if __name__ == "__main__":
    main()
