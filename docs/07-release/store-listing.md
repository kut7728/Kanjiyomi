# 스토어 등록 정보

[07 출시 준비](README.md) · 글자 수 제한은 App Store Connect에서 다시 확인 (미검증)

기본 언어는 한국어입니다. 일본 스토어용으로 일본어 현지화를 하나 더 둡니다. 앱 화면은 한국어뿐이므로, 일본어 설명에도 그 사실을 적습니다.

## 공통

| 항목 | 값 |
|---|---|
| Bundle ID | `my.kanji.app` |
| 가격 | 무료 |
| 국가 | 대한민국, 일본 |
| 카테고리 | 교육 (보조: 참고) — 기본값 (검토 필요) |
| 연령 등급 | 설문 결과에 따름. 예상 4+ (미검증) |
| 지원 URL | https://kut7728.github.io/Kanjiyomi/support/ |
| 개인정보 처리방침 URL | https://kut7728.github.io/Kanjiyomi/privacy/ |
| 저작권 | © 2026 Kim Ui Taek |

## 한국어

**이름** (21자): Kanjiyomi - 일본어 사진 번역

**부제**: 전단지·간판 속 단어 뜻과 발음

**프로모션 문구**: 사진을 찍으면 일본어 단어의 뜻과 한글 발음이 사진 위에 바로 보여요.

**설명**

```
일본 거리의 전단지, 간판, 메뉴판. 사진 한 장이면 어떤 단어인지 바로 알 수 있어요.

■ 사진 속 단어를 바로 짚어 줘요
카메라로 찍거나 앨범에서 고르면 일본어를 단어 단위로 나눠, 뜻·읽기·한글 발음을 보여 줍니다. 목록에서 단어를 누르면 사진 속 그 위치가 확대되어 표시돼요. 세로쓰기도 읽습니다(iOS 26 이상).

■ 필요한 부분만
손가락으로 영역을 그리면 그 안의 단어만 볼 수 있어요.

■ 단어장과 퀴즈
마음에 드는 단어는 단어장에 저장하고, 4지선다 퀴즈로 복습하세요. 단어를 찍었던 사진으로 언제든 돌아갈 수 있어요.

■ 한자 읽기 패턴
経済·経験·経営처럼 같은 한자가 같은 소리로 읽히는 패턴을 모아, 처음 보는 단어의 읽기도 추론해 볼 수 있어요. 한국 한자음(경제·경험)도 함께 보여 줍니다.

■ 인터넷 없이도
글자 인식, 사전 검색, 단어장은 모두 기기 안에서 동작해요. 번들 사전에 수록된 단어는 한국어 뜻도 오프라인으로 보여 줍니다. 미수록 단어는 지원 기기의 AI로 뜻을 만들며, 생성할 수 없으면 영어 뜻을 보여 줍니다. 사진은 기기 밖으로 나가지 않습니다.

■ 더 정확한 뜻이 필요하면 (선택)
본인 OpenAI API 키를 넣으면 ChatGPT로 단어를 나누고 뜻을 만들 수 있어요. 이때만 인식된 글자와 단어 정보가 OpenAI로 전송되며, 요금은 본인 계정에 청구됩니다.

사전 데이터: JMdict, KANJIDIC2 (EDRDG, CC BY-SA 4.0), Unihan (Unicode), 한국어기초사전 (국립국어원, CC BY-SA 2.0 KR), 한국어 위키낱말사전 기여자·Kaikki (CC BY-SA 4.0)
```

**키워드**: 일본어,한자,단어장,사전,여행,일본여행,읽기,발음,간판,메뉴,JLPT,카메라

## 일본어 (日本語)

**이름**: Kanjiyomi - 韓国語で読む日本語 — 기본값 (검토 필요)

**부제**: チラシや看板の単語を韓国語で

**설명**

```
韓国語話者のための日本語スキャンアプリです。アプリの画面は韓国語です。

チラシや看板の写真を撮ると、日本語を単語ごとに分け、韓国語の意味・読み・ハングル表記の発音を表示します。単語をタップすると写真の中の位置が拡大表示されます。

・指でなぞった範囲の単語だけを表示
・単語帳と4択クイズ
・同じ漢字の読みパターンから、初めて見る単語の読みを推測
・文字認識・辞書・単語帳は端末内で動作。収録語の韓国語訳もオフラインで表示します。未収録語は対応端末の AI で補い、生成できない場合は英語の意味を表示します。写真は端末の外に送信しません
・任意: ご自身の OpenAI API キーを入れると ChatGPT で意味を作成(認識した文字と単語情報のみ OpenAI に送信)

辞書データ: JMdict, KANJIDIC2 (EDRDG, CC BY-SA 4.0), Unihan (Unicode), 韓国語基礎辞典 (国立国語院, CC BY-SA 2.0 KR), 韓国語版ウィクショナリーの投稿者・Kaikki (CC BY-SA 4.0)
```

**키워드**: 韓国語,日本語,漢字,単語帳,辞書,スキャン,読み方,ハングル

## 심사 노트 (App Review Information)

```
Kanjiyomi reads Japanese text in photos and shows Korean meanings and pronunciations. The UI is Korean.

- No login is required.
- The core flow works fully on device: Scan tab → "앨범에서 선택" (choose from album) → pick a photo with Japanese text. The default "사전" (dictionary) mode needs no network and no key.
- Bundled Korean meanings are available offline for a subset of dictionary entries. Words without a Korean meaning fall back to AI when available, otherwise English.
- The "AI" mode appears only on devices that support Apple Intelligence (Foundation Models).
- ChatGPT mode is optional. It uses the user's own OpenAI API key, entered in Settings (설정) and stored only in the device Keychain. We do not provide a key and run no server. The privacy section in Settings explains what is sent.
- Dictionary data: JMdict/KANJIDIC2 (CC BY-SA 4.0), Unihan, KRDICT (CC BY-SA 2.0 KR), Korean Wiktionary contributors / Kaikki (CC BY-SA 4.0). Credits: Settings → 오픈소스·라이선스.
```

## 스크린샷

M10에서 스토어 규격으로 찍습니다. 지금 저장소의 [screenshots/](../03-design/screenshots/)는 README용 축소본입니다. 찍을 화면: 스캔 결과(하이라이트), 단어 상세(한자 패턴), 단어장, 퀴즈, 영역 선택.
