//
//  OnboardingView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 23/10/26.
//

import SwiftUI

/// One welcome step.
struct OnboardingPage {
    let headingText: String
    let tagline: String
    let heroAsset: String
    let illustration: String?
    static let catalogItems = [
        OnboardingPage(
            headingText: "Browse smarter", tagline: "A fast browser that reads any page for you.", heroAsset: "welcome_mark",
            illustration: nil),
        OnboardingPage(
            headingText: "Understand any page in seconds",
            tagline: "Summarize an article, pull out the key points, or just ask about what’s on screen.", heroAsset: "ask_mark",
            illustration: "ask_art"),
        OnboardingPage(
            headingText: "Keep the conversation going",
            tagline: "Ask follow-ups, compare things, start from a photo — the chat sits right next to the browser.",
            heroAsset: "chat_mark", illustration: "chat_art"),
        OnboardingPage(
            headingText: "Search with your camera",
            tagline: "Point at anything and find where it comes from — or where to get it.", heroAsset: "camera_mark",
            illustration: "camera_art"),
        OnboardingPage(
            headingText: "Make it your default", tagline: "Links from other apps will open here.", heroAsset: "default_mark",
            illustration: nil),
        OnboardingPage(
            headingText: "About AI answers", tagline: "Three things worth knowing before the first question.",
            heroAsset: "ai_notes_mark", illustration: nil),
    ]
}

/// Six-step welcome flow before the paywall.
struct OnboardingView: View {
    let completeOnboarding: () -> Void
    @State private var welcomeStepIndex = 0
    @State private var attCoordinator = ATTConsent()
    @State private var moving = false
    @Environment(\.scenePhase) private var lifecyclePhase
    @Environment(\.accessibilityReduceMotion) private var lowMotion
    @Environment(BrowserStore.self) private var vault
    private var welcomeStep: OnboardingPage { OnboardingPage.catalogItems[welcomeStepIndex] }

    private var stageTopInset: CGFloat { 118 }
    private var titleAfterMark: CGFloat {
        (welcomeStepIndex == 2 || welcomeStepIndex == 3) ? 16 : 22
    }
    private var footerOrigin: CGFloat { 715 }
    private var illustrationTopGap: CGFloat {
        switch welcomeStepIndex {
        case 2, 3: return 69
        case 1: return 29
        default: return 20
        }
    }

    var body: some View {
        GeometryReader { geo in
            let layoutScale = geo.size.width / 402
            let stageSideInset: CGFloat = geo.size.width > 600 ? (geo.size.width - 440) / 2 : 20 * layoutScale
            let stageInnerWidth = geo.size.width - stageSideInset * 2
            ZStack(alignment: .topLeading) {
                TopGlowBackdrop(assetName: AssetCatalog.topGlow)
                BrandMark(assetName: welcomeStep.heroAsset)
                    .frame(width: 56 * layoutScale, height: 56 * layoutScale)
                    .position(x: stageSideInset + 28 * layoutScale, y: (stageTopInset + 28) * layoutScale)
                    .accessibilityIdentifier("onboarding.mark")

                pageBody(width: stageInnerWidth, layoutScale: layoutScale)
                    .id(welcomeStepIndex)
                    .frame(width: stageInnerWidth, alignment: .topLeading)
                    .position(
                        x: geo.size.width / 2, y: stageTopInset * layoutScale + pageBodyHeight(layoutScale: layoutScale) / 2
                    )
                    .transition(
                        lowMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

                footer(width: stageInnerWidth, layoutScale: layoutScale, footerSize: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 45).onEnded { slot in
                    if slot.translation.width < -70, welcomeStepIndex != 4, (welcomeStepIndex > 0 || attCoordinator.attSettled) {
                        advance()
                    }
                })
        }
        .ignoresSafeArea()
        .task { await attCoordinator.promptATTAfterWelcome() }
        // follow the value, not the action
        .onChange(of: lifecyclePhase) { _, phase in
            if phase == .active, welcomeStepIndex == 0 { Task { await attCoordinator.promptATTAfterWelcome() } }
            if phase == .active, welcomeStepIndex == 4 { advance() }
        }
    }
}

// MARK: - Subviews
extension OnboardingView {
    // page body height
    private func pageBodyHeight(layoutScale: CGFloat) -> CGFloat {
        (footerOrigin - stageTopInset - 8) * layoutScale
    }

    // Page body
    @ViewBuilder private func pageBody(width: CGFloat, layoutScale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: (56 + titleAfterMark) * layoutScale)

            Text(welcomeStepIndex == 1 ? "Understand any page in\nseconds" : welcomeStep.headingText)
                .font(.ui(28 * layoutScale, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(welcomeStep.headingText)
                .accessibilityIdentifier("onboarding.title")

            Text(welcomeStep.tagline)
                .font(.ui(17 * layoutScale))
                .tracking(-0.43)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10 * layoutScale)

            if let illustration = welcomeStep.illustration {
                Spacer().frame(height: illustrationTopGap * layoutScale)
                BundledImage(assetName: illustration)
                    .frame(width: width, height: 372 * layoutScale, alignment: .top)
            } else if welcomeStepIndex == 0 {
                VStack(alignment: .leading, spacing: 18 * layoutScale) {
                    feature(
                        "Ask any page", "Summaries and answers about what is on screen.", icon: "feature_ask",
                        layoutScale: layoutScale, width: width)
                    feature(
                        "Search by photo", "Point the camera and find where it comes from.", icon: "feature_photo",
                        layoutScale: layoutScale, width: width)
                    feature(
                        "Fast and private", "Ads blocked, nothing sent until you ask.", icon: "feature_private",
                        layoutScale: layoutScale, width: width)
                }
                .padding(.top, 26 * layoutScale)
            } else if welcomeStepIndex == 4 {
                defaultBrowserSteps(width: width, layoutScale: layoutScale)
                    .padding(.top, 26 * layoutScale)
            } else if welcomeStepIndex == 5 {
                aiDisclosure(width: width, layoutScale: layoutScale)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: pageBodyHeight(layoutScale: layoutScale), alignment: .topLeading)
    }

    // default browser steps
    private func defaultBrowserSteps(width: CGFloat, layoutScale: CGFloat) -> some View {
        let stepTitles = ["Open Settings", "Tap Default Browser App", "Choose this app"]
        let stepRowHeight: CGFloat = 54 * layoutScale
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stepTitles.enumerated()), id: \.offset) { index, headingText in
                HStack(spacing: 12 * layoutScale) {
                    ZStack {
                        Circle().fill(Palette.brandInk)
                        Text("\(index + 1)")
                            .font(.ui(12 * layoutScale, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 26 * layoutScale, height: 26 * layoutScale)
                    Text(headingText).font(.ui(17 * layoutScale)).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12 * layoutScale)
                .frame(height: stepRowHeight, alignment: .center)
                if index < stepTitles.count - 1 {
                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.45))
                        .frame(height: 1)
                        .padding(.leading, (12 + 26 + 12) * layoutScale)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    // Ai disclosure
    private func aiDisclosure(width: CGFloat, layoutScale: CGFloat) -> some View {
        let mutedLabelColor = Color.secondary
        return VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 48 * layoutScale)
            VStack(alignment: .leading, spacing: 14 * layoutScale) {
                disclosure(
                    icon: "note_page", text: "The text of a page is sent for processing only when you ask a question.",
                    layoutScale: layoutScale, color: mutedLabelColor)
                disclosure(
                    icon: "note_wrong", text: "Answers are generated and can be wrong. Check what matters against the page.",
                    layoutScale: layoutScale, color: mutedLabelColor)
                disclosure(
                    icon: "note_private", text: "Pages opened in private are never processed.", layoutScale: layoutScale,
                    color: mutedLabelColor)
            }
            .padding(.horizontal, 0)
            Button("Read our Privacy Policy") {
                vault.openLegal(.privacy)
            }
            .font(.ui(15 * layoutScale, weight: .semibold))
            .foregroundStyle(Palette.brandInk)
            .padding(.top, 36 * layoutScale)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .topLeading)
    }

    // feature
    private func feature(
        _ headingText: String, _ tagline: String, icon: String, layoutScale: CGFloat, width: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: 14 * layoutScale) {
            BundledImage(assetName: icon).frame(width: 40 * layoutScale, height: 40 * layoutScale)
            VStack(alignment: .leading, spacing: 2 * layoutScale) {
                Text(headingText)
                    .font(.ui(17 * layoutScale, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(tagline)
                    .font(.ui(15 * layoutScale))
                    .tracking(-0.23)
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: max(1, width - 54 * layoutScale), alignment: .leading)
            }
        }
    }

    // disclosure
    private func disclosure(icon: String, text draftText: String, layoutScale: CGFloat, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12 * layoutScale) {
            BundledImage(assetName: icon)
                .frame(width: 22 * layoutScale, height: 22 * layoutScale)
            Text(draftText)
                .font(.ui(15 * layoutScale))
                .tracking(-0.23)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // footer
    private func footer(width: CGFloat, layoutScale: CGFloat, footerSize: CGSize) -> some View {
        let dotsY = footerOrigin * layoutScale
        let buttonY = (footerOrigin + 29 + 27) * layoutScale
        let notNowY = (footerOrigin + 95 + 11) * layoutScale
        return ZStack {
            HStack(spacing: 7 * layoutScale) {
                ForEach(0..<6) { index in
                    Capsule().fill(index == welcomeStepIndex ? Palette.brandInk : Color(uiColor: .systemGray3))
                        .frame(width: index == welcomeStepIndex ? 20 * layoutScale : 7 * layoutScale, height: 7 * layoutScale)
                }
            }
            .frame(height: 7 * layoutScale)
            .position(x: footerSize.width / 2, y: dotsY + 3.5 * layoutScale)
            .accessibilityLabel("Step \(welcomeStepIndex + 1) of 6")

            PrimaryButton(
                welcomeStepIndex == 4 ? "Open Settings" : welcomeStepIndex == 5 ? "I understand" : "Continue",
                enabled: (welcomeStepIndex > 0 || attCoordinator.attSettled) && !moving
            ) {
                if welcomeStepIndex == 4 {
                    if let linkURL = URL(string: BrowsSystemSettings.defaultBrowserOrAppSettings) {
                        UIApplication.shared.open(linkURL)
                    }
                } else {
                    advance()
                }
            }
            .frame(width: width)
            .position(x: footerSize.width / 2, y: buttonY)
            .accessibilityIdentifier("onboarding.continue")

            if welcomeStepIndex == 4 {
                Button("Not now", action: advance)
                    .font(.ui(17 * layoutScale, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: width, height: 22 * layoutScale)
                    .position(x: footerSize.width / 2, y: notNowY)
                    .accessibilityIdentifier("onboarding.skipDefault")
            }
        }
    }

    // Next step, or finish after the last one.
    private func advance() {
        guard !moving, welcomeStepIndex > 0 || attCoordinator.attSettled else { return }
        if welcomeStepIndex == 5 {
            UserDefaults.standard.set(true, forKey: "aiDisclosureAccepted")
            completeOnboarding()
        } else {
            moving = true
            withAnimation(lowMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.36)) { welcomeStepIndex += 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                moving = false
            }
        }
    }
}
