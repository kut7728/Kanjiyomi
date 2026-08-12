//
//  SettingsView.swift
//  Kanjiyomi
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(OpenAIService.modelDefaultsKey) private var model = ""

    @State private var draftKey = ""
    @State private var showDeleteConfirmation = false

    private var service: OpenAIService { OpenAIService.shared }

    var body: some View {
        NavigationStack {
            List {
                keySection
                if service.isConfigured {
                    modelSection
                }
                privacySection
            }
            .scrollContentBackground(.hidden)
            .background(KYColor.background)
            .navigationTitle("설정")
        }
    }

    private var keySection: some View {
        Section {
            if service.isConfigured {
                LabeledContent("저장된 키") {
                    Text(service.keyHint)
                        .font(KYFont.callout())
                        .foregroundStyle(KYColor.textSecondary)
                        .monospaced()
                }
                Button("키 삭제", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } else {
                SecureField("sk-...", text: $draftKey)
                    .font(KYFont.callout())
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                Button("키 저장", action: save)
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("OpenAI API 키")
        } footer: {
            Text(
                service.isConfigured
                ? "키는 이 기기의 키체인에만 저장됩니다. 백업이나 다른 기기로 옮겨지지 않고, 잠금이 풀린 상태에서만 읽힙니다."
                : "platform.openai.com에서 발급한 본인 키를 넣어주세요. 키는 이 기기의 키체인에만 저장되고, 백업이나 다른 기기로 옮겨지지 않습니다."
            )
        }
        .listRowBackground(KYColor.card)
        .confirmationDialog(
            "저장된 API 키를 삭제할까요?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                service.deleteAPIKey()
                draftKey = ""
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var modelSection: some View {
        Section {
            TextField(OpenAIService.defaultModel, text: $model)
                .font(KYFont.callout())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("모델")
        } footer: {
            Text("비워두면 \(OpenAIService.defaultModel)을 사용합니다.")
        }
        .listRowBackground(KYColor.card)
    }

    private var privacySection: some View {
        Section {
            row(
                icon: "iphone",
                title: "기본은 기기 안에서 처리",
                detail: "글자 인식, 사전 검색, 단어장은 인터넷 없이 이 기기에서만 동작합니다."
            )
            row(
                icon: "arrow.up.forward.app",
                title: "ChatGPT를 고른 경우에만 전송",
                detail: "사진에서 읽어낸 글자만 OpenAI로 보냅니다. 사진 자체는 기기를 떠나지 않습니다."
            )
            row(
                icon: "wonsign.circle",
                title: "요금은 본인 계정에 청구",
                detail: "요청은 저장한 키로 직접 보내집니다. 저희 서버를 거치지 않습니다."
            )
        } header: {
            Text("개인정보")
        }
        .listRowBackground(KYColor.card)
    }

    private func row(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KYColor.primary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(KYFont.callout())
                    .foregroundStyle(KYColor.textPrimary)
                Text(detail)
                    .font(KYFont.caption())
                    .foregroundStyle(KYColor.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmed = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        service.saveAPIKey(trimmed)
        // Drop the plaintext from view state as soon as the Keychain has it.
        draftKey = ""
    }
}

#Preview {
    SettingsView()
}
