# Kanjiyomi

[![Test](https://github.com/kut7728/Kanjiyomi/actions/workflows/test.yml/badge.svg)](https://github.com/kut7728/Kanjiyomi/actions/workflows/test.yml)

[한국어](README.md) | 日本語

チラシや看板の写真に写った日本語を単語ごとに認識し、意味とハングル表記の読みを表示する iOS アプリです。
撮った単語を単語帳に集め、クイズと漢字の読みパターンで復習できます。

- SwiftUI · SwiftData · Vision · NaturalLanguage · Foundation Models
- iOS 18 以上（オンデバイス AI・縦書き文書認識は iOS 26 以上の対応端末のみ）
- ログイン不要、データはすべて端末内に保存

| スキャン・ハイライト | 単語の詳細 | 単語帳 | クイズ |
|---|---|---|---|
| <img src="docs/03-design/screenshots/highlight.png" width="200"> | <img src="docs/03-design/screenshots/detail.png" width="200"> | <img src="docs/03-design/screenshots/vocabulary.png" width="200"> | <img src="docs/03-design/screenshots/quiz.png" width="200"> |

## 主な機能

- **スキャン**: カメラやアルバムの写真から日本語を読み取って単語に分け、意味・読み・ハングル表記の読みを表示します。iOS 26 以上では縦書きも読み取ります。
- **ハイライト**: 単語をタップすると写真がその位置に拡大され、枠と吹き出しが表示されます。指で範囲をなぞって、その中の単語だけを見ることもできます。
- **単語分割の 3 モード**: 辞書（オフライン）/ オンデバイス AI（Foundation Models）/ ChatGPT（ユーザー自身の API キー）。
- **オフラインの韓国語訳**: 韓国語基礎辞典とウィクショナリーの一部の項目を同梱しています。未収録語は対応端末の AI で補い、生成できない場合は英語の意味を表示します。
- **単語帳・クイズ**: 保存した単語で 4 択問題を解き、保存した単語から集めた漢字の読みパターンで初めて見る単語の読みを推測します。

API キーはアプリにもリポジトリにも含まれておらず、ユーザーが入力したキーを端末の Keychain にだけ保存します。端末の外に出るのは ChatGPT モードで送る認識済みの文字と単語情報（読み・英語の意味）だけで、写真は送信しません。

## 仕様ドキュメント

企画から画面・技術・テスト・リリース準備までの仕様は [docs/](docs/README.md) にあります（韓国語）。

## ビルド

1. Git LFS をインストールしてから clone します。辞書 DB（`jmdict.sqlite`）は LFS で管理しています。
   ```sh
   git lfs install
   git clone https://github.com/kut7728/Kanjiyomi.git
   ```
2. `Kanjiyomi.xcodeproj` を開き、Signing で自分の Team を選んで実行します。

辞書 DB を自分で作る場合は次を実行します。EDRDG と Unicode から元データをダウンロードします。

```sh
python3 tools/build_dict.py          # JMdict → entries テーブル
python3 tools/build_kanji_layer.py   # KANJIDIC2 + Unihan → 漢字パターンテーブル
```


韓国語の補助辞書は別の `korean.sqlite` として同梱済みです。再生成する場合は、スクリプトに記録したバージョン・SHA-256 と一致する元データを用意します。

```sh
python3 tools/build_korean_dict.py \
  --krdict /path/to/krdict-json.zip \
  --wiktionary /path/to/kowiktionary.jsonl.gz \
  --jmdict /path/to/JMdict.gz
python3 -m unittest discover -s tools/tests -p 'test_*.py'
```

配布先の内容は最新版に変わる場合があります。ハッシュが異なる場合は既存 DB を残して中止します。更新時は原本のハッシュと検証記録も更新してください。対応付けの基準と標本検証の限界は[調査記録](docs/02-research/README.md)にあります。

## データの出典とライセンス

- [JMdict](https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project), [KANJIDIC2](https://www.edrdg.org/wiki/index.php/KANJIDIC_Project): © Electronic Dictionary Research and Development Group. [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) に基づいて使用しており、このデータから作った `jmdict.sqlite` も同じライセンスに従います。
- [韓国語基礎辞典](https://krdict.korean.go.kr/): © 国立国語院。[CC BY-SA 2.0 KR](https://creativecommons.org/licenses/by-sa/2.0/kr/)。日本語の対訳語と英語訳を照合して韓国語の見出し語を対応付けました。
- [韓国語版ウィクショナリー](https://ko.wiktionary.org/)の投稿者、[Kaikki / Wiktextract](https://kaikki.org/kowiktionary/): [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。日本語項目の韓国語の意味を抽出しました。
- 韓国語の補助データ [`korean.sqlite`](Kanjiyomi/Resources/korean.sqlite) は通常の Git で配布します。表記・読みの正規化、重複と不確かな対応の除外を行いました。各項目の出典 URL・識別子・元のライセンス、原本の日付・ハッシュは DB 内に記録しています。データには各出典のライセンスが適用され、下記のソースコードの All rights reserved は適用されません。
- [Unihan Database](https://www.unicode.org/charts/unihan.html): © Unicode, Inc. [Unicode License](https://www.unicode.org/license.txt) に基づいて使用しています。

## ソースコードのライセンス

このリポジトリのソースコードは © 2026 Kim Ui Taek, All rights reserved です。閲覧・参考は自由ですが、許可なく複製・配布・改変することはできません。辞書データは上記の元のライセンスに従います。

プライバシーポリシー: https://kut7728.github.io/Kanjiyomi/privacy/#ja · お問い合わせ: kut.support@gmail.com
