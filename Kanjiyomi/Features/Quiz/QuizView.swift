//
//  QuizView.swift
//  Kanjiyomi
//

import SwiftData
import SwiftUI

enum QuizMode: String, CaseIterable, Identifiable {
    case wordToMeaning = "단어 → 뜻"
    case meaningToWord = "뜻 → 단어"
    var id: String { rawValue }
}

struct QuizQuestion: Identifiable {
    let id = UUID()
    let prompt: String
    let answer: String
    let choices: [String]
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

    var current: QuizQuestion? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    func start(with words: [VocabWord]) {
        guard words.count >= 4 else {
            questions = []
            hasStarted = false
            return
        }
        let shuffled = words.shuffled()
        let count = min(10, shuffled.count)
        questions = (0..<count).compactMap { index in
            makeQuestion(correct: shuffled[index], pool: words, mode: mode)
        }
        currentIndex = 0
        score = 0
        selectedChoice = nil
        isFinished = false
        hasStarted = true
    }

    func select(_ choice: String) {
        guard selectedChoice == nil, let current else { return }
        selectedChoice = choice
        if choice == current.answer {
            score += 1
        }
    }

    func next() {
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
                choices: ([answer] + wrong).shuffled()
            )
        case .meaningToWord:
            let answer = correct.displayHeadword
            let wrong = distractors.map(\.displayHeadword)
            return QuizQuestion(
                prompt: correct.displayMeaning,
                answer: answer,
                choices: ([answer] + wrong).shuffled()
            )
        }
    }
}

struct QuizView: View {
    @Query(sort: \VocabWord.createdAt, order: .reverse) private var words: [VocabWord]
    @State private var viewModel = QuizViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        return NavigationStack {
            ZStack {
                KYColor.background.ignoresSafeArea()

                if words.count < 4 {
                    insufficientState
                } else if viewModel.isFinished {
                    resultState
                } else if viewModel.hasStarted, let question = viewModel.current {
                    questionState(question)
                } else {
                    setupState(viewModel: viewModel)
                }
            }
            .navigationTitle("퀴즈")
        }
    }

    private var insufficientState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(KYColor.primary)
            Text("단어가 4개 이상 필요해요")
                .font(KYFont.headline())
                .foregroundStyle(KYColor.textPrimary)
            Text("단어장에 단어를 더 저장한 뒤 퀴즈를 시작해 보세요.")
                .font(KYFont.callout())
                .foregroundStyle(KYColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
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

                    Text("단어장 \(words.count)개로 최대 10문제를 출제합니다.")
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.textSecondary)
                }
            }

            KYPrimaryButton("퀴즈 시작", systemImage: "play.fill") {
                viewModel.start(with: words)
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
                    Text(viewModel.mode == .wordToMeaning ? "이 단어의 뜻은?" : "이 뜻에 맞는 단어는?")
                        .font(KYFont.caption())
                        .foregroundStyle(KYColor.textSecondary)
                    Text(question.prompt)
                        .font(KYFont.largeTitle())
                        .foregroundStyle(KYColor.textPrimary)
                }
            }

            VStack(spacing: 10) {
                ForEach(question.choices, id: \.self) { choice in
                    Button {
                        viewModel.select(choice)
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

            KYPrimaryButton("다시 풀기", systemImage: "arrow.clockwise") {
                viewModel.start(with: words)
            }
            KYSecondaryButton("모드 선택으로") {
                viewModel.reset()
            }
            Spacer()
        }
        .padding(20)
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
