//
//  DictionaryService.swift
//  Kanjiyomi
//

import Foundation
import SQLite3

/// Lock-protected so lookups can run off the main actor during recognition.
nonisolated final class DictionaryService: @unchecked Sendable {
    static let shared = DictionaryService()

    private var db: OpaquePointer?
    private let lock = NSLock()
    private var existsCache: [String: Bool] = [:]
    private var kanjiMetaCache: [Character: KanjiMeta]?
    private var irregularCache: Set<String>?

    private init() {
        openDatabase()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() {
        guard let url = Bundle.main.url(forResource: "jmdict", withExtension: "sqlite") else {
            print("[DictionaryService] jmdict.sqlite not found in bundle")
            return
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK {
            db = handle
        } else {
            print("[DictionaryService] Failed to open database")
            if let handle { sqlite3_close(handle) }
        }
    }

    func lookup(surface: String, lemma: String) -> DictionaryEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { return nil }

        if let entry = firstEntry(for: uniqueNonEmpty([surface, lemma])) {
            return entry
        }

        // ご利用 has no entry of its own while 利用 does. The polite prefix adds nothing to
        // the meaning and reads as its own kana, so it is put back in front of the reading.
        for word in uniqueNonEmpty([surface, lemma]) {
            guard let (stem, prefix) = Self.splitPolitePrefix(word),
                  let entry = firstEntry(for: [stem])
            else { continue }
            return DictionaryEntry(
                kanji: entry.kanji,
                reading: entry.reading.isEmpty ? "" : prefix + entry.reading,
                partOfSpeech: entry.partOfSpeech,
                glossEN: entry.glossEN
            )
        }
        return nil
    }

    private func firstEntry(for candidates: [String]) -> DictionaryEntry? {
        for word in candidates {
            if let entry = query(kanji: word) { return entry }
        }
        for word in candidates {
            if let entry = query(reading: word) { return entry }
        }
        return nil
    }

    /// Splits お / ご off a word, but only when enough is left to be a word on its own,
    /// so お茶 and ご飯 are not mistaken for a prefix plus a stem.
    private static func splitPolitePrefix(_ word: String) -> (stem: String, prefix: String)? {
        for prefix in ["お", "ご"] where word.hasPrefix(prefix) && word.count >= 4 {
            return (String(word.dropFirst()), prefix)
        }
        return nil
    }

    /// Fast membership check used by the tokenizer to merge over-split characters.
    func exists(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        if let cached = existsCache[word] { return cached }
        guard let db else { return false }

        let sql = "SELECT 1 FROM entries WHERE kanji = ?1 OR reading = ?1 LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        let ns = word as NSString
        sqlite3_bind_text(stmt, 1, ns.utf8String, -1, nil)
        let found = sqlite3_step(stmt) == SQLITE_ROW
        existsCache[word] = found
        return found
    }

    func search(_ query: String, limit: Int = 40) -> [DictionaryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let hasJapanese = trimmed.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3040...0x30FF).contains(v) || (0x4E00...0x9FFF).contains(v)
        }
        let sql: String
        if hasJapanese {
            sql = """
            SELECT kanji, reading, pos, gloss FROM entries
            WHERE kanji = ?1 OR reading = ?1 OR kanji LIKE ?2 OR reading LIKE ?2
            ORDER BY LENGTH(kanji) LIMIT ?3
            """
        } else {
            sql = """
            SELECT kanji, reading, pos, gloss FROM entries
            WHERE gloss LIKE ?2 LIMIT ?3
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let exact = trimmed as NSString
        let pattern = (hasJapanese ? "\(trimmed)%" : "%\(trimmed)%") as NSString
        sqlite3_bind_text(stmt, 1, exact.utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, pattern.utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        var results: [DictionaryEntry] = []
        var seen = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = DictionaryEntry(
                kanji: columnText(stmt, 0),
                reading: columnText(stmt, 1),
                partOfSpeech: columnText(stmt, 2),
                glossEN: columnText(stmt, 3)
            )
            let key = "\(entry.kanji)|\(entry.reading)"
            if seen.insert(key).inserted {
                results.append(entry)
            }
        }
        return results
    }

    private func query(kanji: String) -> DictionaryEntry? {
        let sql = "SELECT kanji, reading, pos, gloss FROM entries WHERE kanji = ? LIMIT 1"
        return runQuery(sql, bind: kanji)
    }

    private func query(reading: String) -> DictionaryEntry? {
        let sql = "SELECT kanji, reading, pos, gloss FROM entries WHERE reading = ? LIMIT 1"
        return runQuery(sql, bind: reading)
    }

    private func runQuery(_ sql: String, bind value: String) -> DictionaryEntry? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        let ns = value as NSString
        sqlite3_bind_text(stmt, 1, ns.utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let kanji = columnText(stmt, 0)
        let reading = columnText(stmt, 1)
        let pos = columnText(stmt, 2)
        let gloss = columnText(stmt, 3)
        return DictionaryEntry(kanji: kanji, reading: reading, partOfSpeech: pos, glossEN: gloss)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    func wordsContaining(_ kanji: Character, limit: Int = 20) -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil, limit > 0 else { return [] }

        let sql = """
        SELECT surface, reading, pos, gloss FROM kanji_index
        WHERE kanji = ?1
        ORDER BY LENGTH(surface), surface
        LIMIT ?2
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let ns = String(kanji) as NSString
        sqlite3_bind_text(stmt, 1, ns.utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [DictionaryEntry] = []
        var seen = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let entry = DictionaryEntry(
                kanji: columnText(stmt, 0),
                reading: columnText(stmt, 1),
                partOfSpeech: columnText(stmt, 2),
                glossEN: columnText(stmt, 3)
            )
            let key = "\(entry.kanji)|\(entry.reading)"
            if seen.insert(key).inserted {
                results.append(entry)
            }
        }
        return results
    }

    private func loadKanjiCachesIfNeeded() {
        if kanjiMetaCache != nil, irregularCache != nil { return }
        var metas: [Character: KanjiMeta] = [:]
        var irregulars: Set<String> = []

        if db != nil {
            let metaSQL = "SELECT kanji, hanja_ko, on_readings, kun_readings, is_irregular_prone FROM kanji_meta"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, metaSQL, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let literal = columnText(stmt, 0)
                    guard let character = literal.first else { continue }
                    metas[character] = KanjiMeta(
                        kanji: character,
                        hanjaKO: columnText(stmt, 1),
                        onReadings: columnText(stmt, 2).split(separator: "/").map(String.init).filter { !$0.isEmpty },
                        kunReadings: columnText(stmt, 3).split(separator: "/").map(String.init).filter { !$0.isEmpty },
                        isIrregularProne: sqlite3_column_int(stmt, 4) != 0
                    )
                }
            }
            sqlite3_finalize(stmt)

            let irregularSQL = "SELECT surface, reading FROM irregular_words"
            var irregularStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, irregularSQL, -1, &irregularStmt, nil) == SQLITE_OK {
                while sqlite3_step(irregularStmt) == SQLITE_ROW {
                    irregulars.insert("\(columnText(irregularStmt, 0))|\(columnText(irregularStmt, 1))")
                }
            }
            sqlite3_finalize(irregularStmt)
        }

        kanjiMetaCache = metas
        irregularCache = irregulars
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for v in values where !v.isEmpty {
            if seen.insert(v).inserted {
                result.append(v)
            }
        }
        return result
    }
}

extension DictionaryService: KanjiCatalog {
    func meta(for kanji: Character) -> KanjiMeta? {
        lock.lock()
        defer { lock.unlock() }
        loadKanjiCachesIfNeeded()
        return kanjiMetaCache?[kanji]
    }

    func isIrregular(surface: String, reading: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadKanjiCachesIfNeeded()
        return irregularCache?.contains("\(surface)|\(reading)") ?? false
    }
}
