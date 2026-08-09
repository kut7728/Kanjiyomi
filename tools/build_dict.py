#!/usr/bin/env python3
"""Build bundled JMdict SQLite for Kanjiyomi.

Downloads JMdict_e (English glosses), parses entries, and writes:
  Kanjiyomi/Resources/jmdict.sqlite

Schema:
  entries(id INTEGER PK, kanji TEXT, reading TEXT, pos TEXT, gloss TEXT)
  Indexes on kanji and reading for fast lookup.
"""

from __future__ import annotations

import gzip
import os
import sqlite3
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

JMDICT_URL = "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
OUTPUT_PATH = os.path.join(REPO_ROOT, "Kanjiyomi", "Resources", "jmdict.sqlite")


def download_jmdict(dest_gz: str) -> None:
    print("Downloading JMdict_e.gz …")
    urllib.request.urlretrieve(JMDICT_URL, dest_gz)
    size_mb = os.path.getsize(dest_gz) / (1024 * 1024)
    print("Downloaded {:.1f} MB".format(size_mb))


def local_text(elem, tag):
    child = elem.find(tag)
    if child is None or child.text is None:
        return None
    return child.text.strip()


def parse_and_build(gz_path: str, db_path: str) -> int:
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("PRAGMA journal_mode=OFF")
    cur.execute(
        """
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY,
            kanji TEXT NOT NULL DEFAULT '',
            reading TEXT NOT NULL DEFAULT '',
            pos TEXT NOT NULL DEFAULT '',
            gloss TEXT NOT NULL DEFAULT ''
        )
        """
    )
    cur.execute("CREATE INDEX idx_entries_kanji ON entries(kanji)")
    cur.execute("CREATE INDEX idx_entries_reading ON entries(reading)")

    print("Parsing XML (streaming) …")
    count = 0
    batch = []
    batch_size = 2000

    with gzip.open(gz_path, "rb") as fh:
        # Iterparse for memory efficiency
        context = ET.iterparse(fh, events=("end",))
        for _event, elem in context:
            if elem.tag != "entry":
                continue

            kebs = [k.text.strip() for k in elem.findall("k_ele/keb") if k.text]
            rebs = [r.text.strip() for r in elem.findall("r_ele/reb") if r.text]
            if not rebs and not kebs:
                elem.clear()
                continue

            senses = []
            for sense in elem.findall("sense"):
                poses = [p.text.strip() for p in sense.findall("pos") if p.text]
                glosses = [
                    g.text.strip()
                    for g in sense.findall("gloss")
                    if g.text and (g.get("{http://www.w3.org/XML/1998/namespace}lang") in (None, "eng"))
                ]
                if not glosses:
                    continue
                senses.append(
                    (
                        ";".join(poses),
                        "; ".join(glosses[:5]),
                    )
                )

            if not senses:
                elem.clear()
                continue

            # Flatten: each kanji (or empty) × primary reading × aggregated sense
            primary_reading = rebs[0]
            pos_all = []
            gloss_all = []
            for pos, gloss in senses[:3]:
                if pos:
                    pos_all.append(pos)
                gloss_all.append(gloss)
            pos_str = "|".join(pos_all)
            gloss_str = " / ".join(gloss_all)

            targets = kebs if kebs else [""]
            for kanji in targets:
                batch.append((kanji, primary_reading, pos_str, gloss_str))
                # Also index by reading alone once per entry
            # Ensure reading-only lookup row exists
            if kebs:
                batch.append(("", primary_reading, pos_str, gloss_str))

            if len(batch) >= batch_size:
                cur.executemany(
                    "INSERT INTO entries(kanji, reading, pos, gloss) VALUES (?, ?, ?, ?)",
                    batch,
                )
                count += len(batch)
                batch = []
                if count % 50000 == 0:
                    print("  inserted ~{} rows …".format(count))

            elem.clear()

    if batch:
        cur.executemany(
            "INSERT INTO entries(kanji, reading, pos, gloss) VALUES (?, ?, ?, ?)",
            batch,
        )
        count += len(batch)

    conn.commit()

    # Compact
    cur.execute("VACUUM")
    conn.close()
    return count


def main() -> int:
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

    cache_gz = os.path.join(SCRIPT_DIR, ".cache", "JMdict_e.gz")
    os.makedirs(os.path.dirname(cache_gz), exist_ok=True)

    if not os.path.exists(cache_gz):
        try:
            download_jmdict(cache_gz)
        except Exception as exc:
            print("ERROR: failed to download JMdict: {}".format(exc), file=sys.stderr)
            print("Place JMdict_e.gz at {} and re-run.".format(cache_gz), file=sys.stderr)
            return 1
    else:
        print("Using cached {}".format(cache_gz))

    print("Writing {}".format(OUTPUT_PATH))
    rows = parse_and_build(cache_gz, OUTPUT_PATH)
    size_mb = os.path.getsize(OUTPUT_PATH) / (1024 * 1024)
    print("Done: {} rows, {:.1f} MB → {}".format(rows, size_mb, OUTPUT_PATH))
    return 0


if __name__ == "__main__":
    sys.exit(main())
