#!/usr/bin/env bash
# Plan sheet snapshots (plan-sheet spec 13.2, acceptance PS8).
#
# Renders the plan sheets the PlanExport tests write (swift test --package-path
# ios/Packages/PlanExport) with poppler's pdftoppm at 72 dpi, in colour and in grey scale (-gray,
# the black-and-white proof), and compares each render with its golden in
# ios/Packages/PlanExport/Tests/Goldens/plan-sheet/<name>.png and <name>-gray.png: at most 0.5 %
# of the pixels may differ by more than 16 levels in any channel.
#
# Usage: scripts/verify/plan-sheet-snapshot.sh [--record] [<test-output dir>]
#
#   --record   write the renders as the new goldens (after an intended change; review them
#              next to artboards 1b and 1ac first)
#
# The reference render is the pinned Debian image (Docker, poppler-utils and the URW base 35
# fonts that stand in for the standard Times-Roman, Times-Italic and Courier, which the sheets
# name but do not embed). Without Docker it renders with the local pdftoppm and pins the
# stand-ins itself (a fontconfig file of its own, so the machine's font settings do not
# matter): the URW base 35 fonts when they are installed (or in $PLAN_SHEET_URW_FONTS), else
# on macOS its Times and Courier, with Times New Roman Italic for the italic (poppler draws
# only the first face of a .ttc collection, so Times.ttc has no italic for it). It prints the
# font each one maps to; goldens recorded with stand-ins other than URW are to be recorded
# again in the reference image. The comparison is Python 3 with the standard library only.
set -euo pipefail

DEBIAN_IMAGE="debian:bookworm-20261005-slim"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output="${repo_root}/ios/Packages/PlanExport/.build/test-output"
goldens="${repo_root}/ios/Packages/PlanExport/Tests/Goldens/plan-sheet"
record=0
for arg in "$@"; do
  case "${arg}" in
    --record) record=1 ;;
    -h | --help)
      sed -n '2,25p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) output="$(cd "${arg}" && pwd)" ;;
  esac
done

# The sheets with goldens: every generated fixture capture, the walk-through, and the 424
# sample in each north state (verified 212° ±8 true, approximate magnetic ±12, no reading).
sheets=(
  box-room/floor-1
  l-shaped-room/floor-1
  two-room-apartment/floor-1
  two-floor-house/floor-1
  two-floor-house/floor-2
  walkthrough/apartment
  sample-424-verified/floor-1
  sample-424-approximate/floor-1
  sample-424-not-verified/floor-1
)
missing=0
for sheet in "${sheets[@]}"; do
  if [[ ! -f "${output}/${sheet}/plan-sheet.pdf" ]]; then
    echo "plan-sheet-snapshot: FAIL: ${output}/${sheet}/plan-sheet.pdf is missing" >&2
    missing=1
  fi
done
if [[ ${missing} -ne 0 ]]; then
  echo "plan-sheet-snapshot: run swift test --package-path ios/Packages/PlanExport first." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Renders <sheet>/plan-sheet.pdf to <name>.ppm (colour) and <name>-gray.pgm.
render_commands() {
  local root="$1" out="$2"
  for sheet in "${sheets[@]}"; do
    local name="${sheet//\//-}"
    echo "pdftoppm -r 72 -singlefile '${root}/${sheet}/plan-sheet.pdf' '${out}/${name}'"
    echo "pdftoppm -r 72 -gray -singlefile '${root}/${sheet}/plan-sheet.pdf' '${out}/${name}-gray'"
  done
}

if command -v docker >/dev/null 2>&1; then
  echo "plan-sheet-snapshot: rendering in ${DEBIAN_IMAGE} (poppler-utils, fonts-urw-base35)"
  docker run --rm -v "${output}:/data:ro" -v "${work}:/out" "${DEBIAN_IMAGE}" bash -c "
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq --no-install-recommends poppler-utils fonts-urw-base35 >/dev/null
    $(render_commands /data /out)
    chmod a+rw /out/*"
elif command -v pdftoppm >/dev/null 2>&1; then
  echo "plan-sheet-snapshot: Docker not installed; rendering with the local $(pdftoppm -v 2>&1 | head -1)"
  # The stand-ins for the standard fonts, pinned in a fontconfig file of the script's own.
  urw=""
  for dir in "${PLAN_SHEET_URW_FONTS:-}" /usr/share/fonts/opentype/urw-base35 \
    /usr/share/fonts/type1/urw-base35 /usr/share/fonts/urw-base35 \
    /usr/local/share/fonts/urw-base35; do
    if [[ -n "${dir}" ]] && compgen -G "${dir}/NimbusRoman-Italic.*" >/dev/null; then
      urw="${dir}"
      break
    fi
  done
  conf="${work}/fonts.conf"
  if [[ -n "${urw}" ]]; then
    fonts="the URW base 35 fonts (as the reference image)"
    cat >"${conf}" <<FONTS
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>${urw}</dir>
  <cachedir>${work}/fontconfig</cachedir>
  <match target="pattern"><test name="family"><string>Times</string></test>
    <edit name="family" mode="assign" binding="strong"><string>Nimbus Roman</string></edit></match>
  <match target="pattern"><test name="family"><string>Courier</string></test>
    <edit name="family" mode="assign" binding="strong"><string>Nimbus Mono PS</string></edit></match>
</fontconfig>
FONTS
  elif [[ -f /System/Library/Fonts/Times.ttc && -f /System/Library/Fonts/Courier.ttc ]]; then
    fonts="stand-ins for the URW base 35 fonts: record goldens again in the reference image"
    cat >"${conf}" <<FONTS
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/System/Library/Fonts</dir>
  <dir>/System/Library/Fonts/Supplemental</dir>
  <cachedir>${work}/fontconfig</cachedir>
  <match target="pattern"><test name="family"><string>Times</string></test>
    <test name="slant" compare="more"><int>0</int></test>
    <edit name="family" mode="assign" binding="strong"><string>Times New Roman</string></edit></match>
</fontconfig>
FONTS
  else
    fonts="the machine's own font settings: record goldens again in the reference image"
    conf=""
  fi
  if [[ -n "${conf}" ]]; then export FONTCONFIG_FILE="${conf}"; fi
  echo "plan-sheet-snapshot: standard fonts from ${fonts}"
  if command -v fc-match >/dev/null 2>&1; then
    for font in "Times-Roman=Times" "Times-Italic=Times:slant=100" "Courier=Courier"; do
      echo "  ${font%%=*} -> $(fc-match -f '%{file} (%{family[0]} %{style[0]})' "${font#*=}")"
    done
  fi
  eval "$(render_commands "${output}" "${work}")"
else
  echo "plan-sheet-snapshot: FAIL: needs Docker or a local poppler pdftoppm." >&2
  exit 1
fi

mkdir -p "${goldens}"
python3 -I - "${work}" "${goldens}" "${record}" "${sheets[@]}" <<'PYTHON'
"""Compares (or records) the renders in <work> with the goldens."""
import os
import struct
import sys
import zlib

work, goldens, record = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
sheets = sys.argv[4:]
SHARE = 0.005   # at most 0.5 % of the pixels ...
LEVELS = 16     # ... may differ by more than 16 levels


def read_pnm(path):
    """Binary PPM (P6) or PGM (P5), 8 bit: (width, height, channels, bytes)."""
    data = open(path, "rb").read()
    fields, index = [], 0
    while len(fields) < 4:
        while data[index:index + 1].isspace():
            index += 1
        if data[index:index + 1] == b"#":
            index = data.index(b"\n", index) + 1
            continue
        start = index
        while not data[index:index + 1].isspace():
            index += 1
        fields.append(data[start:index])
    index += 1
    magic, width, height, maximum = fields[0], int(fields[1]), int(fields[2]), int(fields[3])
    assert maximum == 255, path
    channels = 3 if magic == b"P6" else 1
    return width, height, channels, data[index:index + width * height * channels]


def read_png(path):
    """8-bit grey or RGB PNG, not interlaced: (width, height, channels, bytes)."""
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    index, idat = 8, b""
    while index < len(data):
        length, kind = struct.unpack(">I4s", data[index:index + 8])
        body = data[index + 8:index + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and colour in (0, 2) and interlace == 0, path
        elif kind == b"IDAT":
            idat += body
        index += 12 + length
    channels = 3 if colour == 2 else 1
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(stride * height)
    previous = bytearray(stride)
    for row in range(height):
        kind = raw[row * (stride + 1)]
        line = bytearray(raw[row * (stride + 1) + 1:(row + 1) * (stride + 1)])
        if kind == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + (left + previous[i]) // 2) & 255
        elif kind == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out[row * stride:(row + 1) * stride] = line
        previous = line
    return width, height, channels, bytes(out)


def write_png(path, width, height, channels, pixels):
    stride = width * channels
    raw = b"".join(b"\x00" + pixels[row * stride:(row + 1) * stride] for row in range(height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    header = struct.pack(">IIBBBBB", width, height, 8, 2 if channels == 3 else 0, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


failed = 0
for sheet in sheets:
    for suffix, extension in (("", "ppm"), ("-gray", "pgm")):
        name = sheet.replace("/", "-") + suffix
        render = read_pnm(os.path.join(work, f"{name}.{extension}"))
        golden_path = os.path.join(goldens, f"{name}.png")
        if record:
            write_png(golden_path, *render)
            print(f"recorded {golden_path}")
            continue
        if not os.path.exists(golden_path):
            print(f"FAIL {name}: no golden (run with --record)")
            failed = 1
            continue
        golden = read_png(golden_path)
        if golden[:3] != render[:3]:
            print(f"FAIL {name}: render {render[:3]}, golden {golden[:3]}")
            failed = 1
            continue
        width, height, channels, a = render
        b = golden[3]
        differing = 0
        if a != b:
            over = [abs(x - y) > LEVELS for x, y in zip(a, b)]
            if channels == 1:
                differing = sum(over)
            else:
                differing = sum(
                    1 for i in range(0, len(over), 3) if over[i] or over[i + 1] or over[i + 2])
        share = differing / (width * height)
        status = "OK  " if share <= SHARE else "FAIL"
        if share > SHARE:
            failed = 1
        print(f"{status} {name}: {differing} of {width * height} pixels differ ({share:.4%})")
sys.exit(failed)
PYTHON
echo "plan-sheet-snapshot: $([[ ${record} -eq 1 ]] && echo recorded || echo all ${#sheets[@]} sheets match their colour and grey-scale goldens)."
