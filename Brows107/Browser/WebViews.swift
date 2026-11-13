//
//  WebViews.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 08/11/26. 
//

import SwiftUI
@preconcurrency import WebKit
import Observation
import UIKit


struct WebPageView: UIViewRepresentable {
    let tab: BrowserTab
    let webSession: WebSession
    func makeUIView(context: Context) -> PageBleedBox {
        let box = PageBleedBox()
        box.webSessionRef = webSession
        box.attach(webSession.hostedWebView(for: tab))
        return box
    }
    func updateUIView(_ box: PageBleedBox, context: Context) {
        box.webSessionRef = webSession
        box.attach(webSession.hostedWebView(for: tab))
    }
}

/// SwiftUI keeps the representable inside the safe area. The web view is stretched to the window and ancestors are unclipped so the page covers the status bar and the home indicator. The page’s own background fills that area, so there is no empty band.  
final class PageBleedBox: UIView {
    weak var webSessionRef: WebSession?
    private weak var webLane: WKWebView?
    private var observed: WKWebView?
    private var didUnclip = false


    // attach
    func attach(_ hostName: WKWebView) {
        let replaced = webLane !== hostName
        if replaced {
            webLane?.removeFromSuperview()
            webLane = hostName
            hostName.translatesAutoresizingMaskIntoConstraints = true
            hostName.autoresizingMask = []
            addSubview(hostName)
        }
        if observed !== hostName {
            observed?.removeObserver(self, forKeyPath: "underPageBackgroundColor")
            hostName.addObserver(self, forKeyPath: "underPageBackgroundColor", options: [.new], context: nil)
            self.observed = hostName
        }
        clipsToBounds = false
        if replaced { setNeedsLayout() }
    }

    override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
    ) {
        setNeedsLayout()
    } 

    deinit {
        observed?.removeObserver(self, forKeyPath: "underPageBackgroundColor")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundColor = .clear
        clipsToBounds = false
        guard let webLane, let hostWindow = window else { return }
        unclipToWindowIfNeeded(hostWindow) 
        stretchWebLaneToWindow(webLane, hostWindow)
        clearWebLaneChrome(webLane)
        webSessionRef?.syncTopScrollInset(for: webLane)
    }

    // unclip to window if needed
    private func unclipToWindowIfNeeded(_ hostWindow: UIWindow) {
        guard !didUnclip else { return }
        self.didUnclip = true
        var ancestor: UIView? = self
        while let walkView = ancestor, walkView !== hostWindow {
            walkView.clipsToBounds = false
            walkView.layer.masksToBounds = false
            ancestor = walkView.superview
        }
    }

    // Stretch web lane to window
    private func stretchWebLaneToWindow(_ webLane: WKWebView, _ hostWindow: UIWindow) {
        let top = hostWindow.safeAreaInsets.top
        let pageBounds = CGRect(x: 0, y: top, width: hostWindow.bounds.width, height: max(0, hostWindow.bounds.height - top))
        let target = convert(pageBounds, from: hostWindow)
        if !webLane.frame.almostEqual(to: target) {
            webLane.frame = target
        }
    }

    // clears web lane chrome
    private func clearWebLaneChrome(_ webLane: WKWebView) {
        if webLane.insetsLayoutMarginsFromSafeArea { webLane.insetsLayoutMarginsFromSafeArea = false }
        let scroll = webLane.scrollView
        if scroll.insetsLayoutMarginsFromSafeArea { scroll.insetsLayoutMarginsFromSafeArea = false }
        if scroll.contentInsetAdjustmentBehavior != .never { scroll.contentInsetAdjustmentBehavior = .never }
        if webLane.backgroundColor != .clear {
            webLane.backgroundColor = .clear
            webLane.isOpaque = false
        }
        if scroll.backgroundColor != .clear { scroll.backgroundColor = .clear }
    }
}

/// Text selection menu. Explain stays third, after Copy and Look Up.
final class BrowsWebView: WKWebView {
    var explainHandler: (() -> Void)?
    var lookUpHandler: (() -> Void)?
    var allowsExplain: (() -> Bool)?
    var sampledPageColor: UIColor?
    /// While true, the comfort top inset is off so mid-page scroll is not fighting insets. Cleared at rest on top.
    var topBleedUnlocked = false

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        let canExplain = allowsExplain?() != false
        let lookUp = UIAction(title: "Look Up", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
            self?.lookUpHandler?()
        }
        let explain = UIAction(title: "Explain", image: UIImage(named: "ai_explain")) { [weak self] _ in self?.explainHandler?() }
        if builder.menu(for: .root) != nil {
            builder.replaceChildren(ofMenu: .root) { elements in
                self.filteringContextActions(from: elements)
            }
        }
        if builder.menu(for: .standardEdit) != nil {
            builder.replaceChildren(ofMenu: .standardEdit) { elements in
                self.filteringContextActions(from: elements)
            }
        }
        if builder.menu(for: .lookup) != nil {
            builder.replaceChildren(ofMenu: .lookup) { elements in self.filteringContextActions(from: elements) }
        }
        var customActions = [lookUp]
        if canExplain { customActions.append(explain) }
        let customActionMenu = UIMenu(options: .displayInline, children: customActions)
        if builder.menu(for: .standardEdit) != nil {
            builder.insertChild(customActionMenu, atEndOfMenu: .standardEdit)
        } else if builder.menu(for: .root) != nil {
            builder.insertChild(customActionMenu, atEndOfMenu: .root)
        }
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let actionName = NSStringFromSelector(action).lowercased()
        if actionName.contains("lookup") || (actionName.contains("search") && actionName.contains("web"))
            || actionName.contains("copylinkwithhighlight")
        {
            return false
        }
        return super.canPerformAction(action, withSender: sender)
    }


    // filtering context actions
    private func filteringContextActions(from elements: [UIMenuElement]) -> [UIMenuElement] {
        elements.compactMap { element in
            let title = element.title.lowercased()
            if title.contains("look up") || title.contains("lookup") || title.contains("copy link with highlight")
                || title.contains("copy link with highlights") || title.contains("ссылку с выделением")
                || (title.contains("search") && title.contains("web")) || title.contains("искать в интернете")
            {
                return nil
            }
            guard let menu = element as? UIMenu else { return element }
            return menu.replacingChildren(filteringContextActions(from: menu.children))
        }
    }
}

/// Status-bar icons follow the page color, not the device theme, so a light site stays readable in a dark app.
struct PageStatusBar: UIViewControllerRepresentable {
    var lightBackground: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }


    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.lightBackground = lightBackground
        controller.refresh()
    }

    final class Controller: UIViewController {  
        var lightBackground = false
        override var preferredStatusBarStyle: UIStatusBarStyle { lightBackground ? .darkContent : .lightContent }
        override func didMove(toParent parent: UIViewController?) { refresh() }
        // refreshes it
        func refresh() {
            setNeedsStatusBarAppearanceUpdate()
            parent?.setNeedsStatusBarAppearanceUpdate()
            navigationController?.setNeedsStatusBarAppearanceUpdate()
        }
    }  
}
