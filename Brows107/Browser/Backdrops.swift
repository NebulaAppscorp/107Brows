//
//  Backdrops.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 08/10/26.
//

import SwiftUI
import UIKit


/// Chat backdrop: the blobs are mirrored compared with the browser home.
struct ChatHomeBackdrop: View {
    @Environment(\.colorScheme) private var interfaceScheme
    private let washBlobs: [(x: CGFloat, y: CGFloat, stageWidth: CGFloat, h: CGFloat, color: Color, blur: CGFloat)] = [
        (132, -130, 400, 330, Palette.rgb(0x1FB6A6), 140),
        (-118, -160, 360, 300, Palette.brandInk, 150),
        (-48, -90, 440, 280, Palette.rgb(0x00B37A), 140),
        (122, 40, 400, 250, Palette.brandWash, 130),
    ]
    private var k: CGFloat { 0.42 }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 402
            let opacity = interfaceScheme == .dark ? 0.17 : 1
            ZStack(alignment: .topLeading) {
                Palette.canvasView
                ForEach(Array(washBlobs.enumerated()), id: \.offset) { _, blob in
                    Ellipse()  
                        .fill(blob.color.opacity(opacity))
                        .frame(width: blob.stageWidth * s, height: blob.h * s)
                        .blur(radius: blob.blur * s * k)
                        .offset(x: blob.x * s, y: blob.y * s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // background goes behind everything
        .background(Palette.canvasView)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Light shell is top_glow, private shell is top_glow_private.
/// Same picture sits behind the status bar, the browser home, and chat.
struct ShellBackdrop: View {
    // vault
    @Environment(BrowserStore.self) private var vault
    @Environment(\.colorScheme) private var interfaceScheme

    var body: some View {
        let assetName = vault.incognito ? "top_glow_private" : AssetCatalog.topGlow
        if vault.incognito || vault.prefersLightBackdropArt(systemScheme: interfaceScheme) {
            TopGlowBackdrop(assetName: assetName)
        } else if vault.chromePane == 1 {
            ChatHomeBackdrop()
        } else {
            BrowserHomeBackdrop()
        }
    }
}

/// Decodes the full-screen PNGs once — repeated `Image(name:)` in a TabView was stuttering scroll.
enum BackdropCache {
    private nonisolated(unsafe) static var decodedValue: [String: UIImage] = [:]
    private static let gate = NSLock()

    // ui image
    static func uiImage(assetName: String) -> UIImage? {
        let asset = assetName
        gate.lock()
        if let hit = decodedValue[asset] {
            gate.unlock()
            return hit
        }
        gate.unlock()
        guard let image = UIImage(named: asset) else { return nil }
        gate.lock()
        decodedValue[asset] = image
        gate.unlock()
        return image
    }
}

/// Full-screen raster pinned to the top of the screen, including the status bar.
/// Shell: The shell glow and its private variant share this view.
struct TopGlowBackdrop: View {
    let assetName: String
    // local UI state
    @State private var rasterBitmap: UIImage?

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(geo.size.height, 1)
            if let uiImage = rasterBitmap {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
            } else {
                Palette.canvasView
                    .frame(width: width, height: height)
            }
        }
        .task(id: assetName) {
            let node = assetName
            let image = await Task.detached(priority: .utility) {
                RasterImageBox(image: BackdropCache.uiImage(assetName: node))
            }.value.image
            self.rasterBitmap = image
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct RasterImageBox: @unchecked Sendable {
    let image: UIImage?
}

/// Light appearance uses the bitmap; dark keeps the programmatic blob fallback.
struct ArtworkBackdrop<Fallback: View>: View {
    let assetName: String
    var useArtwork = true
    @ViewBuilder var darkBackdrop: Fallback

    var body: some View {
        if useArtwork {
            TopGlowBackdrop(assetName: assetName)
        } else {
            darkBackdrop
        }
    }
}

/// Lets the single shell picture show through the status bar and the page.
struct ClearHostBackdrop: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {} 

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        } 

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard let hostWindow = view.window else { return }
            var ancestor = view.superview
            while let host = ancestor, host !== hostWindow {
                host.backgroundColor = .clear
                host.isOpaque = false
                ancestor = host.superview
            }
            if let nav = sequence(first: view as UIResponder, next: { $0.next }).compactMap({ $0 as? UINavigationController })
                .first
            {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                nav.navigationBar.standardAppearance = appearance
                nav.navigationBar.scrollEdgeAppearance = appearance
                nav.navigationBar.compactAppearance = appearance
                nav.navigationBar.isTranslucent = true
            }
        }
    }
}

/// iOS 26 draws a soft blur at the top and bottom of a scroll view whenever a bar is nearby.
/// SwiftUI turns that blur back on after layout, so this view keeps it off.
/// The home scroll view is laid out inside the status bar and the home indicator, which leaves an empty band above the heading and under the toolbar.
struct HomeScreenBleed: UIViewControllerRepresentable {
    /// Safe area insets plus the home ScrollView minY in window coordinates (for the top padding).
    var onLayout: (UIEdgeInsets, CGFloat) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onLayout = onLayout
        return controller
    }


    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onLayout = onLayout
    }

    final class Controller: UIViewController {
        var onLayout: ((UIEdgeInsets, CGFloat) -> Void)?
        private var lastInsets: UIEdgeInsets?
        private var lastScrollTop: CGFloat?
        private weak var trackedScroll: UIScrollView?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            trackedScroll = nil
            lastScrollTop = nil
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard let hostWindow = view.window else { return }
            let insets = hostWindow.safeAreaInsets
            guard let root = view.superview else { return }
            guard let scroll = trackedScroll ?? Self.preferredScroll(in: root) else { return }
            trackedScroll = scroll
            if scroll.contentInsetAdjustmentBehavior != .never { scroll.contentInsetAdjustmentBehavior = .never }
            if scroll.contentInset != .zero { scroll.contentInset = .zero }
            scroll.clipsToBounds = false
            if let host = scroll.superview {
                let target = host.convert(hostWindow.bounds, from: hostWindow)
                if scroll.frame != target { scroll.frame = target }
            }
            if scroll.backgroundColor != .clear { scroll.backgroundColor = .clear }
            if scroll.isOpaque { scroll.isOpaque = false }
            var ancestor = scroll.superview
            while let host = ancestor, host !== hostWindow {
                if host.backgroundColor != .clear { host.backgroundColor = .clear }
                if host.isOpaque { host.isOpaque = false }
                ancestor = host.superview
            }
            if let nav = sequence(first: view, next: { $0.next }).first(where: { $0 is UINavigationController })
                as? UINavigationController
            {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                nav.navigationBar.standardAppearance = appearance
                nav.navigationBar.scrollEdgeAppearance = appearance
                nav.navigationBar.compactAppearance = appearance
                nav.navigationBar.isTranslucent = true
            }
            if #available(iOS 26.0, *) {
                scroll.topEdgeEffect.isHidden = true
                scroll.bottomEdgeEffect.isHidden = true
            }
            let scrollTop = scroll.convert(CGPoint.zero, to: hostWindow).y
            let insetsChanged = lastInsets != insets
            let scrollTopChanged = lastScrollTop.map { abs($0 - scrollTop) > 0.5 } ?? true
            guard insetsChanged || scrollTopChanged else { return }
            lastInsets = insets
            lastScrollTop = scrollTop
            DispatchQueue.main.async { [weak self] in self?.onLayout?(insets, scrollTop) }
        } 

        // preferred scroll
        private static func preferredScroll(in root: UIView) -> UIScrollView? {
            var scrolls: [UIScrollView] = []
            // walk
            func walk(_ hostName: UIView) {
                if let scroll = hostName as? UIScrollView { scrolls.append(scroll) }
                for child in hostName.subviews { walk(child) }
            }
            walk(root)
            return scrolls.max(by: { $0.bounds.height < $1.bounds.height })
        }
    }
}
