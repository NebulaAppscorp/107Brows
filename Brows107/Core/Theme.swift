//
//  Theme.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 27/10/26.
//

import SwiftUI
import UIKit
import Speech
import AVFoundation

/// Deep links into system settings.
enum BrowsSystemSettings {
    static var defaultBrowserOrAppSettings: String {
        if #available(iOS 18.3, *) {
            return UIApplication.openDefaultApplicationsSettingsURLString
        }
        return UIApplication.openSettingsURLString
    }
}

/// Pre-iOS 26 stand-in for the glass button style.
struct BrowsFallbackGlassButtonStyle: ButtonStyle {
    // injected state
    @Environment(\.colorScheme) private var interfaceScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                Capsule().fill(.ultraThinMaterial)
            }
            .overlay(
                Capsule().strokeBorder(Color(uiColor: .separator).opacity(interfaceScheme == .dark ? 0.5 : 0.35), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BrowsFallbackGlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // background goes behind everything
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            // animate only on this value
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BrowsGlassBackgroundModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
        }
    }
}

struct BrowsGlassCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var interfaceScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(interfaceScheme == .dark ? Color.black.opacity(0.34) : nil).interactive(), in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .background(interfaceScheme == .dark ? Color.black.opacity(0.24) : .clear, in: Capsule())
        }
    }
}

struct BrowsGlassCircleModifier: ViewModifier {
    @Environment(\.colorScheme) private var interfaceScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                .regular.tint(interfaceScheme == .dark ? Color.black.opacity(0.34) : nil).interactive(), in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
                .background(interfaceScheme == .dark ? Color.black.opacity(0.24) : .clear, in: Circle())
                .overlay(Circle().strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5))
        }
    }
}

struct BrowsGlassButtonModifier: ViewModifier {
    // view state
    @Environment(\.colorScheme) private var interfaceScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
                .tint(interfaceScheme == .dark ? Color.black.opacity(0.34) : nil)
        } else {
            content.buttonStyle(BrowsFallbackGlassButtonStyle())
                // background fill
                .background(interfaceScheme == .dark ? Color.black.opacity(0.24) : .clear, in: Capsule())
        }
    }
}

struct BrowsGlassProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(BrowsFallbackGlassProminentButtonStyle())
        }
    }
}

extension View {
    @ViewBuilder
    func browsExactLineHeight(_ points: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            lineHeight(.exact(points: points))
        } else {
            self
        }
    }

    // brows glass background
    func browsGlassBackground(radius: CGFloat) -> some View {
        modifier(BrowsGlassBackgroundModifier(radius: radius))
    }

    // brows glass capsule
    func browsGlassCapsule() -> some View {
        modifier(BrowsGlassCapsuleModifier())
    }

    // Brows glass circle
    func browsGlassCircle() -> some View {
        modifier(BrowsGlassCircleModifier())
    }

    // brows glass button style
    func browsGlassButtonStyle() -> some View {
        modifier(BrowsGlassButtonModifier())
    }

    // Brows glass prominent button style
    func browsGlassProminentButtonStyle() -> some View {
        modifier(BrowsGlassProminentButtonModifier())
    }

    // Native nav bar; optionally hides its background and tracks scroll.
    func browsLiquidNavBar(hidesBackground: Bool = false, tracksScroll: Bool = false) -> some View {
        modifier(BrowsLiquidNavBarModifier(hidesBackground: hidesBackground, tracksScroll: tracksScroll))
    }

    @ViewBuilder
    func browsScrollEdgeEffectHidden(_ edges: Edge.Set = .all) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: edges)
        } else {
            self
        }
    }

    /// Bottom browser toolbar: `safeAreaBar` on iOS 26+, overlay fallback for older SDK checks.
    @ViewBuilder
    func browsBrowserBottomToolbar<Bar: View>(shows: Bool, @ViewBuilder bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0) {
                if shows { bar() }
            }
        } else {
            overlay(alignment: .bottom) {
                if shows {
                    bar()
                }
            }
        }
    }

    /// Full-width sheet flush to the bottom (no floating card inset).
    @ViewBuilder
    func browsFlushBottomSheet() -> some View {
        modifier(BrowsFlushBottomSheetModifier())
            .modifier(BrowsSheetEdgeAttachModifier())
    }

    // brows sheet canvas background
    func browsSheetCanvasBackground() -> some View {
        presentationBackground {
            Palette.canvasView.ignoresSafeArea()
        }
    }
}

struct BrowsFlushBottomSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}

/// Removes the floating-card look of iOS sheets so width and bottom sit flush with the screen.
struct BrowsSheetEdgeAttachModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(BrowsSheetEdgeAttachHost())
    }
}

struct BrowsSheetEdgeAttachHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let sheet = controller.presentationController as? UISheetPresentationController else { return }
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            if #available(iOS 16.0, *) {
                sheet.preferredCornerRadius = 38
            }
        }
    }
}

struct BrowsLiquidNavBarModifier: ViewModifier {
    var hidesBackground: Bool
    var tracksScroll: Bool

    func body(content: Content) -> some View {
        Group {
            if hidesBackground {
                content.toolbarBackground(.hidden, for: .navigationBar)
            } else {
                opaqueNavChrome(content)
            }
        }
    }

    @ViewBuilder
    private func opaqueNavChrome(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            let scrollTracksBar = tracksScroll
            content
                .toolbarBackground(.automatic, for: .navigationBar)
                .toolbarBackgroundVisibility(scrollTracksBar ? .automatic : .visible, for: .navigationBar)
        } else {
            content.toolbarBackground(tracksScroll ? .automatic : .visible, for: .navigationBar)
        }
    }
}

struct BundledImage: View {
    let assetName: String
    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

struct BrandMark: View {
    var assetName = "welcome_mark"
    var markSide: CGFloat = 56
    var body: some View { BundledImage(assetName: assetName).frame(width: markSide, height: markSide) }
}

/// Full-width green call-to-action.
struct PrimaryButton: View {
    let headingText: String
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var interfaceScheme

    init(_ headingText: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.headingText = headingText
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button {
            guard enabled else { return }
            action()
        } label: {
            Text(headingText).font(.ui(17, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 26)
        }
        .browsGlassProminentButtonStyle()
        .tint(Palette.brandInk)
        .controlSize(.large)
        .overlay {
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: interfaceScheme == .dark
                            ? [Color.white.opacity(0.18), Color.white.opacity(0.02)]
                            : [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
                .padding(0.5)
                .allowsHitTesting(false)
        }
    }
}

struct IconButton: View {
    let headingText: String
    let iconName: String
    let action: () -> Void
    var body: some View {
        Button(headingText, systemImage: iconName, action: action)
            .labelStyle(.iconOnly)
            .browsGlassButtonStyle()
            .buttonBorderShape(.circle)
            .controlSize(.large)
    }
}

struct SectionCaption: View {
    let draftText: String
    var body: some View {
        Text(draftText).font(.ui(13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Settings-style row with a divider.
struct PlainRow: View {
    var headingText: String
    var subtitle: String? = nil
    var iconName: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName).font(.ui(20)).foregroundStyle(Palette.brandInk).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(headingText).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 5)
    }
}

/// Icon + paragraph used in the AI notes.
struct NoticeBlock: View {
    let headingText: String
    let description: String
    var iconName = "wifi.slash"
    var action: (() -> Void)?
    var body: some View {
        ContentUnavailableView {
            Label(headingText, systemImage: iconName)
        } description: {
            Text(description)
        } actions: {
            if let action { Button("Try again", action: action).browsGlassProminentButtonStyle().tint(Palette.brandInk) }
        }
    }
}

extension Font {
    /// Fixed-size system font. Everything in the chrome uses explicit point sizes, so they all go through here.
    static func ui(_ size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}
