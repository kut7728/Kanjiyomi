//
//  Components.swift
//  Kanjiyomi
//

import SwiftUI

struct KYCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KYColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

struct KYPrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    var isEnabled: Bool = true

    init(_ title: String, systemImage: String? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(KYFont.body())
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? KYColor.primary : KYColor.textSecondary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

struct KYSecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(KYFont.body())
            }
            .foregroundStyle(KYColor.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(KYColor.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct KYDotLoadingView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.28, paused: false)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.28) % 3
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(KYColor.primary)
                        .frame(width: 10, height: 10)
                        .scaleEffect(phase == index ? 1.25 : 0.85)
                        .opacity(phase == index ? 1 : 0.45)
                        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: phase)
                }
            }
        }
    }
}

struct KYLoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            KYDotLoadingView()

            // Each step slides up as it replaces the previous one.
            ZStack {
                Text(message)
                    .font(KYFont.headline())
                    .foregroundStyle(KYColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .id(message)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
            .frame(height: 26)
            .clipped()
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: message)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(minWidth: 240)
        .background(KYColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 28)
    }
}

struct SpeechBubble: View {
    let text: String
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(spacing: 0) {
                Text(text)
                    .font(KYFont.callout())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(KYColor.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Triangle()
                    .fill(KYColor.primary)
                    .frame(width: 14, height: 8)
                    .rotationEffect(.degrees(180))
                    .offset(y: -1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
