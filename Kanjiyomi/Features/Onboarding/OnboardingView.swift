import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    let onConfigureAPIKey: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var page = 0
    @State private var canUseOnDeviceAI = MeaningService.shared.isGenerationAvailable

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch page {
                    case 0: introduction
                    case 1: modes
                    default: apiGuide
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(page)
        }
        .background(KYColor.background.ignoresSafeArea())
        .foregroundStyle(KYColor.textPrimary)
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .preferredColorScheme(.light)
        .tint(KYColor.primary)
        .interactiveDismissDisabled()
        .onAppear { refreshAvailability() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshAvailability() }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("사용 안내 · \(page + 1) / 3")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("onboarding.progress")
                Spacer()
                Button("나중에 보기", action: onFinish)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.skip")
            }
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule()
                        .fill(index <= page ? KYColor.primary : KYColor.primary.opacity(0.12))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var introduction: some View {
        Group {
            heading(icon: "text.viewfinder", title: "사진에서 단어장까지",
                    subtitle: "사진 속 단어의 뜻·발음을 보고, 퀴즈로 복습해요.")

            availabilityCard

            KYCard {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("半額").font(.title.bold())
                            Text("예시").font(.caption).foregroundStyle(KYColor.primary)
                        }
                        Text("はんがく · 한가쿠").font(.footnote)
                    }
                    Spacer(minLength: 0)
                    Text("반값")
                        .font(.title2.bold())
                        .foregroundStyle(KYColor.primary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("키 없이 오프라인으로 시작해요", systemImage: "wifi.slash")
                    .font(.subheadline.bold())
                Text("한국어 미수록 단어는 AI로 보완해요. 안 되면 영어 뜻·‘뜻 없음’으로 표시돼요. 한국어 뜻이 있는 단어만 저장돼요.")
                    .font(.footnote)
                    .accessibilityIdentifier("onboarding.introductionNote")
            }
        }
    }

    private var modes: some View {
        Group {
            heading(icon: "slider.horizontal.3", title: "내게 맞는 모드로",
                    subtitle: "글자 인식은 같고, 단어 나누기·뜻 보완이 달라요.")

            KYCard {
                VStack(alignment: .leading, spacing: 16) {
                    modeRow(.dictionary,
                            text: "사전 단어를 빠르게 찾아요. 없는 한국어 뜻은 기기 AI가 가능하면 보완해요.")
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        modeRow(.model,
                                text: "사전 밖 단어·뜻·새 예문을 생성해요. iOS 26+와 Apple Intelligence가 필요해요.")
                        Text(canUseOnDeviceAI ? "현재 사용 가능 · 기기 안에서 처리" : "현재 사용 불가")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KYColor.primary)
                    }
                    Divider()
                    modeRow(.openAI,
                            text: "기기 AI 없이 단어·뜻을 생성해요. 인터넷·본인 API 키·별도 요금이 필요해요.")
                }
            }

            Text("사진 인식 후 ‘단어 나누기’에서 선택해요. 기기 AI·ChatGPT는 사용 조건을 갖추면 나타나요.")
                .font(.footnote)
                .accessibilityIdentifier("onboarding.modeNote")
        }
    }

    private var apiGuide: some View {
        Group {
            heading(icon: "key.fill", title: "필요할 때 GPT로 보완",
                    subtitle: "기기 AI 없이, 미수록 뜻·읽기를 채워요.")

            KYCard {
                VStack(alignment: .leading, spacing: 16) {
                    Button(action: onConfigureAPIKey) {
                        HStack(alignment: .top, spacing: 8) {
                            guideRow(icon: "key", title: "내 API 키로 선택해서 사용",
                                     text: "키 등록 → 사진 스캔 → ‘단어 나누기’에서 GPT를 선택해요.")
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(KYColor.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(OpenAIService.shared.isConfigured ? "API 키 설정 보기" : "API 키 설정하기")
                    .accessibilityValue("키 등록 후 사진을 스캔하고 단어 나누기에서 GPT를 선택하세요.")
                    .accessibilityHint("설정에서 OpenAI API 키를 등록하거나 확인합니다.")
                    .accessibilityIdentifier("onboarding.configure")

                    Divider()

                    Link(destination: URL(string: "https://help.openai.com/en/articles/9039756-managing-billing-settings-on-the-chatgpt-web-and-api-platform")!) {
                        HStack(alignment: .top, spacing: 8) {
                            guideRow(icon: "creditcard", title: "사용량에 따라 별도 과금",
                                     text: "ChatGPT 구독과 별도예요.\n인터넷·API 결제 설정이 필요해요.")
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(KYColor.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("OpenAI의 API 요금·결제 안내를 엽니다.")

                    Divider()

                    guideRow(icon: "lock.shield", title: "사진은 보내지 않아요",
                             text: "글자·읽기·영어 뜻 → OpenAI\n키는 기기 키체인에 보관해요.")
                }
            }

            Text("GPT를 고를 때만 요청해요. 새 예문은 기기 AI가 필요하며, AI의 뜻·읽기는 틀릴 수 있어요.")
                .font(.footnote)
                .accessibilityIdentifier("onboarding.apiNote")
        }
    }

    private var availabilityCard: some View {
        KYCard {
            detail(
                icon: canUseOnDeviceAI ? "checkmark.circle" : "info.circle",
                title: canUseOnDeviceAI ? "온디바이스 AI 사용 가능" : "현재 온디바이스 AI 사용 불가",
                text: canUseOnDeviceAI
                    ? "미수록 한국어 뜻·새 예문을 기기에서 생성해요."
                    : "기기·iOS·설정·모델 준비 상태에 따라 달라요. 지금은 사전·저장된 뜻을 사용해요."
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            KYSecondaryButton("이전") { page -= 1 }
                .disabled(page == 0)
                .opacity(page == 0 ? 0.4 : 1)
                .accessibilityIdentifier("onboarding.previous")
            if page == 2 {
                KYPrimaryButton("바로 시작하기", action: onFinish)
                    .accessibilityIdentifier("onboarding.finish")
            } else {
                KYPrimaryButton("다음") { page += 1 }
                    .accessibilityIdentifier("onboarding.next")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(KYColor.background)
    }

    private func heading(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.footnote)
        }
    }

    private func modeRow(_ mode: SegmentationMode, text: String) -> some View {
        guideRow(icon: mode.systemImage, title: mode.label, text: text)
    }

    private func guideRow(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
            Text(text)
                .font(.footnote)
        }
    }

    private func detail(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KYColor.primary)
                .frame(width: 32, height: 32)
                .background(KYColor.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(KYColor.textPrimary)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(KYColor.textPrimary.opacity(0.8))
            }
        }
    }

    private func refreshAvailability() {
        canUseOnDeviceAI = MeaningService.shared.isGenerationAvailable
    }
}
