//
//  KeyboardDismissHost.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 07/11/26.
//

import SwiftUI
import UIKit

/// Tap anywhere outside a field to dismiss the keyboard without eating the tap.
struct KeyboardDismissHost: UIViewRepresentable {
    var dismissGesturesOn = true

    func makeCoordinator() -> KeyboardTapRelay { KeyboardTapRelay() }

    func makeUIView(context: Context) -> UIView {
        let hostName = UIView(frame: .zero)
        hostName.isUserInteractionEnabled = false
        context.coordinator.dismissGesturesOn = dismissGesturesOn
        context.coordinator.wireToWindow(from: hostName)
        return hostName
    }

    func updateUIView(_ hostName: UIView, context: Context) {
        context.coordinator.syncKeyboardHost(dismissGesturesOn: dismissGesturesOn, anchorView: hostName)
    }

    static func dismantleUIView(_ hostName: UIView, coordinator: KeyboardTapRelay) {
        coordinator.unwireFromWindow()
    }

    @MainActor
    final class KeyboardTapRelay: NSObject, UIGestureRecognizerDelegate {
        private weak var anchorView: UIView?
        private weak var dismissHostWindow: UIWindow?
        private var tapDismissRecognizer: UITapGestureRecognizer?
        var dismissGesturesOn = true {
            didSet { tapDismissRecognizer?.isEnabled = dismissGesturesOn }
        }

        // keeps keyboard host in sync
        func syncKeyboardHost(dismissGesturesOn: Bool, anchorView hostName: UIView) {
            self.dismissGesturesOn = dismissGesturesOn
            if self.anchorView === hostName, tapDismissRecognizer != nil {
                tapDismissRecognizer?.isEnabled = dismissGesturesOn
                return
            }
            wireToWindow(from: hostName)
        }

        // Gesture goes on the window, not the view, so scroll views keep working.
        func wireToWindow(from hostName: UIView) {
            anchorView = hostName
            tapDismissRecognizer?.isEnabled = dismissGesturesOn
            DispatchQueue.main.async { [weak self, weak hostName] in
                guard let self, let hostName else { return }
                let hostWindow = hostName.window
                if hostWindow == nil { return }
                if self.dismissHostWindow === hostWindow {
                    self.tapDismissRecognizer?.isEnabled = self.dismissGesturesOn
                    return
                }
                self.unwireFromWindow()
                let tapDismissRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.endEditingOnTap))
                tapDismissRecognizer.cancelsTouchesInView = false
                tapDismissRecognizer.delaysTouchesBegan = false
                tapDismissRecognizer.delaysTouchesEnded = false
                tapDismissRecognizer.isEnabled = self.dismissGesturesOn
                tapDismissRecognizer.delegate = self
                hostWindow?.addGestureRecognizer(tapDismissRecognizer)
                self.dismissHostWindow = hostWindow
                self.tapDismissRecognizer = tapDismissRecognizer
            }
        }

        // unwire from window
        func unwireFromWindow() {
            if let tapDismissRecognizer { dismissHostWindow?.removeGestureRecognizer(tapDismissRecognizer) }
            tapDismissRecognizer = nil
            dismissHostWindow = nil
        }

        // end editing on tap
        @objc private func endEditingOnTap() {
            guard dismissGesturesOn else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.dismissGesturesOn else { return }
                self.dismissHostWindow?.endEditing(true)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard dismissGesturesOn else { return false }
            var hostName = touch.view
            while let current = hostName {
                if current is UITextField || current is UITextView || current is UIControl { return false }
                hostName = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
