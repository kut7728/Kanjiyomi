#!/usr/bin/env python3
"""Augment the bundled JMdict SQLite with kanji pattern-learning tables.

Adds:
  kanji_meta(kanji, hanja_ko, on_readings, kun_readings, is_irregular_prone)
  kanji_index(kanji, surface, reading, pos, gloss)
  irregular_words(surface, reading, reason)

Uses the existing entries table for the inverted index. Readings and Korean
hanja sounds come from KANJIDIC2 + Unihan when available, plus a fallback
set so the feature works without a network.
"""

from __future__ import annotations

import gzip
import os
import sqlite3
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
DB_PATH = os.path.join(REPO_ROOT, "Kanjiyomi", "Resources", "jmdict.sqlite")
CACHE_DIR = os.path.join(SCRIPT_DIR, ".cache")

KANJIDIC_URL = "http://www.edrdg.org/kanjidic/kanjidic2.xml.gz"
UNIHAN_URL = "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip"

IRREGULAR = [
    ("今日", "きょう", "jukujikun"),
    ("明日", "あした", "jukujikun"),
    ("明日", "あす", "jukujikun"),
    ("昨日", "きのう", "jukujikun"),
    ("大人", "おとな", "jukujikun"),
    ("一人", "ひとり", "jukujikun"),
    ("二人", "ふたり", "jukujikun"),
    ("為替", "かわせ", "jukujikun"),
    ("梅雨", "つゆ", "jukujikun"),
    ("今朝", "けさ", "jukujikun"),
    ("下手", "へた", "jukujikun"),
    ("上手", "じょうず", "ateji-like"),
    ("土産", "みやげ", "jukujikun"),
    ("河岸", "かし", "jukujikun"),
    ("七夕", "たなばた", "jukujikun"),
    ("八百屋", "やおや", "jukujikun"),
]

# kanji -> (hanja_ko, on_csv, kun_csv)
FALLBACK: dict[str, tuple[str, str, str]] = {
    "一": ("일", "いち/いつ", "ひと"),
    "二": ("이", "に", "ふた"),
    "人": ("인", "じん/にん", "ひと"),
    "大": ("대", "だい/たい", "おお"),
    "日": ("일", "にち/じつ", "ひ/か"),
    "今": ("금", "こん/きん", "いま"),
    "国": ("국", "こく", "くに"),
    "学": ("학", "がく", "まな"),
    "校": ("교", "こう", ""),
    "生": ("생", "せい/しょう", "い/う"),
    "先": ("선", "せん", "さき"),
    "年": ("년", "ねん", "とし"),
    "時": ("시", "じ", "とき"),
    "間": ("간", "かん/けん", "あいだ/ま"),
    "分": ("분", "ぶん/ふん", "わ"),
    "新": ("신", "しん", "あたら/あら"),
    "安": ("안", "あん", "やす"),
    "経": ("경", "けい/きょう", "へ/た"),
    "済": ("제", "さい/せい", "す"),
    "験": ("험", "けん/げん", ""),
    "営": ("영", "えい", "いとな"),
    "路": ("로", "ろ", "じ"),
    "書": ("서", "しょ", "か"),
    "類": ("류", "るい", ""),
    "店": ("점", "てん", "みせ"),
    "読": ("독", "どく/とく", "よ"),
    "語": ("어", "ご", "かた"),
    "文": ("문", "ぶん/もん", "ふみ"),
    "字": ("자", "じ", ""),
    "漢": ("한", "かん", ""),
    "和": ("화", "わ", "やわ"),
    "会": ("회", "かい", "あ"),
    "社": ("사", "しゃ", "やしろ"),
    "会": ("회", "かい", "あ"),
    "計": ("계", "けい", "はか"),
    "画": ("화", "が/かく", ""),
    "電": ("전", "でん", ""),
    "話": ("화", "わ", "はな"),
    "見": ("견", "けん", "み"),
    "行": ("행", "こう/ぎょう/あん", "い/ゆ/おこな"),
    "来": ("래", "らい", "く/きた"),
    "出": ("출", "しゅつ", "で/だ"),
    "入": ("입", "にゅう", "はい/い"),
    "上": ("상", "じょう", "うえ/あ"),
    "下": ("하", "か/げ", "した/さ/くだ"),
    "中": ("중", "ちゅう", "なか"),
    "外": ("외", "がい", "そと/はず"),
    "前": ("전", "ぜん", "まえ"),
    "後": ("후", "ご/こう", "あと/うし"),
    "右": ("우", "う/ゆう", "みぎ"),
    "左": ("좌", "さ", "ひだり"),
    "東": ("동", "とう", "ひがし"),
    "西": ("서", "せい/さい", "にし"),
    "南": ("남", "なん", "みなみ"),
    "北": ("북", "ほく", "きた"),
    "高": ("고", "こう", "たか"),
    "小": ("소", "しょう", "ちい/こ"),
    "長": ("장", "ちょう", "なが"),
    "短": ("단", "たん", "みじか"),
    "明": ("명", "めい/みょう", "あか/あき"),
    "暗": ("암", "あん", "くら"),
    "白": ("백", "はく/びゃく", "しろ"),
    "黒": ("흑", "こく", "くろ"),
    "赤": ("적", "せき", "あか"),
    "青": ("청", "せい/しょう", "あお"),
    "金": ("금", "きん/こん", "かね"),
    "銀": ("은", "ぎん", ""),
    "円": ("원", "えん", "まる"),
    "水": ("수", "すい", "みず"),
    "火": ("화", "か", "ひ"),
    "木": ("목", "もく/ぼく", "き"),
    "土": ("토", "ど/と", "つち"),
    "天": ("천", "てん", "あま"),
    "空": ("공", "くう", "そら/あ"),
    "山": ("산", "さん", "やま"),
    "川": ("천", "せん", "かわ"),
    "海": ("해", "かい", "うみ"),
    "雨": ("우", "う", "あめ"),
    "雪": ("설", "せつ", "ゆき"),
    "風": ("풍", "ふう/ふ", "かぜ"),
    "気": ("기", "き/け", ""),
    "力": ("력", "りょく/りき", "ちから"),
    "手": ("수", "しゅ", "て"),
    "足": ("족", "そく", "あし"),
    "目": ("목", "もく", "め"),
    "口": ("구", "こう/く", "くち"),
    "耳": ("이", "じ", "みみ"),
    "心": ("심", "しん", "こころ"),
    "思": ("사", "し", "おも"),
    "知": ("지", "ち", "し"),
    "考": ("고", "こう", "かんが"),
    "言": ("언", "げん/ごん", "い/こと"),
    "話": ("화", "わ", "はな"),
    "聞": ("문", "ぶん/もん", "き"),
    "食": ("식", "しょく/じき", "た/く"),
    "飲": ("음", "いん", "の"),
    "買": ("매", "ばい", "か"),
    "売": ("매", "ばい", "う"),
    "持": ("지", "じ", "も"),
    "待": ("대", "たい", "ま"),
    "立": ("립", "りつ", "た"),
    "座": ("좌", "ざ", "すわ"),
    "休": ("휴", "きゅう", "やす"),
    "寝": ("침", "しん", "ね"),
    "起": ("기", "き", "お"),
    "開": ("개", "かい", "ひら/あ"),
    "閉": ("폐", "へい", "し"),
    "始": ("시", "し", "はじ"),
    "終": ("종", "しゅう", "お"),
    "作": ("작", "さく/さ", "つく"),
    "使": ("사", "し", "つか"),
    "用": ("용", "よう", "もち"),
    "事": ("사", "じ/ず", "こと"),
    "物": ("물", "ぶつ/もつ", "もの"),
    "者": ("자", "しゃ", "もの"),
    "方": ("방", "ほう", "かた"),
    "所": ("소", "しょ", "ところ"),
    "場": ("장", "じょう", "ば"),
    "所": ("소", "しょ", "ところ"),
    "家": ("가", "か/け", "いえ/や"),
    "族": ("족", "ぞく", ""),
    "父": ("부", "ふ", "ちち"),
    "母": ("모", "ぼ", "はは"),
    "子": ("자", "し/す", "こ"),
    "女": ("녀", "じょ/にょ", "おんな"),
    "男": ("남", "だん/なん", "おとこ"),
    "友": ("우", "ゆう", "とも"),
    "名": ("명", "めい/みょう", "な"),
    "正": ("정", "せい/しょう", "ただ"),
    "同": ("동", "どう", "おな"),
    "自": ("자", "じ/し", "みずか"),
    "他": ("타", "た", "ほか"),
    "全": ("전", "ぜん", "まった"),
    "部": ("부", "ぶ", ""),
    "公": ("공", "こう", "おおやけ"),
    "私": ("사", "し", "わたくし/わたし"),
    "世": ("세", "せい/せ", "よ"),
    "界": ("계", "かい", ""),
    "問": ("문", "もん", "と"),
    "題": ("제", "だい", ""),
    "答": ("답", "とう", "こた"),
    "意": ("의", "い", ""),
    "味": ("미", "み", "あじ"),
    "感": ("감", "かん", ""),
    "情": ("정", "じょう", "なさ"),
    "愛": ("애", "あい", ""),
    "好": ("호", "こう", "す/この"),
    "悪": ("악", "あく", "わる"),
    "強": ("강", "きょう/ごう", "つよ"),
    "弱": ("약", "じゃく", "よわ"),
    "多": ("다", "た", "おお"),
    "少": ("소", "しょう", "すく/すこ"),
    "早": ("조", "そう", "はや"),
    "遅": ("지", "ち", "おそ"),
    "近": ("근", "きん", "ちか"),
    "遠": ("원", "えん", "とお"),
    "広": ("광", "こう", "ひろ"),
    "狭": ("협", "きょう", "せま"),
    "深": ("심", "しん", "ふか"),
    "浅": ("천", "せん", "あさ"),
    "重": ("중", "じゅう/ちょう", "おも/かさ"),
    "軽": ("경", "けい", "かる"),
    "美": ("미", "び", "うつく"),
    "楽": ("락", "らく/がく", "たの"),
    "苦": ("고", "く", "くる/にが"),
    "幸": ("행", "こう", "しあわ/さいわ"),
    "不": ("불", "ふ/ぶ", ""),
    "無": ("무", "む/ぶ", "な"),
    "有": ("유", "ゆう/う", "あ"),
    "在": ("재", "ざい", "あ"),
    "存": ("존", "そん/ぞん", ""),
    "現": ("현", "げん", "あらわ"),
    "実": ("실", "じつ", "み/みの"),
    "確": ("확", "かく", "たし"),
    "定": ("정", "てい/じょう", "さだ"),
    "必": ("필", "ひつ", "かなら"),
    "要": ("요", "よう", "い"),
    "必": ("필", "ひつ", "かなら"),
    "可": ("가", "か", ""),
    "能": ("능", "のう", ""),
    "可": ("가", "か", ""),
    "得": ("득", "とく", "え/う"),
    "失": ("실", "しつ", "うしな"),
    "変": ("변", "へん", "か"),
    "化": ("화", "か/け", "ば"),
    "進": ("진", "しん", "すす"),
    "退": ("퇴", "たい", "しりぞ"),
    "加": ("가", "か", "くわ"),
    "減": ("감", "げん", "へ"),
    "増": ("증", "ぞう", "ふ"),
    "比": ("비", "ひ", "くら"),
    "較": ("교", "かく", ""),
    "対": ("대", "たい", ""),
    "関": ("관", "かん", "せき"),
    "係": ("계", "けい", "かか"),
    "連": ("연", "れん", "つら/つ"),
    "続": ("속", "ぞく", "つづ"),
    "結": ("결", "けつ", "むす"),
    "果": ("과", "か", "は"),
    "報": ("보", "ほう", "むく"),
    "告": ("고", "こく", "つ"),
    "知": ("지", "ち", "し"),
    "識": ("식", "しき", ""),
    "記": ("기", "き", "しる"),
    "録": ("록", "ろく", ""),
    "録": ("록", "ろく", ""),
    "表": ("표", "ひょう", "おもて/あらわ"),
    "示": ("시", "じ/し", "しめ"),
    "発": ("발", "はつ/ほつ", ""),
    "表": ("표", "ひょう", "おもて"),
    "現": ("현", "げん", "あらわ"),
    "研": ("연", "けん", "と"),
    "究": ("구", "きゅう", "きわ"),
    "調": ("조", "ちょう", "しら"),
    "査": ("사", "さ", ""),
    "試": ("시", "し", "こころ/ため"),
    "験": ("험", "けん", ""),
    "験": ("험", "けん/げん", ""),
    "成": ("성", "せい/じょう", "な"),
    "功": ("공", "こう", ""),
    "敗": ("패", "はい", "やぶ"),
    "勝": ("승", "しょう", "か"),
    "負": ("부", "ふ", "ま/お"),
    "戦": ("전", "せん", "いくさ/たたか"),
    "争": ("쟁", "そう", "あらそ"),
    "和": ("화", "わ", "やわ"),
    "平": ("평", "へい/びょう", "たい"),
    "安": ("안", "あん", "やす"),
    "危": ("위", "き", "あぶ/あや"),
    "険": ("험", "けん", "けわ"),
    "保": ("보", "ほ", "たも"),
    "護": ("호", "ご", "まも"),
    "守": ("수", "しゅ/す", "まも"),
    "攻": ("공", "こう", "せ"),
    "撃": ("격", "げき", "う"),
    "制": ("제", "せい", ""),
    "度": ("도", "ど/たく", "たび"),
    "回": ("회", "かい", "まわ"),
    "数": ("수", "すう/す", "かず/かぞ"),
    "量": ("량", "りょう", "はか"),
    "質": ("질", "しつ/しち", ""),
    "点": ("점", "てん", ""),
    "線": ("선", "せん", ""),
    "面": ("면", "めん", "おも/おもて"),
    "側": ("측", "そく", "がわ"),
    "内": ("내", "ない", "うち"),
    "外": ("외", "がい", "そと"),
    "向": ("향", "こう", "む"),
    "通": ("통", "つう", "とお/かよ"),
    "過": ("과", "か", "す"),
    "道": ("도", "どう", "みち"),
    "路": ("로", "ろ", "じ"),
    "駅": ("역", "えき", ""),
    "車": ("차", "しゃ", "くるま"),
    "乗": ("승", "じょう", "の"),
    "降": ("강", "こう", "お/ふ"),
    "飛": ("비", "ひ", "と"),
    "走": ("주", "そう", "はし"),
    "歩": ("보", "ほ/ぶ", "ある/あゆ"),
    "停": ("정", "てい", "と"),
    "止": ("지", "し", "と"),
    "動": ("동", "どう", "うご"),
    "作": ("작", "さく/さ", "つく"),
    "働": ("동", "どう", "はたら"),
    "業": ("업", "ぎょう/ごう", ""),
    "職": ("직", "しょく", ""),
    "仕": ("사", "し", ""),
    "事": ("사", "じ", "こと"),
    "員": ("원", "いん", ""),
    "客": ("객", "きゃく", ""),
    "主": ("주", "しゅ/す", "ぬし/おも"),
    "義": ("의", "ぎ", ""),
    "務": ("무", "む", "つと"),
    "責": ("책", "せき", "せ"),
    "任": ("임", "にん", "まか"),
    "権": ("권", "けん/ごん", ""),
    "利": ("리", "り", "き"),
    "益": ("익", "えき", ""),
    "害": ("해", "がい", ""),
    "損": ("손", "そん", "そこ"),
    "得": ("득", "とく", "え"),
    "費": ("비", "ひ", "つい"),
    "資": ("자", "し", ""),
    "産": ("산", "さん", "う"),
    "業": ("업", "ぎょう", ""),
    "商": ("상", "しょう", ""),
    "品": ("품", "ひん", "しな"),
    "価": ("가", "か", "あたい"),
    "格": ("격", "かく", ""),
    "税": ("세", "ぜい", ""),
    "収": ("수", "しゅう", "おさ"),
    "支": ("지", "し", "ささ"),
    "払": ("불", "ふつ", "はら"),
    "貸": ("대", "たい", "か"),
    "借": ("차", "しゃく", "か"),
    "返": ("반", "へん", "かえ"),
    "送": ("송", "そう", "おく"),
    "受": ("수", "じゅ", "う"),
    "取": ("취", "しゅ", "と"),
    "与": ("여", "よ", "あた"),
    "渡": ("도", "と", "わた"),
    "交": ("교", "こう", "まじ/か"),
    "換": ("환", "かん", "か"),
    "代": ("대", "だい/たい", "か/よ"),
    "表": ("표", "ひょう", "おもて"),
    "示": ("시", "じ", "しめ"),
    "説": ("설", "せつ", "と"),
    "明": ("명", "めい", "あか"),
    "解": ("해", "かい/げ", "と"),
    "決": ("결", "けつ", "き"),
    "選": ("선", "せん", "えら"),
    "択": ("택", "たく", ""),
    "判": ("판", "はん/ばん", "わか"),
    "断": ("단", "だん", "ことわ/た"),
    "許": ("허", "きょ", "ゆる"),
    "可": ("가", "か", ""),
    "否": ("부", "ひ", "いな"),
    "認": ("인", "にん", "みと"),
    "証": ("증", "しょう", ""),
    "確": ("확", "かく", "たし"),
    "信": ("신", "しん", ""),
    "頼": ("뢰", "らい", "たよ/たの"),
    "約": ("약", "やく", ""),
    "束": ("속", "そく", "たば"),
    "守": ("수", "しゅ", "まも"),
    "破": ("파", "は", "やぶ"),
    "規": ("규", "き", ""),
    "則": ("칙", "そく", ""),
    "法": ("법", "ほう", ""),
    "律": ("률", "りつ", ""),
    "令": ("령", "れい", ""),
    "政": ("정", "せい", "まつりごと"),
    "治": ("치", "じ/ち", "おさ"),
    "府": ("부", "ふ", ""),
    "県": ("현", "けん", ""),
    "市": ("시", "し", "いち"),
    "区": ("구", "く", ""),
    "町": ("정", "ちょう", "まち"),
    "村": ("촌", "そん", "むら"),
    "民": ("민", "みん", "たみ"),
    "衆": ("중", "しゅう", ""),
    "議": ("의", "ぎ", ""),
    "会": ("회", "かい", "あ"),
    "院": ("원", "いん", ""),
    "党": ("당", "とう", ""),
    "首": ("수", "しゅ", "くび"),
    "相": ("상", "そう/しょう", "あい"),
    "官": ("관", "かん", ""),
    "吏": ("리", "り", ""),
    "軍": ("군", "ぐん", ""),
    "隊": ("대", "たい", ""),
    "兵": ("병", "へい/ひょう", ""),
    "器": ("기", "き", "うつわ"),
    "械": ("계", "かい", ""),
    "機": ("기", "き", "はた"),
    "械": ("계", "かい", ""),
    "工": ("공", "こう/く", ""),
    "技": ("기", "ぎ", "わざ"),
    "術": ("술", "じゅつ", ""),
    "科": ("과", "か", ""),
    "医": ("의", "い", ""),
    "病": ("병", "びょう", "や"),
    "院": ("원", "いん", ""),
    "薬": ("약", "やく", "くすり"),
    "体": ("체", "たい/てい", "からだ"),
    "頭": ("두", "とう/ず", "あたま"),
    "顔": ("안", "がん", "かお"),
    "声": ("성", "せい/しょう", "こえ"),
    "色": ("색", "しょく/しき", "いろ"),
    "形": ("형", "けい/ぎょう", "かた/かたち"),
    "式": ("식", "しき", ""),
    "様": ("양", "よう", "さま"),
    "態": ("태", "たい", "わざ"),
    "状": ("상", "じょう", ""),
    "況": ("황", "きょう", ""),
    "景": ("경", "けい", ""),
    "観": ("관", "かん", "み"),
    "光": ("광", "こう", "ひかり/ひか"),
    "影": ("영", "えい", "かげ"),
    "音": ("음", "おん/いん", "おと/ね"),
    "楽": ("악", "がく/らく", "たの"),
    "歌": ("가", "か", "うた"),
    "詩": ("시", "し", ""),
    "画": ("화", "が", ""),
    "絵": ("회", "かい", "え"),
    "写": ("사", "しゃ", "うつ"),
    "真": ("진", "しん", "ま"),
    "実": ("실", "じつ", "み"),
    "虚": ("허", "きょ", "むな"),
    "偽": ("위", "ぎ", "いつわ"),
    "正": ("정", "せい", "ただ"),
    "誤": ("오", "ご", "あやま"),
    "残": ("잔", "ざん", "のこ"),
    "余": ("여", "よ", "あま"),
    "他": ("타", "た", "ほか"),
    "各": ("각", "かく", "おのおの"),
    "毎": ("매", "まい", ""),
    "次": ("차", "じ/し", "つぎ/つ"),
    "初": ("초", "しょ", "はじ/はつ"),
    "終": ("종", "しゅう", "お"),
    "末": ("말", "まつ/ばつ", "すえ"),
    "未": ("미", "み", "いま"),
    "既": ("기", "き", "すで"),
    "再": ("재", "さい", "ふたた"),
    "復": ("복", "ふく", "また"),
    "単": ("단", "たん", ""),
    "複": ("복", "ふく", ""),
    "簡": ("간", "かん", ""),
    "難": ("난", "なん", "むずか/かた"),
    "易": ("이", "い/えき", "やさ"),
    "特": ("특", "とく", ""),
    "別": ("별", "べつ", "わか"),
    "共": ("공", "きょう", "とも"),
    "独": ("독", "どく", "ひと"),
    "個": ("개", "こ", ""),
    "各": ("각", "かく", ""),
    "普": ("보", "ふ", ""),
    "通": ("통", "つう", "とお"),
    "常": ("상", "じょう", "つね/とこ"),
    "非": ("비", "ひ", ""),
}


def katakana_to_hiragana(text: str) -> str:
    out = []
    for ch in text:
        code = ord(ch)
        if 0x30A1 <= code <= 0x30F6:
            out.append(chr(code - 0x60))
        else:
            out.append(ch)
    return "".join(out)


def download(url: str, dest: str) -> bool:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print("Using cached", dest)
        return True
    print("Downloading", url)
    try:
        urllib.request.urlretrieve(url, dest)
        return True
    except Exception as exc:
        print("WARN: download failed:", exc)
        return False


def parse_kanjidic(path: str) -> dict[str, tuple[list[str], list[str]]]:
    result: dict[str, tuple[list[str], list[str]]] = {}
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as fh:
        context = ET.iterparse(fh, events=("end",))
        for _event, elem in context:
            if elem.tag != "character":
                continue
            literal = elem.findtext("literal")
            if not literal:
                elem.clear()
                continue
            ons: list[str] = []
            kuns: list[str] = []
            for reading in elem.findall(".//reading"):
                kind = reading.get("r_type")
                text = (reading.text or "").strip()
                if not text:
                    continue
                text = katakana_to_hiragana(text.replace("-", "").replace(".", ""))
                if kind == "ja_on" and text not in ons:
                    ons.append(text)
                elif kind == "ja_kun" and text not in kuns:
                    kuns.append(text)
            if ons or kuns:
                result[literal] = (ons, kuns)
            elem.clear()
    return result


def parse_unihan(zip_path: str) -> dict[str, str]:
    hanja: dict[str, str] = {}
    with zipfile.ZipFile(zip_path) as zf:
        name = next((n for n in zf.namelist() if n.endswith("Unihan_Readings.txt")), None)
        if name is None:
            return hanja
        with zf.open(name) as fh:
            for raw in fh:
                line = raw.decode("utf-8", errors="ignore").strip()
                if not line or line.startswith("#") or "\t" not in line:
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    continue
                code, field, value = parts[0], parts[1], parts[2]
                if field not in ("kHangul", "kKorean"):
                    continue
                if not code.startswith("U+"):
                    continue
                character = chr(int(code[2:], 16))
                if character in hanja and field == "kKorean":
                    continue
                syllable = value.split()[0].split(":")[0]
                if field == "kHangul":
                    hanja[character] = syllable
                elif character not in hanja and syllable:
                    if any("가" <= ch <= "힣" for ch in syllable):
                        hanja[character] = syllable
    return hanja


def fallback_meta() -> dict[str, tuple[str, list[str], list[str]]]:
    meta: dict[str, tuple[str, list[str], list[str]]] = {}
    for kanji, (hanja, ons, kuns) in FALLBACK.items():
        if len(kanji) != 1:
            continue
        meta[kanji] = (
            hanja,
            [p for p in ons.split("/") if p],
            [p for p in kuns.split("/") if p],
        )
    return meta


def merge_meta(
    fallback: dict[str, tuple[str, list[str], list[str]]],
    kanjidic: dict[str, tuple[list[str], list[str]]],
    unihan: dict[str, str],
) -> dict[str, tuple[str, list[str], list[str], int]]:
    keys = set(fallback) | set(unihan)
    merged: dict[str, tuple[str, list[str], list[str], int]] = {}
    irregular_prone = set("今人大小下手土産河岸七夕")
    for kanji in keys:
        fb = fallback.get(kanji)
        kd = kanjidic.get(kanji)
        hanja = unihan.get(kanji, fb[0] if fb else "")
        ons = kd[0] if kd else (fb[1] if fb else [])
        kuns = kd[1] if kd else (fb[2] if fb else [])
        if not hanja and not ons and not kuns:
            continue
        merged[kanji] = (hanja, ons, kuns, 1 if kanji in irregular_prone else 0)
    return merged


def used_kanji(conn: sqlite3.Connection) -> set[str]:
    used: set[str] = set()
    for (surface,) in conn.execute(
        "SELECT kanji FROM entries WHERE length(kanji) BETWEEN 2 AND 3"
    ):
        for ch in surface or "":
            if 0x4E00 <= ord(ch) <= 0x9FFF:
                used.add(ch)
    return used


def rebuild_tables(conn: sqlite3.Connection, meta: dict[str, tuple[str, list[str], list[str], int]]) -> None:
    cur = conn.cursor()
    cur.executescript(
        """
        DROP TABLE IF EXISTS kanji_meta;
        DROP TABLE IF EXISTS kanji_index;
        DROP TABLE IF EXISTS irregular_words;
        CREATE TABLE kanji_meta (
            kanji TEXT PRIMARY KEY,
            hanja_ko TEXT NOT NULL DEFAULT '',
            on_readings TEXT NOT NULL DEFAULT '',
            kun_readings TEXT NOT NULL DEFAULT '',
            is_irregular_prone INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE kanji_index (
            kanji TEXT NOT NULL,
            surface TEXT NOT NULL,
            reading TEXT NOT NULL,
            pos TEXT NOT NULL DEFAULT '',
            gloss TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (kanji, surface, reading)
        );
        CREATE INDEX idx_kanji_index_kanji ON kanji_index(kanji);
        CREATE TABLE irregular_words (
            surface TEXT NOT NULL,
            reading TEXT NOT NULL,
            reason TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (surface, reading)
        );
        """
    )

    cur.executemany(
        "INSERT INTO kanji_meta(kanji, hanja_ko, on_readings, kun_readings, is_irregular_prone) VALUES (?, ?, ?, ?, ?)",
        [
            (kanji, hanja, "/".join(ons), "/".join(kuns), flag)
            for kanji, (hanja, ons, kuns, flag) in meta.items()
        ],
    )
    cur.executemany(
        "INSERT INTO irregular_words(surface, reading, reason) VALUES (?, ?, ?)",
        IRREGULAR,
    )

    allowed = set(meta)
    rows = cur.execute(
        """
        SELECT kanji, reading, pos, gloss FROM entries
        WHERE length(kanji) BETWEEN 2 AND 3
        """
    ).fetchall()

    best: dict[str, tuple[str, str, str]] = {}
    for surface, reading, pos, gloss in rows:
        if not surface or not reading:
            continue
        current = best.get(surface)
        if current is None or len(reading) < len(current[0]):
            best[surface] = (reading, pos or "", gloss or "")

    index_rows = []
    seen = set()
    for surface, (reading, pos, gloss) in best.items():
        chars = [ch for ch in surface if ch in allowed]
        if not chars:
            continue
        for ch in chars:
            key = (ch, surface, reading)
            if key in seen:
                continue
            seen.add(key)
            index_rows.append((ch, surface, reading, pos, gloss))

    cur.executemany(
        "INSERT INTO kanji_index(kanji, surface, reading, pos, gloss) VALUES (?, ?, ?, ?, ?)",
        index_rows,
    )
    conn.commit()
    print(
        "kanji_meta {}  kanji_index {}  irregular {}".format(
            len(meta), len(index_rows), len(IRREGULAR)
        )
    )


def main() -> int:
    if not os.path.exists(DB_PATH):
        print("ERROR: missing", DB_PATH, file=sys.stderr)
        return 1

    os.makedirs(CACHE_DIR, exist_ok=True)
    kanjidic: dict[str, tuple[list[str], list[str]]] = {}
    unihan: dict[str, str] = {}

    kd_path = os.path.join(CACHE_DIR, "kanjidic2.xml.gz")
    if download(KANJIDIC_URL, kd_path):
        try:
            print("Parsing KANJIDIC2 …")
            kanjidic = parse_kanjidic(kd_path)
            print("  {} characters".format(len(kanjidic)))
        except Exception as exc:
            print("WARN: KANJIDIC parse failed:", exc)

    uh_path = os.path.join(CACHE_DIR, "Unihan.zip")
    if download(UNIHAN_URL, uh_path):
        try:
            print("Parsing Unihan …")
            unihan = parse_unihan(uh_path)
            print("  {} hangul readings".format(len(unihan)))
        except Exception as exc:
            print("WARN: Unihan parse failed:", exc)

    print("Writing tables into", DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        used = used_kanji(conn)
        raw = merge_meta(fallback_meta(), kanjidic, unihan)
        # Keep fallback/unihan rows even if unused, plus every compound kanji
        # that has a KANJIDIC reading so alignment still works.
        meta = dict(raw)
        for kanji in used:
            if kanji in meta:
                continue
            kd = kanjidic.get(kanji)
            if not kd:
                continue
            meta[kanji] = ("", kd[0], kd[1], 0)
        print("kanji in 2-3 char words:", len(used), "meta rows:", len(meta))
        rebuild_tables(conn, meta)
        conn.execute("VACUUM")
    finally:
        conn.close()
    size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
    print("Done: {:.1f} MB".format(size_mb))
    return 0


if __name__ == "__main__":
    sys.exit(main())
