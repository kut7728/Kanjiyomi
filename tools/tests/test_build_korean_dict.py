import gzip
import hashlib
import io
import json
import sqlite3
import sys
import tempfile
import unittest
import zipfile
import stat
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import patch

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_korean_dict as b


class KoreanDictTests(unittest.TestCase):
    def test_japanese_forms_and_exact_gloss_rules(self):
        self.assertEqual(b.japanese_forms("はんがく【半額】。はんがく【半額品】"), {("半額", "はんがく"), ("半額品", "はんがく")})
        self.assertEqual(b.japanese_forms("くだもの・かぶつ【果物】"), {("果物", "くだもの"), ("果物", "かぶつ")})
        self.assertEqual(b.japanese_forms("もく〖木・樹〗"), {("木", "もく"), ("樹", "もく")})
        self.assertEqual(b.japanese_forms("インフルエンザ"), {("", "インフルエンザ")})
        self.assertEqual(b.canonical_ruby_reading("取り扱う", [["取", "と"], ["扱", "あつか"]]), "とりあつかう")
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "j.gz"
            xml = '''<JMdict>
            <entry><ent_seq>1</ent_seq><k_ele><keb>入口</keb><keb>入り口</keb></k_ele><r_ele><reb>いりぐち</reb><re_restr>入口</re_restr></r_ele><sense><stagk>入口</stagk><stagr>いりぐち</stagr><gloss>entrance</gloss><gloss>entrance hall</gloss></sense><sense><stagk>入り口</stagk><gloss>metaphorically</gloss></sense><sense><stagk>入口</stagk><stagr>べつ</stagr><gloss>portal</gloss></sense></entry>
            <entry><ent_seq>2</ent_seq><k_ele><keb>仮名</keb></k_ele><r_ele><reb>かな</reb><re_nokanji/></r_ele><sense><gloss>kana</gloss></sense></entry>
            </JMdict>'''.encode()
            with gzip.open(p, "wb") as f: f.write(xml)
            allowed, en = b.parse_jmdict(p)
            self.assertIn(("入口", "いりぐち"), allowed)
            self.assertNotIn(("入り口", "いりぐち"), allowed)
            self.assertIn("entrance", en[("入口", "いりぐち")])
            self.assertIn("entrance hall", en[("入口", "いりぐち")])
            self.assertNotIn("portal", en[("入口", "いりぐち")])
            self.assertIn(("", "かな"), allowed)
            self.assertNotIn(("仮名", "かな"), allowed)
            self.assertNotIn("kana", en[("入口", "いりぐち")])
            self.assertNotEqual(b.norm("entrance"), b.norm("entrance hall"))
            self.assertEqual(b.english_terms("discount; reduction (n.)"), {"discount", "reduction"})
            self.assertEqual(b.english_terms("first (note, with comma), second"), {"first", "second"})

    def test_krdict_requires_complete_english_gloss_and_skips_metaphor(self):
        def eq(language, lemma, definition="일본어 뜻"):
            return {"feat": [{"att": "language", "val": language}, {"att": "lemma", "val": lemma}, {"att": "definition", "val": definition}]}
        entry = {"val": "10", "Lemma": {"feat": {"att": "writtenForm", "val": "입구"}}, "Sense": [
            {"val": "1", "Equivalent": [eq("일본어", "いりぐち【入口】"), eq("영어", "entrance hall")]},
            {"val": "2", "Equivalent": [eq("일본어", "いりぐち【入口】", "일반적인 뜻"), eq("영어", "entrance")], "feat": [{"att":"definition", "val":"(비유적으로) 어떤 일의 시작"}]},
            {"val": "3", "Equivalent": [eq("일본어", "いりぐち【入口】"), eq("영어", "entrance")]},
        ]}
        fruit = {"val":"11", "Lemma":{"feat":{"att":"writtenForm","val":"과일"}}, "Sense":{"val":"1","Equivalent":[eq("일본어","くだもの・かぶつ【果物】"),eq("영어","fruit")]}}
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "k.zip"
            payload = {"LexicalResource": {"Lexicon": {"LexicalEntry": [entry]}}}
            with zipfile.ZipFile(p, "w") as z:
                payload["LexicalResource"]["Lexicon"]["LexicalEntry"].append(fruit)
                z.writestr("1.json", json.dumps(payload, ensure_ascii=False))
            pair = ("入口", "いりぐち")
            fruit_pair = ("果物", "くだもの")
            found = b.krdict_candidates(p, {pair, fruit_pair}, {pair: {"entrance"}, fruit_pair: {"fruit"}})
            self.assertEqual(found[pair]["krdict"], {("입구", "10:3", "")})
            self.assertEqual(found[fruit_pair]["krdict"], {("과일", "11:1", "")})
            self.assertNotIn(("果物", "かぶつ"), found)

    def test_wiktionary_ambiguous_reading_and_form_reference(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "w.gz"
            data = [
                {"word":"人気","lang_code":"ja","forms":[{"form":"人気","ruby":[["人気","にんき"]]}],"sounds":[{"other":"にんき"},{"other":"ひとけ"}],"senses":[{"glosses":["인기"]},{"glosses":["인적이 있음"]}]},
                {"word":"食べる","lang_code":"ja","forms":[{"form":"食べる","ruby":[["食","た"]]},{"form":"食べた","ruby":[["食","た"]]}],"senses":[{"glosses":["먹다"]}]},
                {"word":"入口","lang_code":"ja","forms":[{"form":"入口","ruby":[["入口","いりぐち"]]}],"senses":[{"glosses":["입구"]},{"glosses":["활용형"]}]},
                {"word":"上手","lang_code":"ja","forms":[{"form":"上手"}],"sounds":[{"other":"じょうず"},{"other":"うわて"}],"senses":[{"glosses":["능숙함"]}]},
                {"word":"いる","lang_code":"ja","senses":[{"glosses":["(동사의 연용형에 …ている 형태로 붙어)"],"raw_tags":["보조동사"]}]},
                {"word":"FormField","lang_code":"ja","form_of":[{"word":"語","word_sense":"x"}],"senses":[{"glosses":["형태 항목"]}]},
                {"word":"AltField","lang_code":"ja","alt_of":[{"word":"語"}],"senses":[{"glosses":["다른 표기"]}]},
                {"word":"Tagged","lang_code":"ja","tags":["form-of"],"senses":[{"glosses":["변화형"]}]},
                {"word":"NoGloss","lang_code":"ja","tags":["no-gloss"],"senses":[{"glosses":["참조"]}]},
                {"word":"SenseForm","lang_code":"ja","senses":[{"tags":["alt-of"],"glosses":["다른 표기"]}]},
            ]
            with gzip.open(p, "wt", encoding="utf-8") as f:
                for row in data: f.write(json.dumps(row, ensure_ascii=False) + "\n")
            allowed = {("人気","にんき"), ("人気","ひとけ"), ("入口","いりぐち"), ("上手","じょうず"), ("食べる","たべる"), ("","いる")}
            allowed.update((word, word) for word in ("FormField","AltField","Tagged","NoGloss","SenseForm"))
            got = b.wiktionary_candidates(p, allowed)
            self.assertNotIn(("人気","にんき"), got)
            self.assertNotIn(("上手","じょうず"), got)
            self.assertNotIn(("いる","いる"), got)
            for word in ("FormField","AltField","Tagged","NoGloss","SenseForm"):
                self.assertNotIn((word,word), got)
            self.assertEqual(got[("入口","いりぐち")]["wiktionary"], {("입구", "入口#1", "入口")})
            self.assertEqual(got[("食べる","たべる")]["wiktionary"], {("먹다", "食べる#1", "食べる")})

    def test_bad_source_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            paths = [root / n for n in ("k.zip", "w.gz", "j.gz")]
            for p in paths: p.write_bytes(b"wrong")
            output = root / "korean.sqlite"
            output.write_bytes(b"previous database")
            with patch.dict(b.HASHES, {"krdict": hashlib.sha256(b"wrong").hexdigest()}):
                with self.assertRaises(ValueError):
                    b.build(*paths, output)
            self.assertEqual(output.read_bytes(), b"previous database")

    def test_exclusion_falls_back_to_krdict_and_writes_attribution(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            krdict, wiktionary, jmdict, reviews = [root / n for n in ("k.zip", "w.gz", "j.gz", "reviews.json")]
            entry = {"val":"987:1", "Lemma":{"feat":{"att":"writtenForm","val":"입구"}}, "Sense":{"val":"1","Equivalent":[
                {"feat":[{"att":"language","val":"일본어"},{"att":"lemma","val":"いりぐち【入口】"},{"att":"definition","val":"建物に入るところ"}]},
                {"feat":[{"att":"language","val":"영어"},{"att":"lemma","val":"entrance"}]},
            ]}}
            kana_entry={"val":"988","Lemma":{"feat":{"att":"writtenForm","val":"かな"}},"Sense":{"val":"1","Equivalent":[
                {"feat":[{"att":"language","val":"일본어"},{"att":"lemma","val":"かな"},{"att":"definition","val":"かなの意味"}]},
                {"feat":[{"att":"language","val":"영어"},{"att":"lemma","val":"kana"}]},
            ]}}
            with zipfile.ZipFile(krdict,"w") as z:
                z.writestr("1.json",json.dumps({"LexicalResource":{"Lexicon":{"LexicalEntry":[entry,kana_entry]}}},ensure_ascii=False))
            with gzip.open(jmdict,"wb") as f:
                f.write("<JMdict><entry><ent_seq>1</ent_seq><k_ele><keb>入口</keb></k_ele><r_ele><reb>いりぐち</reb></r_ele><sense><gloss>entrance</gloss></sense></entry><entry><ent_seq>2</ent_seq><r_ele><reb>かな</reb><re_nokanji/></r_ele><sense><gloss>kana</gloss></sense></entry></JMdict>".encode())
            with gzip.open(wiktionary,"wt",encoding="utf-8") as f:
                f.write(json.dumps({"word":"入口","lang_code":"ja","forms":[{"form":"入口","ruby":[["入口","いりぐち"]]}],"senses":[{"glosses":["입구 위키"]}]},ensure_ascii=False)+"\n")
            reviews.write_text(json.dumps({"review_date":"2026-10-15","method":"fixture","sample_random_count":0,"named_check_count":1,"manual_exclusion_count":0,"reviewed":[{"written":"入口","reading":"いりぐち","source":"krdict","source_id":"987:1:1","source_gloss":"입구","decision":"accept","note":"fixture"}],"exclude":[{"written":"入口","reading":"いりぐち","source":"wiktionary","source_id":"入口#1","reason":"fixture"}]}),encoding="utf-8")
            hashes={"krdict":hashlib.sha256(krdict.read_bytes()).hexdigest(),"wiktionary":hashlib.sha256(wiktionary.read_bytes()).hexdigest(),"jmdict":hashlib.sha256(jmdict.read_bytes()).hexdigest()}
            output=root/"korean.sqlite"
            with patch.dict(b.HASHES,hashes):
                output.write_bytes(b"previous database")
                with patch.object(b, "krdict_candidates", return_value={}), patch.object(b, "wiktionary_candidates", return_value={}):
                    with self.assertRaisesRegex(ValueError, "no Korean meanings"):
                        b.build(krdict,wiktionary,jmdict,output,reviews)
                self.assertEqual(output.read_bytes(), b"previous database")
                b.build(krdict,wiktionary,jmdict,output,reviews)
                missing=root/"missing-reviews.json"
                malformed=root/"malformed-reviews.json"
                invalid_json=root/"invalid-json-reviews.json"
                malformed.write_text('{"review_date":"2026-10-15","method":"bad","reviewed":[],"exclude":[]}',encoding="utf-8")
                invalid_json.write_text('{broken',encoding="utf-8")
                for invalid_reviews in (missing,malformed,invalid_json):
                    sentinel=b"previous database"
                    output.write_bytes(sentinel)
                    argv=["build_korean_dict.py","--krdict",str(krdict),"--wiktionary",str(wiktionary),"--jmdict",str(jmdict),"--output",str(output),"--reviews",str(invalid_reviews)]
                    with patch.object(sys,"argv",argv), redirect_stderr(io.StringIO()):
                        self.assertEqual(b.main(),1)
                    self.assertEqual(output.read_bytes(),sentinel)
                b.build(krdict,wiktionary,jmdict,output,reviews)
            conn=sqlite3.connect(output)
            row=conn.execute("SELECT written,reading,meaning,source,source_id,source_url FROM meanings WHERE written='入口'").fetchone()
            self.assertEqual(row[:5],("入口","いりぐち","입구","krdict","987:1:1"))
            self.assertIn("ParaWordNo=987",row[5])
            self.assertEqual(conn.execute("SELECT written,reading FROM meanings WHERE reading='かな'").fetchone(),("かな","かな"))
            self.assertEqual(conn.execute("SELECT value FROM metadata WHERE key='review.sha256'").fetchone()[0],hashlib.sha256(reviews.read_bytes()).hexdigest())
            self.assertTrue(conn.execute("SELECT value FROM metadata WHERE key='source.krdict.license_url'").fetchone()[0])
            self.assertEqual(stat.S_IMODE(output.stat().st_mode),0o644)
            conn.close()


if __name__ == "__main__":
    unittest.main()
