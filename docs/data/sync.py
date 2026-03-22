#!/usr/bin/env python3
"""Sync player_data.csv numbers into the docs .md files.

Usage: python docs/data/sync.py
"""
import csv
import io
import re
from pathlib import Path

DATA_DIR = Path(__file__).parent
DOCS_DIR = DATA_DIR.parent
CSV_FILE = DATA_DIR / "player_data.csv"


def parse_csv(path):
    """Parse sectioned CSV. Sections start with '--- name'. Returns {name: (headers, rows)}."""
    sections = {}
    name = None
    headers = None
    rows = []

    for line in path.read_text().splitlines():
        if line.startswith("--- "):
            if name:
                sections[name] = (headers, rows)
            name = line[4:].strip()
            headers = None
            rows = []
        elif not line.strip():
            continue
        elif name is not None:
            row = next(csv.reader(io.StringIO(line)))
            if headers is None:
                headers = row
            else:
                rows.append(row)

    if name:
        sections[name] = (headers, rows)
    return sections


def make_table(headers, rows):
    """Generate a markdown table from headers and rows."""
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell))

    def fmt(cells):
        return "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"

    lines = [fmt(headers)]
    lines.append("|" + "|".join("-" * (w + 2) for w in widths) + "|")
    for row in rows:
        padded = [(row[i] if i < len(row) else "") for i in range(len(widths))]
        lines.append(fmt(padded))
    return "\n".join(lines)


def sync_file(path, sections):
    """Replace <!-- data:X --> ... <!-- end:X --> blocks in a markdown file."""
    text = path.read_text()
    count = 0

    def replacer(m):
        nonlocal count
        sec = m.group(1)
        if sec not in sections:
            print(f"  WARNING: '{sec}' not found in CSV, skipping")
            return m.group(0)
        count += 1
        headers, rows = sections[sec]
        table = make_table(headers, rows)
        return f"<!-- data:{sec} -->\n{table}\n<!-- end:{sec} -->"

    text = re.sub(
        r"<!-- data:(\S+) -->\n.*?<!-- end:\1 -->",
        replacer,
        text,
        flags=re.DOTALL,
    )
    path.write_text(text)
    return count


def main():
    sections = parse_csv(CSV_FILE)
    print(f"Loaded {len(sections)} sections from player_data.csv")

    total = 0
    for md in sorted(DOCS_DIR.rglob("*.md")):
        n = sync_file(md, sections)
        if n:
            print(f"  {md.relative_to(DOCS_DIR)}: {n} tables updated")
            total += n

    print(f"Done — {total} tables synced.")


if __name__ == "__main__":
    main()
