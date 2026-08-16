#!/usr/bin/env python3
"""Validate i18n/strings.json: en/zh key parity + placeholder consistency.

Why this exists: a tooling edit once truncated the tail of the zh block, leaving
en/zh with different key counts. Godot only notices at runtime (missing-key
fallbacks), so this is a fast pre-commit gate.

Usage:
    python tools/check_strings.py               # checks res://i18n/strings.json
    python tools/check_strings.py path/to.json  # checks a specific file

Exit code 0 = balanced, 1 = problem found (or file/JSON error).
"""

import json
import re
import sys
from pathlib import Path

PLACEHOLDER = re.compile(r"\{[a-zA-Z0-9_]+\}")


def load(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        print(f"ERROR: cannot read {path}: {e}")
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        print(f"ERROR: {path} is not valid JSON: line {e.lineno} col {e.colno}: {e.msg}")
        return None


def check(path: Path) -> bool:
    data = load(path)
    if data is None:
        return False
    if not isinstance(data, dict):
        print(f"ERROR: {path} root must be an object")
        return False

    problems = []
    for lang in ("en", "zh"):
        if lang not in data or not isinstance(data[lang], dict):
            problems.append(f"missing or non-object '{lang}' block")
    if problems:
        for p in problems:
            print(f"FAIL: {p}")
        return False

    en, zh = data["en"], data["zh"]
    en_keys, zh_keys = set(en), set(zh)

    only_en = sorted(en_keys - zh_keys)
    only_zh = sorted(zh_keys - en_keys)
    if only_en:
        problems.append(f"{len(only_en)} key(s) in en but not zh: {only_en}")
    if only_zh:
        problems.append(f"{len(only_zh)} key(s) in zh but not en: {only_zh}")

    # Placeholder parity for shared keys — {max} etc. must exist on both sides.
    for k in sorted(en_keys & zh_keys):
        pe = set(PLACEHOLDER.findall(str(en[k])))
        pz = set(PLACEHOLDER.findall(str(zh[k])))
        if pe != pz:
            problems.append(f"placeholder mismatch on '{k}': en={sorted(pe)} zh={sorted(pz)}")

    if problems:
        print(f"FAIL: {path}")
        for p in problems:
            print(f"  - {p}")
        return False

    print(f"OK: {path.name} — en/zh balanced, {len(en_keys)} keys each, placeholders consistent")
    return True


def main() -> int:
    if len(sys.argv) > 1:
        target = Path(sys.argv[1])
    else:
        # tools/ sits next to i18n/ inside the Godot project dir.
        target = Path(__file__).resolve().parent.parent / "i18n" / "strings.json"
    return 0 if check(target) else 1


if __name__ == "__main__":
    raise SystemExit(main())
