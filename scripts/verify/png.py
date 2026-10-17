"""PNG check with Pillow: verify the structure, then fully decode and require a non-zero size.

Runs inside the pinned Python image started by scripts/verify-exports.sh.
Usage: python png.py <file> [<file> ...]
"""

import sys

from PIL import Image


def check(path: str) -> str:
    with Image.open(path) as image:
        image.verify()
    with Image.open(path) as image:
        if image.format != "PNG":
            raise ValueError(f"not a PNG file (format {image.format})")
        image.load()
        width, height = image.size
    if width == 0 or height == 0:
        raise ValueError("image has zero size")
    return f"PNG {width}x{height}"


def main(paths: list[str]) -> int:
    failed = 0
    for path in paths:
        try:
            print(f"OK   {path}: {check(path)}")
        except Exception as exc:  # noqa: BLE001 - any decode failure is a failed check
            print(f"FAIL {path}: {exc}")
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
