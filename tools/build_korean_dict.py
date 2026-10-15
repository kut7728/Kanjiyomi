#!/usr/bin/env python3
"""Build the offline Korean meanings sidecar from pinned local source dumps.

Sources: KRDICT JSON (https://krdict.korean.go.kr/download/downloadPopup),
Kaikki Korean Wiktionary JSONL (https://kaikki.org/kowiktionary/rawdata.html),
and JMdict (https://www.edrdg.org/jmdict/j_jmdict.html).
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import re
import sqlite3
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path
from urllib.parse import quote

HASHES = {
    "krdict": "f9c1b9309afe66429a92cca1b2c426db25ec809d04103aca74c3a23859280df6",
    "wiktionary": "911d2d956669703efd1f5fc459e9733c7359c340c7344e80f012a7b8eaac308b",
    "jmdict": "d1da7185e4cb331c08bdef9c89d3651a078de9583c8c13ba41353c04b9d30cc4",
}
URLS = {
    "krdict": "https://krdict.korean.go.kr/dicBatchDownload?seq=217",
    "wiktionary": "https://kaikki.org/kowiktionary/raw-wiktextract-data.jsonl.gz",
    "jmdict": "https://www.edrdg.org/jmdict/j_jmdict.html",
}
LICENSE = {"krdict": "CC BY-SA 2.0 KR", "wiktionary": "CC BY-SA 4.0"}
KANA = re.compile(r"^[\u3040-\u30ffー・]+$")
HANGUL = re.compile(r"[\uac00-\ud7a3]")
PAREN = re.compile(r"\s*\([^()]*\)")
SPECIAL = re.compile(r"\([^()]*比喩的[^()]*\)|\([^()]*비유적[^()]*\)")


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", PAREN.sub("", s)).strip().casefold()


def english_terms(s: str):
    return {norm(term) for term in re.split(r"[;,]", norm(s)) if norm(term)}


def feat_map(item):
    feat = item.get("feat", [])
    if isinstance(feat, dict):
        feat = [feat]
    return {x.get("att"): x.get("val", "") for x in feat if isinstance(x, dict)}


def values(parent, key):
    x = parent.get(key, [])
    return x if isinstance(x, list) else ([x] if x else [])


def parse_jmdict(path: Path):
    allowed = defaultdict(set)
    english = defaultdict(set)
    with gzip.open(path, "rb") as f:
        for _, e in ET.iterparse(f, events=("end",)):
            if e.tag != "entry":
                continue
            kebs = [x.text.strip() for x in e.findall("k_ele/keb") if x.text]
            readings = [(x.findtext("reb", "").strip(), {r.text for r in x.findall("re_restr") if r.text}, x.find("re_nokanji") is not None) for x in e.findall("r_ele") if x.findtext("reb")]
            pairs = set()
            for reading, restrictions, no_kanji in readings:
                if no_kanji:
                    pairs.add(("", reading))
                    continue
                for written in kebs or [""]:
                    if not restrictions or written in restrictions:
                        pairs.add((written, reading))
            for pair in pairs:
                allowed[pair].add(e.findtext("ent_seq", ""))
            for s in e.findall("sense"):
                sk = {x.text for x in s.findall("stagk") if x.text}
                sr = {x.text for x in s.findall("stagr") if x.text}
                gloss = {norm(x.text or "") for x in s.findall("gloss") if x.get("{http://www.w3.org/XML/1998/namespace}lang", "eng") == "eng"}
                for pair in pairs:
                    if (not sk or pair[0] in sk) and (not sr or pair[1] in sr):
                        english[pair].update(x for x in gloss if x)
            e.clear()
    return allowed, english


def japanese_forms(lemma: str):
    """Split explicit kana【written】 units; JMdict validates each result."""
    out = set()
    for unit in re.split(r"[。;；]", lemma):
        unit = unit.strip()
        m = re.fullmatch(r"([\u3040-\u30ffー・]+)(?:〖([^〗]*)〗|【([^】]+)】)", unit)
        if m:
            raw_written = m.group(2) or m.group(3) or ""
            writings = [w for w in raw_written.split("・") if w]
            for reading in (x for x in m.group(1).split("・") if x):
                for written in writings:
                    out.add((written, reading))
        elif KANA.fullmatch(unit):
            out.add(("", unit))
    return out


def canonical_ruby_reading(word: str, ruby):
    """Apply Kaikki [kanji, kana] ruby pairs while retaining unannotated kana."""
    if not isinstance(ruby, list) or not ruby:
        return ""
    result, cursor = [], 0
    for pair in ruby:
        if not isinstance(pair, list) or len(pair) != 2:
            return ""
        surface, reading = pair
        position = word.find(surface, cursor) if surface else -1
        if position < 0 or not reading:
            return ""
        result.append(word[cursor:position])
        result.append(reading)
        cursor = position + len(surface)
    result.append(word[cursor:])
    reading = "".join(result)
    return reading if KANA.fullmatch(reading) else ""


def krdict_candidates(path: Path, allowed, english):
    found = defaultdict(lambda: defaultdict(set))
    with zipfile.ZipFile(path) as z:
        for name in sorted(z.namelist()):
            resource = json.load(z.open(name))["LexicalResource"]["Lexicon"]["LexicalEntry"]
            for entry in resource:
                lemmas = values(entry, "Lemma")
                korean = next((feat_map(x).get("writtenForm", "").strip() for x in lemmas if feat_map(x).get("writtenForm")), "")
                if not korean:
                    continue
                entry_info = feat_map(entry)
                pos = entry_info.get("partOfSpeech", "") + entry_info.get("lexicalUnit", "")
                for sense in values(entry, "Sense"):
                    sid = str(entry.get("val", "")) + ":" + str(sense.get("val", ""))
                    equivalents = [feat_map(x) for x in values(sense, "Equivalent")]
                    ja = [x for x in equivalents if x.get("language") == "일본어"]
                    en = set().union(*(english_terms(x.get("lemma", "")) for x in equivalents if x.get("language") in ("영어", "영어(미국)")))
                    # KRDICT's Korean gloss is the entry lemma; Equivalent.definition is
                    # the foreign-language definition and must never be copied as Korean.
                    sense_info = feat_map(sense)
                    if (SPECIAL.search(" ".join(x.get("definition", "") for x in ja) + " " + sense_info.get("definition", ""))
                            or any(x in pos for x in ("문법", "속담", "관용구"))
                            or any(x in str(sense_info.values()) for x in ("문법", "속담", "관용구"))):
                        continue
                    for item in ja:
                        for pair in japanese_forms(item.get("lemma", "")):
                            if pair not in allowed:
                                continue
                            if not en.intersection(english[pair]):
                                continue
                            found[pair]["krdict"].add((korean, sid, ""))
    return found


def wiktionary_candidates(path: Path, allowed):
    found = defaultdict(lambda: defaultdict(set))
    readings_by_word = defaultdict(set)
    reading_only = {reading for written, reading in allowed if not written}
    for written, reading in allowed:
        if written:
            readings_by_word[written].add(reading)
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            if d.get("lang_code") != "ja":
                continue
            if d.get("form_of") or d.get("alt_of") or d.get("no-gloss") or d.get("no_gloss") or _reference_tags(d):
                continue
            word = d.get("word", "").strip()
            if not word:
                continue
            canonical = set()
            for form in d.get("forms", []):
                if form.get("form") == word:
                    reading = canonical_ruby_reading(word, form.get("ruby"))
                    if reading:
                        canonical.add(reading)
            if len(canonical) > 1:
                continue
            sounds = {s.get("other", "") for s in d.get("sounds", []) if KANA.fullmatch(s.get("other", ""))}
            if len(sounds) > 1 or (canonical and sounds and sounds != canonical):
                continue
            explicit = canonical or sounds
            normalized_written = word if any("\u4e00" <= c <= "\u9fff" for c in word) else ""
            readings = explicit or (readings_by_word.get(word, set()) if normalized_written else ({word} if word in reading_only else set()))
            readings = {r for r in readings if ((normalized_written, r) in allowed or (not normalized_written and ("", r) in allowed))}
            if len(readings) != 1:
                continue
            reading = next(iter(readings))
            for i, sense in enumerate(d.get("senses", [])):
                if (sense.get("form_of") or sense.get("alt_of") or sense.get("no-gloss") or sense.get("no_gloss")
                        or _reference_tags(sense)):
                    continue
                tags = set(sense.get("raw_tags", [])) | set(sense.get("tags", []))
                if tags.intersection({"보조동사", "활용형", "문법", "form-of", "inflection"}):
                    continue
                for gloss in sense.get("glosses", []):
                    gloss = gloss.strip()
                    if (not HANGUL.search(gloss) or gloss.startswith(("~", "→", "참조", "다음 지명"))
                            or any(x in gloss for x in ("활용형", "형태", "보조동사", "동사의 연용형", "문법", "의 변형", "의 어형", "의 과거형", "의 현재형"))):
                        continue
                    gloss = gloss.rstrip(".。 ")
                    found[(normalized_written or reading, reading)]["wiktionary"].add((gloss, f"{word}#{i + 1}", word))
    return found


def _reference_tags(item):
    tags = set()
    for key in ("tags", "raw_tags"):
        value = item.get(key, [])
        tags.update([value] if isinstance(value, str) else value or [])
    return bool({str(tag).casefold().replace("_", "-") for tag in tags} & {"form-of", "alt-of", "no-gloss"})


def load_reviews(path: Path):
    try:
        review = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read valid review JSON {path}: {exc}") from exc
    if (not isinstance(review, dict) or not isinstance(review.get("review_date"), str)
            or not review["review_date"] or not isinstance(review.get("method"), str)
            or not review["method"] or not isinstance(review.get("reviewed"), list) or not review["reviewed"]
            or not isinstance(review.get("exclude"), list)
            or any(not isinstance(review.get(k), int) or review[k] < 0 for k in ("sample_random_count", "named_check_count", "manual_exclusion_count"))
            or sum(review[k] for k in ("sample_random_count", "named_check_count", "manual_exclusion_count")) != len(review["reviewed"])):
        raise ValueError(f"invalid review file structure: {path}")
    for item in review["reviewed"]:
        if (not isinstance(item, dict) or item.get("decision") not in {"accept", "exclude", "not_found"}
                or not isinstance(item.get("written"), str) or not isinstance(item.get("reading"), str)
                or item.get("source") not in {"krdict", "wiktionary"} or not isinstance(item.get("note"), str) or not item["note"]
                or not isinstance(item.get("source_id"), str)
                or (item["decision"] == "accept" and (not item["source_id"] or not item.get("source_gloss")))):
            raise ValueError(f"invalid reviewed record in {path}")
    for item in review["exclude"]:
        if (not isinstance(item, dict) or not all(isinstance(item.get(k), str) and item[k] for k in ("written", "reading", "source", "source_id", "reason"))
                or item.get("source") not in {"krdict", "wiktionary"}):
            raise ValueError(f"invalid exclusion record in {path}")
    if sum(x["decision"] == "exclude" for x in review["reviewed"]) != review["manual_exclusion_count"]:
        raise ValueError(f"review exclusion count mismatch in {path}")
    return review


def build(krdict: Path, wiktionary: Path, jmdict: Path, output: Path, reviews: Path | None = None):
    reviews = reviews or Path(__file__).with_name("korean_reviews.json")
    if not reviews.is_file():
        raise ValueError(f"missing review file: {reviews}")
    review = load_reviews(reviews)
    for name, path in (("krdict", krdict), ("wiktionary", wiktionary), ("jmdict", jmdict)):
        if not path.is_file() or sha(path) != HASHES[name]:
            raise ValueError(f"missing or unexpected {name} source: {path}")
    allowed, english = parse_jmdict(jmdict)
    raw_sources = {"krdict": krdict_candidates(krdict, allowed, english), "wiktionary": wiktionary_candidates(wiktionary, allowed)}
    sources = {}
    for name, source_data in raw_sources.items():
        normalized = defaultdict(lambda: defaultdict(set))
        for (written, reading), values_by_source in source_data.items():
            key = (written or reading, reading)
            for source, meanings in values_by_source.items():
                normalized[key][source].update(meanings)
        sources[name] = normalized
    exclusions = {(x["written"], x["reading"], x["source"], x["source_id"]) for x in review.get("exclude", [])}
    rows = []
    for pair in sorted(set(sources["krdict"]) | set(sources["wiktionary"])):
        source, vals = "", []
        for candidate in ("wiktionary", "krdict"):
            vals = sorted(sources[candidate].get(pair, {}).get(candidate, ()))
            vals = [x for x in vals if (pair[0], pair[1], candidate, x[1]) not in exclusions]
            if vals:
                source = candidate
                break
        if not source:
            continue
        meanings = []
        ids = []
        for meaning, sid, _ in vals:
            if meaning in meanings:
                ids.append(sid)
            elif len(meanings) < 3:
                meanings.append(meaning); ids.append(sid)
        ids = list(dict.fromkeys(ids))
        if meanings:
            written = pair[0] or pair[1]
            if source == "wiktionary":
                source_url = ";".join(dict.fromkeys("https://ko.wiktionary.org/wiki/" + quote(title, safe="") for _, _, title in vals))
            else:
                source_url = ";".join(dict.fromkeys("https://krdict.korean.go.kr/kor/dicSearch/SearchView?ParaWordNo=" + quote(sid.split(":", 1)[0], safe="") for sid in ids))
            rows.append((written, pair[1], "; ".join(meanings), source, ",".join(ids), source_url, LICENSE[source]))
    if not rows:
        raise ValueError("no Korean meanings survived validation; keeping the existing database")
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=output.name + ".", suffix=".tmp", dir=output.parent)
    os.close(fd)
    try:
        conn = sqlite3.connect(temp_name)
        conn.execute("PRAGMA journal_mode=OFF")
        conn.execute("CREATE TABLE meanings (written TEXT NOT NULL, reading TEXT NOT NULL, meaning TEXT NOT NULL, source TEXT NOT NULL, source_id TEXT NOT NULL, source_url TEXT NOT NULL, license TEXT NOT NULL, PRIMARY KEY(written,reading))")
        conn.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY,value TEXT NOT NULL)")
        conn.executemany("INSERT INTO meanings VALUES (?,?,?,?,?,?,?)", rows)
        decisions = [x.get("decision") for x in review.get("reviewed", [])]
        meta = {
            "build.date": "2026-10-15", "processing.version": "1",
            "source.krdict.url": URLS["krdict"], "source.krdict.rights_holder": "국립국어원", "source.krdict.license": LICENSE["krdict"], "source.krdict.license_url": "https://krdict.korean.go.kr/kor/kboardPolicy/copyRightTermsInfo", "source.krdict.sha256": HASHES["krdict"], "source.krdict.date": "2026-09-19",
            "source.wiktionary.url": URLS["wiktionary"], "source.wiktionary.rights_holder": "Wiktionary contributors", "source.wiktionary.license": LICENSE["wiktionary"], "source.wiktionary.license_url": "https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content", "source.wiktionary.sha256": HASHES["wiktionary"], "source.wiktionary.date": "2026-10-01",
            "source.jmdict.url": URLS["jmdict"], "source.jmdict.rights_holder": "Electronic Dictionary Research and Development Group", "source.jmdict.license": "CC BY-SA 4.0", "source.jmdict.license_url": "https://www.edrdg.org/edrdg/licence.html", "source.jmdict.sha256": HASHES["jmdict"], "source.jmdict.date": "2026-10-15", "source.jmdict.role": "English gloss cross-check and allowed written/reading pairs; no JMdict gloss is copied",
            "processing": "Text only; examples/audio excluded; exact English gloss intersection after removing parenthetical notes and splitting enumerated translations; source priority Wiktionary then KRDICT after exclusions; max 3 meanings; written kana normalized from JMdict reading; canonical ruby reading and restricted written/reading pairs enforced",
            "processing.change_notice": "Meaning rows are selectively linked and normalized from source Japanese entries; no English/Korean meanings are machine-translated or newly generated.",
            "review.sha256": sha(reviews), "review.count.accept": str(decisions.count("accept")), "review.count.exclude": str(len(review.get("exclude", []))), "review.count.not_found": str(decisions.count("not_found")),
            "review.count.random_sample": str(review["sample_random_count"]), "review.count.named_checks": str(review["named_check_count"]),
        }
        conn.executemany("INSERT INTO metadata VALUES (?,?)", sorted(meta.items()))
        conn.commit()
        if conn.execute("PRAGMA integrity_check").fetchone() != ("ok",):
            raise sqlite3.DatabaseError("SQLite integrity check failed")
        if conn.execute("SELECT count(*) FROM meanings WHERE meaning='' OR source NOT IN ('krdict','wiktionary')").fetchone()[0]:
            raise sqlite3.DatabaseError("invalid meanings rows")
        counts = dict(conn.execute("SELECT source,count(*) FROM meanings GROUP BY source"))
        total = conn.execute("SELECT count(*) FROM meanings").fetchone()[0]
        conn.close()
        os.chmod(temp_name, 0o644)
        os.replace(temp_name, output)
        return total, counts
    except Exception:
        try: os.unlink(temp_name)
        except FileNotFoundError: pass
        raise


def main():
    p = argparse.ArgumentParser(description="Rebuild korean.sqlite from the three pinned local source files. No network access.")
    p.add_argument("--krdict", type=Path, required=True, help="/tmp/kanjiyomi-krdict-json.zip")
    p.add_argument("--wiktionary", type=Path, required=True, help="/tmp/kanjiyomi-kowikt-raw.jsonl.gz")
    p.add_argument("--jmdict", type=Path, required=True, help="/tmp/kanjiyomi-JMdict.gz")
    p.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "Kanjiyomi/Resources/korean.sqlite")
    p.add_argument("--reviews", type=Path, default=Path(__file__).with_name("korean_reviews.json"))
    a = p.parse_args()
    try:
        total, counts = build(a.krdict, a.wiktionary, a.jmdict, a.output, a.reviews)
    except (OSError, ValueError, sqlite3.DatabaseError, zipfile.BadZipFile) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"Created {a.output}: {total} rows ({counts})")
    return 0


if __name__ == "__main__": sys.exit(main())
