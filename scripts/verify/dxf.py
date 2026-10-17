"""Strict DXF check with ezdxf: the file must load, audit without errors and have entities.

Runs inside the pinned Python image started by scripts/verify-exports.sh.
Usage: python dxf.py <file> [<file> ...]
"""

import sys

import ezdxf


def main(paths: list[str]) -> int:
    failed = 0
    for path in paths:
        try:
            doc = ezdxf.readfile(path)  # strict reader: structure errors fail here
        except Exception as exc:  # noqa: BLE001 - any read failure is a failed check
            print(f"FAIL {path}: cannot read DXF: {exc}")
            failed += 1
            continue
        auditor = doc.audit()
        entities = len(doc.modelspace())
        if auditor.has_errors:
            print(f"FAIL {path}: {len(auditor.errors)} audit error(s)")
            for error in auditor.errors:
                print(f"  {error.message}")
            failed += 1
        elif entities == 0:
            print(f"FAIL {path}: modelspace has no entities")
            failed += 1
        else:
            print(f"OK   {path}: {entities} entities, audit clean")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
