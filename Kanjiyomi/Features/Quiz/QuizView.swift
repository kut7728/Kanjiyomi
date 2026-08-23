//
//  QuizView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

enum QuizMode: String, CaseIterable, Identifiable {
    case wordToMeaning = "단어 → 뜻"
    case meaningToWord = "뜻 → 단어"
    case readingInference = "읽기 추론"
    var id: String { rawValue }
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let prompt: String
    let answer: String
    let choices: [String]
    var caption: String? = nil
    var successMessage: String? = nil
    var isInference: Bool = false
    var isRelatedBoost: Bool = false
    var trackedSurface: String? = nil
    var patternKanji: String? = nil
    var patternReading: String? = nil
}

@MainActor
@Observable
final class QuizViewModel {
    var mode: QuizMode = .wordToMeaning
    var questions: [QuizQuestion] = []
    var currentIndex = 0
    var score = 0
    var selectedChoice: String?
    var isFinished = false
    var hasStarted = false
    var inferenceUnavailable = false
    var lastSuccessMessage: String?

    var current: QuizQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    func start(
        with words: [VocabWord],
        catalog: KanjiCatalog = DictionaryService.shared,
        modelContext: ModelContext? = nil
    ) {
        lastSuccessMessage = nil
        inferenceUnavailable = false
        if let modelContext {
            KanjiPatternStore.sync(from: words, modelContext: modelContext, catalog: catalog)
        }

        switch mode {
        case .readingInference:
            startInference(words: words, catalog: catalog)
        case .wordToMeaning, .meaningToWord:
            startMeaning(words: words, catalog: catalog, modelContext: modelContext)
        }
    }

    func select(_ choice: String, modelContext: ModelContext? = nil) {
        guard selectedChoice == nil, let current else { return }
        selectedChoice = choice
        let isCorrect = choice == current.answer
        if isCorrect {
            score += 1
            lastSuccessMessage = current.successMessage
        } else {
            lastSuccessMessage = nil
        }
        if let modelContext {
            if let surface = current.trackedSurface {
                KanjiPatternStore.recordAttempt(
                    surface: surface,
                    mode: mode,
                    isCorrect: isCorrect,
                    modelContext: modelContext
                )
            }
            if let kanji = current.patternKanji, let reading = current.patternReading {
                KanjiPatternStore.recordQuiz(
                    kanji: kanji,
                    reading: reading,
                    isCorrect: isCorrect,
                    isInference: current.isInference,
                    modelContext: modelContext
                )
            }
        }
    }

    func next() {
        lastSuccessMessage = nil
        if currentIndex + 1 >= questions.count {
            isFinished = true
        } else {
            currentIndex += 1
            selectedChoice = nil
        }
    }

    func reset() {
        hasStarted = false
        isFinished = false
        questions = []
        selectedChoice = nil
        currentIndex = 0
        score = 0
        inferenceUnavailable = false
        lastSuccessMessage = nil
    }

    private func startMeaning(
        words: [VocabWord],
        catalog: KanjiCatalog,
        modelContext: ModelContext?
    ) {
        guard words.count >= 4 else {
            questions = []
            hasStarted = false
            return
        }
        let shuffled = words.shuffled()
        let count = min(10, shuffled.count)
        var built = (0..<count).compactMap { index in
            makeQuestion(correct: shuffled[index], pool: words, mode: mode)
        }
        if let modelContext {
            let learned = words.map { ($0.displayHeadword, $0.reading, $0.displayMeaning) }
            for miss in KanjiPatternStore.recentMisses(modelContext: modelContext, limit: 4) {
                let extras = RelatedReviewBuilder.boostQuestions(
                    missedSurface: miss.surface,
                    learned: learned,
                    catalog: catalog,
                    limit: 1
                )
                built.insert(contentsOf: extras, at: 0)
                if extras.isEmpty == false { break }
            }
            built = Array(built.prefix(10))
        }
        questions = built
        currentIndex = 0
        score = 0
        selectedChoice = nil
        isFinished = false
        hasStarted = !built.isEmpty
    }

    private func startInference(words: [VocabWord], catalog: KanjiCatalog) {
        let learned = words.map { ($0.displayHeadword, $0.reading) }
        let patterns = PatternDetector.detect(from: learned, catalog: catalog)
            .filter { $0.status == .discovered || $0.status == .familiar }
        guard !patterns.isEmpty else {
            questions = []
            hasStarted = false
            inferenceUnavailable = true
            return
        }
        let built = InferenceQuizBuilder.makeQuestions(
            learned: learned,
            catalog: catalog,
            limit: 10
        ).map { question in
            QuizQuestion(
                prompt: question.surface,
                answer: question.answer,
                choices: question.choices,
                caption: "\(question.surface)은 어떻게 읽을까요?",
                successMessage: "배운 적 없는 단어를 한자 패턴으로 맞혔습니다.",
                isInference: true,
                trackedSurface: question.surface,
                patternKanji: String(question.patternKanji),
                patternReading: question.patternReading
            )
        }
        questions = built
        currentIndex = 0
        score = 0
        selectedChoice = nil
        isFinished = false
        hasStarted = !built.isEmpty
        inferenceUnavailable = built.isEmpty
    }

    private func makeQuestion(correct: VocabWord, pool: [VocabWord], mode: QuizMode) -> QuizQuestion? {
        let distractors = pool
            .filter { $0.id != correct.id }
            .shuffled()
            .prefix(3)
        guard distractors.count == 3 else { return nil }

        switch mode {
        case .wordToMeaning:
            let answer = correct.displayMeaning
            let wrong = distractors.map(\.displayMeaning)
            return QuizQuestion(
                prompt: correct.displayHeadword,
                answer: answer,
                choices: ([answer] + wrong).shuffled(),
                trackedSurface: correct.displayHeadword
            )
        case .meaningToWord:
            let answer = correct.displayHeadword
            let wrong = distractors.map(\.displayHeadword)
            return QuizQuestion(
                prompt: correct.displayMeaning,
                answer: answer,
                choices: ([answer] + wrong).shuffled(),
                trackedSurface: correct.displayHeadword
            )
        case .readingInference:
            return nil
        }
    }
}

struct QuizView: View {
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]
    @Query(sort: \UserKanjiPattern.updatedAt, order: .reverse) private var patterns: [UserKanjiPattern]
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = QuizViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            ZStack {
                KYColor.background.ignoresSafeArea()

                if viewModel.inferenceUnavailable {
                    inferenceBlockedState
                } else if viewModel.isFinished {
                    resultState
                } else if viewModel.hasStarted, let question = viewModel.current {
                    questionState(question)
                } else {
                    setupState(viewModel: viewModel)
                }
            }
            .navigationTitle("퀴즈")
            .onAppear {
                KanjiPatternStore.sync(
                    from: words,
                    modelContext: modelContext,
                    catalog: DictionaryService.shared
                )
            }
        }
    }

    private func setupState(viewModel: QuizViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return VStack(spacing: 20) {
            KYCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("퀴즈 모드")
                        .font(KYFont.headline())
                        .foregroundStyle(KYColor.textPrimary)
                    Picker("모드", selection: $viewModel.mode) {
                        ForEach(QuizMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(setupCaption)
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.textSecondary)
                }
            }

            if words.count < 4, viewModel.mode != .readingInference {
                Text("뜻 퀴즈는 단어가 4개 이상 필요해요.")
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textSecondary)
            }

            PatternProgressCard(count: KanjiPatternStore.discoveredCount(in: patterns))

            KYPrimaryButton(
                "퀴즈 시작",
                systemImage: "play.fill",
                isEnabled: viewModel.mode == .readingInference || words.count >= 4
            ) {
                viewModel.start(
                    with: words,
                    catalog: DictionaryService.shared,
                    modelContext: modelContext
                )
            }
        }
        .padding(20)
    }

    private func questionState(_ question: QuizQuestion) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("\(viewModel.currentIndex + 1) / \(viewModel.questions.count)")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
                Spacer()
                Text("점수 \(viewModel.score)")
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.primary)
            }

            KYCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.caption ?? defaultCaption)
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.textSecondary)
                    Text(question.prompt)
                        .font(KYFont.largeTitle())
                        .foregroundStyle(KYColor.textPrimary)
                    if question.isRelatedBoost {
                        Text("틀린 단어와 같은 한자를 다시 보는 보조 문제입니다.")
                            .font(KYFont.caption())
                            .foregroundStyle(KYColor.primary)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(question.choices, id: \.self) { choice in
                    Button {
                        viewModel.select(choice, modelContext: modelContext)
                    } label: {
                        Text(choice)
                            .font(KYFont.body())
                            .foregroundStyle(choiceColor(for: choice, answer: question.answer))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(choiceBackground(for: choice, answer: question.answer))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedChoice != nil)
                }
            }

            if viewModel.selectedChoice != nil {
                if let message = viewModel.lastSuccessMessage {
                    Text(message)
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.success)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                KYPrimaryButton(viewModel.currentIndex + 1 >= viewModel.questions.count ? "결과 보기" : "다음") {
                    viewModel.next()
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private var resultState: some View {
        VStack(spacing: 20) {
            KYCard {
                VStack(spacing: 12) {
                    Text("퀴즈 결과")
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.textSecondary)
                    Text("\(viewModel.score) / \(viewModel.questions.count)")
                        .font(KYFont.largeTitle())
                        .foregroundStyle(KYColor.primary)
                    Text(resultMessage)
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }

            PatternProgressCard(count: KanjiPatternStore.discoveredCount(in: patterns))

            KYPrimaryButton("다시 풀기", systemImage: "arrow.clockwise") {
                viewModel.start(
                    with: words,
                    catalog: DictionaryService.shared,
                    modelContext: modelContext
                )
            }
            KYSecondaryButton("모드 선택으로") {
                viewModel.reset()
            }
            Spacer()
        }
        .padding(20)
    }

    private var defaultCaption: String {
        switch viewModel.mode {
        case .wordToMeaning: return "이 단어의 뜻은?"
        case .meaningToWord: return "이 뜻에 맞는 단어는?"
        case .readingInference: return "이 단어는 어떻게 읽을까요?"
        }
    }

    private var setupCaption: String {
        switch viewModel.mode {
        case .readingInference:
            return "익힌 한자 패턴으로 처음 보는 단어의 읽기를 추론합니다."
        case .wordToMeaning, .meaningToWord:
            return "단어장 \(words.count)개로 최대 10문제를 출제합니다."
        }
    }

    private var inferenceBlockedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text("아직 발견한 패턴이 없어요")
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
            Text("같은 한자가 들어간 단어를 더 모아 보세요. 패턴이 보이면 처음 보는 단어의 읽기를 추론할 수 있습니다.")
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
                .multilineTextAlignment(.center)
            KYSecondaryButton("모드 선택으로") {
                viewModel.reset()
            }
        }
        .padding(40)
    }

    private var resultMessage: String {
        let total = max(viewModel.questions.count, 1)
        let ratio = Double(viewModel.score) / Double(total)
        if ratio >= 0.8 { return "훌륭해요! 거의 다 맞췄어요." }
        if ratio >= 0.5 { return "좋아요. 한 번 더 복습해 볼까요?" }
        return "괜찮아요. 단어장을 다시 보고 도전해 보세요."
    }

    private func choiceColor(for choice: String, answer: String) -> Color {
        guard let selected = viewModel.selectedChoice else { return KYColor.textPrimary }
        if choice == answer { return KYColor.success }
        if choice == selected { return KYColor.danger }
        return KYColor.textSecondary
    }

    private func choiceBackground(for choice: String, answer: String) -> Color {
        guard let selected = viewModel.selectedChoice else { return KYColor.card }
        if choice == answer { return KYColor.success.opacity(0.12) }
        if choice == selected { return KYColor.danger.opacity(0.12) }
        return KYColor.card
    }
}
