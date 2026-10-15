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
| <img src="docs/screenshots/highlight.png" width="200"> | <img src="docs/screenshots/detail.png" width="200"> | <img src="docs/screenshots/vocabulary.png" width="200"> | <img src="docs/screenshots/quiz.png" width="200"> |

## 主な機能

- **スキャン**: カメラや写真からテキストを認識して単語に分け、意味・読み・ハングル表記の一覧を表示します。縦書きにも対応し、指でなぞった範囲だけを切り取って認識することもできます。
- **領域ハイライト**: 一覧の単語をタップすると写真上の該当位置に枠と吹き出しが表示され、吹き出しをタップすると詳細画面に移動します。
- **詳細**: 表記、韓国語の意味、ハングル表記の読み、例文、漢字の読みパターンを表示します。単語帳への保存はユーザーが選んだときだけ行います。
- **単語帳**: 保存した単語の閲覧と削除（スワイプ・一括選択）ができます。単語を撮った元の写真に戻ることができ、辞書検索もここから行います。
- **クイズ**: 単語帳から 4 択問題（単語→意味、意味→単語）を出題します。保存した単語から抽出した漢字の読みパターンを使い、初めて見る単語の読みを推測する問題もあります。
- **スキャン履歴**: 過去のスキャン結果をもう一度開けます。

## 認識パイプライン

```
写真 → OCR(Vision) → 単語分割 → 辞書検索(JMdict) → 韓国語の意味生成(キャッシュ) → かな→ハングル変換
```

- **OCR**: iOS 26 では `RecognizeDocumentsRequest` で縦書きまで読み取り、それ以前は `VNRecognizeTextRequest` を使います。
- **単語分割**: 設定で 3 つのモードから選びます。
  | モード | 方式 | ネットワーク |
  |---|---|---|
  | 辞書 | 同梱の JMdict にある単語を基準に分割 | なし |
  | オンデバイス AI | Foundation Models で辞書にない固有名詞・複合語も分割 | なし |
  | ChatGPT | ユーザー自身の OpenAI API キーで分割と意味生成 | あり |
- **韓国語の意味**: 生成した意味は SwiftData にキャッシュし、一度見た単語ではモデルを再度呼び出しません。生成できない場合は JMdict の英語の意味を表示します。
- **ハングル表記**: LLM を使わず、かな→ハングルの対応表で決まったルールどおりに変換します。

## API キーとプライバシー

- アプリにもこのリポジトリにも API キーは含まれていません。ChatGPT モードはユーザーが自分で入力したキーでのみ動作します。
- キーは Keychain に `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 属性で保存され、他の端末には移行されません。保存直後に画面の状態から平文を消し、リクエストのたびに Keychain から読み出して HTTPS の `Authorization` ヘッダーでのみ送信します。URL やログには残しません。
- 端末の外に出るデータは、ChatGPT モードで送る**認識済みテキスト**だけです。写真は送信しません。

## プロジェクト構成

```
Kanjiyomi/
├── Features/       # 画面単位 (Scan, WordDetail, Vocabulary, Search, Quiz, Settings)
├── Services/       # OCR, 単語分割, 辞書, 意味生成, OpenAI, Keychain
│   └── Kanji/      # 漢字抽出, 音読み・訓読み分類, 読みの対応付け, パターン検出, 推測クイズ生成
├── Models/         # SwiftData モデル (VocabWord, WordCache, ScanRecord …)
├── DesignSystem/   # 色・タイポグラフィ・共通コンポーネント
└── Resources/      # jmdict.sqlite (Git LFS)
tools/              # 辞書 DB を作る Python スクリプト
KanjiyomiTests/     # かな変換, 範囲選択, 漢字パターンの単体テスト
```

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

## データの出典とライセンス

- [JMdict](https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project), [KANJIDIC2](https://www.edrdg.org/wiki/index.php/KANJIDIC_Project): © Electronic Dictionary Research and Development Group. [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) に基づいて使用しており、このデータから作った `jmdict.sqlite` も同じライセンスに従います。
- [Unihan Database](https://www.unicode.org/charts/unihan.html): © Unicode, Inc. [Unicode License](https://www.unicode.org/license.txt) に基づいて使用しています。
