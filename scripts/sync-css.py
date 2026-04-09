#!/usr/bin/env python3
# This file is part of Compact.
# Copyright (C) 2026 Midnight Foundation
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Syncs marked blocks from doc/custom-code.css into midnight-docs/src/css/custom.css.
#
# Each sync block is delimited by:
#   /* BEGIN_COMPACT_SYNC: <tag> */ ... /* END_COMPACT_SYNC: <tag> */
#
# Two modes, determined by whether any line inside the docs block carries /* COMPACT_SYNC */:
#
#   Whole-block (no /* COMPACT_SYNC */ lines):
#     The entire block content is replaced verbatim with the compiler's version.
#
#   Line-level (some lines have /* COMPACT_SYNC */):
#     Only those marked lines are updated, matched to the compiler block by CSS
#     property name. The /* COMPACT_SYNC */ marker is preserved on the updated line.
#
# The BEGIN/END marker lines themselves are always kept from the docs file.
#
# Usage:
#   python3 sync-css.py <compiler-custom.css> <docs-custom.css>           # apply sync
#   python3 sync-css.py <compiler-custom.css> <docs-custom.css> --check   # check only, exit 1 if out of sync

import re
import sys
import difflib
from pathlib import Path

BEGIN_RE = re.compile(r"/\* BEGIN_COMPACT_SYNC: (\S+) \*/")
END_RE   = re.compile(r"/\* END_COMPACT_SYNC: (\S+) \*/")
LINE_RE  = re.compile(r"/\* COMPACT_SYNC \*/")
PROP_RE  = re.compile(r"^\s*([\w-]+)\s*:")


def parse_blocks(text):
    """Return {tag: [inner lines]} for every sync block in text."""
    blocks = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = BEGIN_RE.search(lines[i])
        if m:
            tag = m.group(1)
            inner = []
            i += 1
            while i < len(lines):
                if END_RE.search(lines[i]):
                    break
                inner.append(lines[i])
                i += 1
            blocks[tag] = inner
        i += 1
    return blocks


def prop_name(line):
    m = PROP_RE.match(line)
    return m.group(1) if m else None


def sync(compiler_text, docs_text):
    compiler_blocks = parse_blocks(compiler_text)
    out_lines = []
    docs_lines = docs_text.splitlines(keepends=True)
    i = 0

    while i < len(docs_lines):
        line = docs_lines[i]
        m = BEGIN_RE.search(line)
        if m:
            tag = m.group(1)
            out_lines.append(line)  # keep BEGIN marker from docs
            i += 1

            # Collect docs inner lines up to END marker
            docs_inner = []
            while i < len(docs_lines) and not END_RE.search(docs_lines[i]):
                docs_inner.append(docs_lines[i].rstrip("\r\n"))
                i += 1

            if tag not in compiler_blocks:
                # No matching compiler block — keep docs content unchanged
                for dl in docs_inner:
                    out_lines.append(dl + "\n")
            else:
                compiler_inner = compiler_blocks[tag]
                marked_indices = [j for j, l in enumerate(docs_inner) if LINE_RE.search(l)]

                if not marked_indices:
                    # Whole-block sync: replace inner content verbatim from compiler
                    for cl in compiler_inner:
                        out_lines.append(cl + "\n")
                else:
                    # Line-level sync: update only /* COMPACT_SYNC */ lines
                    updated = list(docs_inner)
                    for j in marked_indices:
                        p = prop_name(LINE_RE.sub("", docs_inner[j]))
                        if p:
                            for cl in compiler_inner:
                                if prop_name(cl) == p:
                                    updated[j] = cl.rstrip() + " /* COMPACT_SYNC */"
                                    break
                    for dl in updated:
                        out_lines.append(dl + "\n")

            # Keep END marker from docs
            if i < len(docs_lines):
                out_lines.append(docs_lines[i])
                i += 1
        else:
            out_lines.append(line)
            i += 1

    return "".join(out_lines)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = [a for a in sys.argv[1:] if a.startswith("--")]
    check_only = "--check" in flags

    if len(args) != 2:
        print(f"Usage: {sys.argv[0]} <compiler-custom-file.css> <docs-custom-file.css> [--check]", file=sys.stderr)
        sys.exit(1)

    compiler_path = Path(args[0])
    docs_path     = Path(args[1])

    compiler_text = compiler_path.read_text(encoding="utf-8")
    docs_text     = docs_path.read_text(encoding="utf-8")
    result        = sync(compiler_text, docs_text)

    if check_only:
        if result != docs_text:
            diff = difflib.unified_diff(
                docs_text.splitlines(keepends=True),
                result.splitlines(keepends=True),
                fromfile=str(docs_path),
                tofile=str(docs_path) + " (after sync)",
            )
            sys.stdout.writelines(diff)
            print(f"\nCSS sync blocks are out of sync in {docs_path}", file=sys.stderr)
            sys.exit(1)
        else:
            print(f"OK: CSS sync blocks are up to date in {docs_path}")
    else:
        docs_path.write_text(result, encoding="utf-8")
        print(f"Updated {docs_path}")
