"""Increment the CFBundleVersion (build number) in project.yml by 1.

Run from the repo root before each archive:

    python scripts/bump_build.py
    ~/bin/xcodegen generate

ASC rejects duplicate build numbers within a given CFBundleShortVersionString,
so every archive that gets uploaded needs to bump this. XcodeGen wipes any
manual Xcode-side increments on every regen — the value lives in project.yml.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
YML = ROOT / "project.yml"

content = YML.read_text(encoding="utf-8")
m = re.search(r'CFBundleVersion:\s*"(\d+)"', content)
if not m:
    sys.exit("CFBundleVersion not found in project.yml")
old = int(m.group(1))
new = old + 1
content = re.sub(
    r'(CFBundleVersion:\s*)"\d+"',
    f'\\1"{new}"',
    content,
    count=1,
)
YML.write_text(content, encoding="utf-8")
print(f"Build number bumped: {old} -> {new}")
print("Now run: ~/bin/xcodegen generate")
