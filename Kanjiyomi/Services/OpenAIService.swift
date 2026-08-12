//
//  OpenAIService.swift
//  Kanjiyomi
//

import Foundation

/// Word segmentation through the user's own OpenAI account.
///
/// This is the only part of the app that leaves the device. It sends the text recognized in
/// a photo, never the photo itself, and only when the user has both stored a key and picked
/// this mode. The key is read from the Keychain per request and only ever travels in the
/// `Authorization` header of an HTTPS request, never in a URL or a log line.
@Observable
@MainActor
final class OpenAIService {
    static let shared = OpenAIService()

    /// The `gpt-5.6` alias routes to Sol, the frontier tier, which spends far more time
    /// thinking than splitting words and glossing them needs. Luna is the fast tier and
    /// still comfortably handles both.
    static let defaultModel = "gpt-5.6-luna"
    static let modelDefaultsKey = "openAIModel"

    /// Omitting this leaves the model at its `medium` default, which added tens of seconds
    /// to every scan. Both tasks here are pattern work with a fixed answer shape, so light
    /// reasoning is enough.
    private static let reasoningEffort = "low"

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Lines carry the words for a whole photo, so one request is usually enough.
    private static let segmentBatchSize = 30

    private static let segmentInstructions = """
    You split Japanese text into the words a dictionary would list.
    Copy characters exactly as they appear; never translate, respell, or invent text.
    Keep the words in the order they appear in the line.
    Leave out particles, inflectional endings, punctuation and bare numbers.
    Return one entry for every line you are given, in the same order.
    """

    private static let meaningInstructions = """
    You translate Japanese words for Korean learners.
    For every word you are given, return its meaning in Korean and how it is read.
    Write the reading in hiragana only, never in kanji or romaji.
    Always answer in Korean. Never answer in English.
    Keep each meaning under 20 Korean characters.
    Return one entry for every word you are given, in the same order.
    """

    /// Nothing here is written to disk: no URL cache for the recognized text and no cookies.
    @ObservationIgnored
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()

    /// Mirrors whether a key is in the Keychain. Held in memory so the mode picker can
    /// depend on it without hitting the Keychain on every redraw.
    private(set) var isConfigured: Bool

    /// The last few characters of the stored key, enough to tell two keys apart without
    /// putting a usable secret on screen.
    private(set) var keyHint: String

    /// Set when a request fails so the scan screen can explain why it fell back to the
    /// dictionary. Never contains the key.
    private(set) var lastErrorMessage: String?

    private init() {
        let stored = KeychainStore.read(.openAIAPIKey)
        isConfigured = stored != nil
        keyHint = Self.hint(for: stored)
    }

    var model: String {
        let stored = UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? ""
        return stored.isEmpty ? Self.defaultModel : stored
    }

    func saveAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.save(trimmed, for: .openAIAPIKey)
        isConfigured = KeychainStore.contains(.openAIAPIKey)
        keyHint = isConfigured ? Self.hint(for: trimmed) : ""
        lastErrorMessage = nil
    }

    func deleteAPIKey() {
        KeychainStore.delete(.openAIAPIKey)
        isConfigured = false
        keyHint = ""
        lastErrorMessage = nil
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private static func hint(for key: String?) -> String {
        guard let key, key.count > 4 else { return "" }
        return "••••••••" + String(key.suffix(4))
    }

    // MARK: - Segmentation

    func segment(lines: [String]) async -> [[String]] {
        guard !lines.isEmpty, let apiKey = requireKey() else { return [] }

        var result = [[String]](repeating: [], count: lines.count)
        for range in Self.batches(of: lines.count, size: Self.segmentBatchSize) {
            if Task.isCancelled { break }
            let batch = Array(lines[range])
            do {
                let produced = try await segmentBatch(batch, apiKey: apiKey)
                for (offset, words) in produced.enumerated() where range.lowerBound + offset < result.count {
                    result[range.lowerBound + offset] = words
                }
            } catch {
                lastErrorMessage = Self.message(for: error)
                return result
            }
        }
        return result
    }

    private func segmentBatch(_ batch: [String], apiKey: String) async throws -> [[String]] {
        let parsed: SegmentedPayload = try await complete(
            instructions: Self.segmentInstructions,
            prompt: """
            Split each of these \(batch.count) Japanese lines into words.
            \(batch.map { "- \($0)" }.joined(separator: "\n"))
            """,
            schemaName: "segmented_lines",
            schema: Self.segmentSchema,
            apiKey: apiKey
        )

        // Matching on the echoed line survives a dropped entry; position covers a rewritten
        // one. Words that fit neither are discarded later, when they cannot be found in the
        // line they were meant for.
        let wordsByLine = Dictionary(parsed.lines.map { ($0.line, $0.words) }) { first, _ in first }
        return batch.enumerated().map { index, line in
            if let words = wordsByLine[line] { return words }
            return index < parsed.lines.count ? parsed.lines[index].words : []
        }
    }

    // MARK: - Meanings

    /// Korean meanings for a batch of words, keyed by cache key.
    ///
    /// Nothing is written to the cache here. A ChatGPT pass stays in memory until the user
    /// decides to keep it, so a scan they did not like leaves their saved meanings untouched.
    func generateMeanings(for words: [RecognizedWord]) async -> [String: MeaningResult] {
        guard !words.isEmpty, let apiKey = requireKey() else { return [:] }

        let requests = words.map { word in
            MeaningRequest(
                key: WordCache.makeKey(surface: word.surface, lemma: word.lemma),
                word: word.displayHeadword,
                reading: word.reading,
                glossEN: word.meaningEN
            )
        }
        // Matching on the echoed word rather than position survives a dropped entry.
        let keysByWord = Dictionary(requests.map { ($0.word, $0.key) }) { first, _ in first }
        let readingsByKey = Dictionary(requests.map { ($0.key, $0.reading) }) { first, _ in first }
        let wordsByKey = Dictionary(requests.map { ($0.key, $0.word) }) { first, _ in first }

        let parsed: MeaningPayload
        do {
            parsed = try await complete(
                instructions: Self.meaningInstructions,
                prompt: """
                Give the Korean meaning of each of these \(requests.count) Japanese words.
                \(requests.map(\.promptLine).joined(separator: "\n"))
                """,
                schemaName: "word_meanings",
                schema: Self.meaningSchema,
                apiKey: apiKey
            )
        } catch {
            lastErrorMessage = Self.message(for: error)
            return [:]
        }

        var results: [String: MeaningResult] = [:]
        for (index, item) in parsed.items.enumerated() {
            let meaning = item.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !meaning.isEmpty else { continue }
            // The model occasionally rewrites the word it echoes back; position covers that
            // as long as it returned the number of entries it was asked for.
            guard let key = keysByWord[item.word]
                    ?? (parsed.items.count == requests.count ? requests[index].key : nil)
            else { continue }

            // A word JMdict has never heard of has no reading to show, and the model is the
            // only source left. Kana is salvaged out of the answer, and anything that leaves
            // no kana behind is dropped rather than romanized into nonsense.
            let needsReading = readingsByKey[key]?.isEmpty ?? false
            let reading = needsReading
                ? MeaningService.acceptedReading(item.reading, for: wordsByKey[key] ?? item.word)
                : ""
            results[key] = MeaningResult(
                meaningKO: meaning,
                reading: reading,
                hangul: reading.isEmpty ? "" : KanaRomanizer.toHangul(reading)
            )
        }
        return results
    }

    // MARK: - Transport

    private func requireKey() -> String? {
        guard let apiKey = KeychainStore.read(.openAIAPIKey), !apiKey.isEmpty else {
            lastErrorMessage = "설정에서 OpenAI API 키를 먼저 추가해 주세요."
            return nil
        }
        return apiKey
    }

    private func complete<Payload: Decodable>(
        instructions: String,
        prompt: String,
        schemaName: String,
        schema: [String: Any],
        apiKey: String
    ) async throws -> Payload {
        let body: [String: Any] = [
            "model": model,
            "reasoning_effort": Self.reasoningEffort,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": schemaName,
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.transport }
        guard http.statusCode == 200 else {
            // Only the fixed identifiers are read, never the server's prose. A 429 alone
            // cannot tell an empty balance apart from requests arriving too fast, and those
            // need opposite things from the user.
            let failure = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error
            throw OpenAIError.status(http.statusCode, reason: failure?.code ?? failure?.type)
        }

        guard let content = try? JSONDecoder().decode(ChatResponse.self, from: data)
            .choices.first?.message.content,
              let payload = content.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(Payload.self, from: payload)
        else { throw OpenAIError.malformedResponse }
        return parsed
    }

    private static func batches(of count: Int, size: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: size).map { $0..<min($0 + size, count) }
    }

    private static let segmentSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "lines": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "line": ["type": "string"],
                        "words": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["line", "words"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["lines"],
        "additionalProperties": false
    ]

    private static let meaningSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "word": ["type": "string"],
                        "meaning": ["type": "string"],
                        "reading": ["type": "string"]
                    ],
                    "required": ["word", "meaning", "reading"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["items"],
        "additionalProperties": false
    ]

    /// Built from the status code and OpenAI's own error identifier. The server's message
    /// text is never shown, so nothing about the request can reach the screen.
    private static func message(for error: Error) -> String {
        guard let error = error as? OpenAIError else {
            return "ChatGPT 요청에 실패했어요. 네트워크를 확인해 주세요."
        }
        switch error {
        case .transport:
            return "ChatGPT에 연결하지 못했어요. 네트워크를 확인해 주세요."
        case .malformedResponse:
            return "ChatGPT 응답을 이해하지 못했어요."
        case let .status(code, reason):
            return message(status: code, reason: reason)
        }
    }

    private static func message(status: Int, reason: String?) -> String {
        // Billing problems all arrive as 429, the same code as genuine rate limiting, and
        // telling the user to wait would be useless advice for every one of them.
        switch reason {
        case "credit_balance_exhausted", "insufficient_quota":
            return "OpenAI 계정에 남은 크레딧이 없어요. platform.openai.com 결제 화면에서 크레딧을 충전해 주세요."
        case "organization_spend_limit_exceeded", "project_spend_limit_exceeded":
            return "OpenAI 계정에 설정한 지출 한도에 도달했어요. 한도를 올리거나 해제해 주세요."
        case "organization_usage_limit_exceeded":
            return "OpenAI가 계정에 지정한 사용 한도에 도달했어요. 한도 상향을 요청해 주세요."
        default:
            break
        }

        switch status {
        case 401, 403:
            return "API 키가 거부됐어요. 설정에서 키를 다시 확인해 주세요."
        case 404:
            return "모델을 찾을 수 없어요. 설정에서 모델 이름을 확인해 주세요."
        case 429:
            return "요청이 너무 빨라요. 잠시 후 다시 시도해 주세요."
        default:
            return "ChatGPT 요청이 실패했어요. (\(status))"
        }
    }
}

private enum OpenAIError: Error {
    case status(Int, reason: String?)
    case transport
    case malformedResponse
}

/// OpenAI's error envelope. Only the machine-readable identifiers are decoded.
private struct APIErrorEnvelope: Decodable {
    struct Failure: Decodable {
        let code: String?
        let type: String?
    }
    let error: Failure
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct SegmentedPayload: Decodable {
    struct Line: Decodable {
        let line: String
        let words: [String]
    }
    let lines: [Line]
}

private struct MeaningPayload: Decodable {
    struct Item: Decodable {
        let word: String
        let meaning: String
        let reading: String
    }
    let items: [Item]
}
