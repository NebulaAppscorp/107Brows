//
//  BrowserChrome.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 08/11/26.
//

import SwiftUI
import UIKit

/// UIKit button so the iOS 26 glass configuration is used.
struct NativeAddressField: UIViewRepresentable {
    let headingText: String
    let addressSpinner: Bool
    var isPrivate = false
    var isDark = false
    /// While the site panel is up the pill shows the protection shield instead of the magnifier.
    var showsShield = false
    let activate: () -> Void
    func makeUIView(context: Context) -> UIButton {
        let addressControl = UIButton(type: .system)
        addressControl.contentHorizontalAlignment = .leading
        addressControl.accessibilityIdentifier = "browser.address"
        addressControl.accessibilityLabel = "Search or enter address"
        addressControl.addAction(UIAction { _ in context.coordinator.activate() }, for: .touchUpInside)
        return addressControl
    }  
    func updateUIView(_ addressControl: UIButton, context: Context) {
        context.coordinator.activate = activate
        var buttonChrome: UIButton.Configuration = {
            if #available(iOS 26.0, *) {
                if isDark {
                    return UIButton.Configuration.plain()
                }
                return UIButton.Configuration.glass()
            }
            var plainChromeConfig = UIButton.Configuration.plain()
            plainChromeConfig.background.backgroundColor =
                isDark ? UIColor.white.withAlphaComponent(0.16) : UIColor.secondarySystemFill
            plainChromeConfig.background.cornerRadius = 18
            return plainChromeConfig
        }()
        buttonChrome.title = headingText.isEmpty ? "Search" : headingText
        buttonChrome.image =
            showsShield
            ? UIImage(systemName: "shield.lefthalf.filled")?.withTintColor(
                UIColor(Palette.brandInk), renderingMode: .alwaysOriginal)
            : UIImage(systemName: "magnifyingglass")
        buttonChrome.imagePadding = 5
        if isDark {
            buttonChrome.baseForegroundColor = .white
            if !showsShield {
                buttonChrome.image = UIImage(systemName: "magnifyingglass")?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
            }
        } else if isPrivate {
            buttonChrome.baseForegroundColor =
                headingText.isEmpty
                ? UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.7)
                : UIColor(red: 235 / 255, green: 235 / 255, blue: 245 / 255, alpha: 0.7)
            if !showsShield {
                buttonChrome.image = UIImage(systemName: "magnifyingglass")?
                    .withTintColor(
                        UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1), renderingMode: .alwaysOriginal)
            }
        } else {
            buttonChrome.baseForegroundColor =
                headingText.isEmpty
                ? UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.6)
                : UIColor(red: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 1)
        }
        buttonChrome.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        buttonChrome.cornerStyle = .capsule
        buttonChrome.titleLineBreakMode = .byTruncatingMiddle
        buttonChrome.showsActivityIndicator = addressSpinner
        buttonChrome.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { input in
            var styledField = input
            styledField.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            return styledField
        }
        addressControl.configuration = buttonChrome
    }
    func makeCoordinator() -> AddressFieldRelay { AddressFieldRelay(activate: activate) }
    final class AddressFieldRelay {
        var activate: () -> Void
        init(activate: @escaping () -> Void) { self.activate = activate }
    }
}


struct GlassCircleButton: View {
    var sfGlyph: String
    var diameter: CGFloat = 50
    var disabled = false
    var prominentStyle = false
    var iconTint: Color = Palette.brandInk
    var a11yIdentifier: String = ""
    let onTap: () -> Void

    var body: some View {
        Group {
            if prominentStyle {
                Button(action: onTap) {
                    iconLayer
                }
                .browsGlassProminentButtonStyle()
                .buttonBorderShape(.circle)
                .tint(iconTint)
            } else {
                Button(action: onTap) {
                    iconLayer
                }
                .browsGlassButtonStyle()
                .buttonBorderShape(.circle)
            }
        }
        .disabled(disabled)
        .accessibilityIdentifier(a11yIdentifier)
    }

    // Icon layer, built seperately to keep body short
    private var iconLayer: some View {
        Image(systemName: sfGlyph)
            .font(.ui(diameter >= 50 ? 19 : 15, weight: .semibold))
            .foregroundStyle(prominentStyle ? Color.white : (disabled ? Palette.mutedLabel : Color.primary)) 
            .frame(width: diameter, height: diameter)
    }
}

/// The Browse / Chat switch in the top bar.
struct SurfaceSwitch: View {
    // keeps chrome pane index
    @Binding var chromePaneIndex: Int
    var isPrivate = false

    var body: some View {
        HStack(spacing: 0) {
            surfaceModeChip(tag: 0, menuGlyph: "globe", headingText: "Browser", width: 116)
            surfaceModeChip(tag: 1, menuGlyph: "message", headingText: "Chat", width: 90)
        }
        .padding(3)
        .frame(width: 214, height: 42)
        .background {
            Capsule()
                .fill(isPrivate ? Color.white.opacity(0.14) : Palette.chromeTrack)
                .shadow(color: Palette.rgb(0x002417).opacity(isPrivate ? 0 : 0.1), radius: 6, y: 2)
                .shadow(color: Palette.rgb(0x002417).opacity(isPrivate ? 0 : 0.06), radius: 18, y: 8)
        }
        .offset(x: -1)
        .accessibilityIdentifier("browser.surface")
    }
}

// MARK: - Actions
extension SurfaceSwitch {
    // Surface mode chip
    private func surfaceModeChip(tag: Int, menuGlyph: String, headingText: String, width: CGFloat) -> some View {
        let chipActive = chromePaneIndex == tag
        return Button {
            withAnimation(.smooth(duration: 0.3)) { chromePaneIndex = tag }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: menuGlyph)
                    .font(.ui(13, weight: .regular))
                    .foregroundStyle(chipSymbolColor(chipActive: chipActive))
                    .frame(width: tag == 0 ? 16 : 17, height: 16)
                Text(headingText)
                    .font(.ui(15, weight: chipActive ? .semibold : .regular))
                    .tracking(-0.23)
                    .foregroundStyle(chipTitleColor(chipActive: chipActive))
            }
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .frame(width: width, height: 36, alignment: .leading)
            // background goes behind everything
            .background(chipBackground(chipActive: chipActive), in: Capsule())
            .shadow(color: chipActive && !isPrivate ? Color.black.opacity(0.1) : .clear, radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    // Chip symbol color
    private func chipSymbolColor(chipActive: Bool) -> Color {
        if isPrivate { return chipActive ? Palette.rgb(0x8C63FF) : Color.white.opacity(0.45) }
        return chipActive ? Palette.brandInk : Palette.mutedLabel.opacity(0.65)
    }

    // chip title color
    private func chipTitleColor(chipActive: Bool) -> Color {
        if isPrivate { return chipActive ? .white : Color.white.opacity(0.55) }
        return chipActive ? Color.primary : Palette.mutedLabel
    }

    // chip background
    private func chipBackground(chipActive: Bool) -> Color {
        if isPrivate { return chipActive ? Palette.rgb(0x0B0713) : .clear }
        return chipActive ? Palette.surfaceChipSelected : .clear
    }
}

/// Three-line menu button.
struct HamburgerGlassButton: View {
    let a11yTitle: String
    let onTap: () -> Void
    @Environment(\.colorScheme) private var interfaceScheme

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .modifier(HamburgerGlassStyle())
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().frame(width: 24, height: 2)
                    Capsule().frame(width: 24, height: 2)
                    Capsule().frame(width: 20, height: 2)
                }
                .foregroundStyle(interfaceScheme == .dark ? Color.white : Color.black)
            }
            .frame(width: 50, height: 50)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yTitle)
    }
}

struct HamburgerGlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                // drawn on top of the content
                .overlay(Circle().strokeBorder(Color.white.opacity(0.42), lineWidth: 0.75))  
        }
    }
}


/// Hamburger, address pill and the surface switch.
struct BrowserTopChrome: View {
    // local UI state
    @Binding var chromePaneIndex: Int
    var isPrivate = false
    var lensChipVisible: Bool
    var tapViewfinder: () -> Void
    var onChats: (() -> Void)? = nil
    var onNewChat: (() -> Void)? = nil

    var body: some View {
        ZStack {
            SurfaceSwitch(chromePaneIndex: $chromePaneIndex, isPrivate: isPrivate)
            HStack {
                if let onChats {
                    Button(action: onChats) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.ui(18, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(width: 50, height: 50)
                    }
                    .browsGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Chats")
                } else {
                    Color.clear.frame(width: 48, height: 1).accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                if lensChipVisible {
                    Button {
                        tapViewfinder()
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.ui(19, weight: .semibold))
                            .foregroundStyle(isPrivate ? Color.white : Color.primary)
                            .frame(width: 40, height: 40)
                    }
                    .browsGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .offset(x: 5)
                    .accessibilityLabel("Search by photo")
                } else if let onNewChat {
                    Button(action: onNewChat) {
                        Image(systemName: "square.and.pencil")
                            .font(.ui(18, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(width: 50, height: 50)
                    }
                    .browsGlassButtonStyle()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .accessibilityLabel("New chat")
                } else {
                    Spacer().frame(width: 50)
                }
            }
            .padding(.horizontal, 14)
        } 
        .frame(height: 56) 
        .frame(maxWidth: .infinity)
    }
}

/// Back, forward, share, tabs.
struct BrowserBottomBar: View {
    var canStepBack: Bool
    /// Private home only: bright back chevron.
    var isPrivate = false
    var isDark = false
    var addressTitle: String
    var addressSpinner: Bool
    /// Shield in the address pill while the site panel is open (off by default).
    var showsShield = false
    var showsAI: Bool
    var onBack: () -> Void
    var onAddress: () -> Void
    var onAI: () -> Void
    var onMenu: () -> Void


    private let circle: CGFloat = 48


    @ViewBuilder
    private func bottomCircleControl<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        if isDark {
            Button(action: action, label: label)
                .buttonStyle(.plain)
                .modifier(DarkBottomGlassModifier(shape: .circle))
        } else {
            Button(action: action, label: label)
                .browsGlassButtonStyle()
                .buttonBorderShape(.circle)
                .controlSize(.small)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            bottomCircleControl(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.ui(isPrivate ? 19 : 17, weight: .semibold))
                    .foregroundStyle(
                        isDark ? .white : isPrivate ? Color.white : canStepBack ? Palette.rgb(0x1A1A1A) : Palette.rgb(0xBFBFBF)
                    )
                    .frame(width: isDark ? circle : 40, height: isDark ? circle : 40)
                    .contentShape(Circle())
            }
            .frame(width: 50, height: 50)
            .disabled(!canStepBack && !isPrivate && !isDark)

            NativeAddressField(
                headingText: addressTitle, addressSpinner: addressSpinner, isPrivate: isPrivate, isDark: isDark,
                showsShield: showsShield, activate: onAddress
            )
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .modifier(DarkBottomGlassModifier(shape: .capsule, isEnabled: isDark))

            if showsAI {
                Button {
                    onAI()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.ui(16, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }
                .browsGlassProminentButtonStyle()
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .frame(width: 50, height: 50)
                .tint(Palette.brandInk)
                .accessibilityLabel("Ask this page")
                .accessibilityIdentifier("browser.ai")
            }

            bottomCircleControl(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(isDark ? .white : isPrivate ? Color.white : Palette.rgb(0x1A1A1A))
                    .frame(width: isDark ? circle : 40, height: isDark ? circle : 40)
                    .contentShape(Circle()) 
            }
            .frame(width: 50, height: 50)
            .accessibilityLabel("Menu")
            .accessibilityIdentifier("browser.menu")
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // background goes behind everything
        .background(Color.clear)
    }
}


struct DarkBottomGlassModifier: ViewModifier {
    enum SurfaceShape {
        case circle
        case capsule
    }

    let shape: SurfaceShape
    var isEnabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled, #available(iOS 26.0, *) {
            switch shape {
            case .circle:
                content.glassEffect(.clear.tint(.black.opacity(0.32)).interactive(), in: .circle)
            case .capsule:
                content.glassEffect(.clear.tint(.black.opacity(0.32)).interactive(), in: .capsule)
            }
        } else if isEnabled {
            switch shape {
            case .circle:
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .background(Color.black.opacity(0.22), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.34), lineWidth: 0.7))
            case .capsule:
                content
                    // background fill
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Color.black.opacity(0.22), in: Capsule())
                    // drawn on top of the content
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.34), lineWidth: 0.7))
            }
        } else {
            content
        }
    }
}
