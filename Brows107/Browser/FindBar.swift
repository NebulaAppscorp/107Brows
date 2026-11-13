//
//  FindBar.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 07/10/26.
//

import SwiftUI
import UIKit


/// Find-in-page bar with previous / next.
struct FindOnPageBar: View {
    @Binding var draftText: String
    var matchIndex: Int
    var matchCount: Int
    // work out the auto focus
    var autoFocus = false
    var onQueryChange: (String) -> Void
    var onSubmit: () -> Void
    var onPrev: () -> Void
    var onNext: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.ui(14))
                    .foregroundStyle(Palette.mutedLabel.opacity(0.55))
                FindTextInput(draftText: $draftText, autoFocus: autoFocus, onSubmit: onSubmit)
                    // react to the change here
                    .onChange(of: draftText) { _, text in onQueryChange(text) }
                VoiceInputButton(draftText: $draftText)
                if !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("\(matchIndex) of \(matchCount)")
                        .font(.ui(13))
                        .foregroundStyle(Palette.mutedLabel)
                }
            }
            // spacing from the design
            .padding(.horizontal, 14)
            // Fixed size from the design
            .frame(maxWidth: .infinity)
            // size matches the mock
            .frame(height: 44)
            .background(Palette.raisedFill, in: Capsule())
            .browsGlassCapsule()  

            HStack(spacing: 0) {
                // Tap handler below
                Button {
                    onPrev()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ui(16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Previous match")
                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.ui(16, weight: .semibold))
                        .foregroundStyle(Color.primary) 
                        // size matches the mock
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Next match")
            }
            .frame(width: 72, height: 44)
            .background(Palette.raisedFill, in: Capsule())
            .browsGlassCapsule()

            Button {
                onDone() 
            } label: {
                Image(systemName: "checkmark")
                    .font(.ui(17, weight: .semibold))
                    .foregroundStyle(.white)
                    // Fixed size from the design
                    .frame(width: 44, height: 44)
                    .contentShape(Circle()) 
            }
            .buttonStyle(.plain)
            // background goes behind everything
            .background(Palette.brandInk, in: Circle())
            .browsGlassCircle()
            // size matches the mock
            .frame(width: 44, height: 44)
        }
        // spacing from the design
        .padding(.horizontal, 16)
        // Spacing from the design
        .padding(.vertical, 8)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .task {
            onQueryChange(draftText)
        }
    }
}

struct FindTextInput: UIViewRepresentable {
    // injected state
    @Binding var draftText: String
    var autoFocus: Bool
    var onSubmit: () -> Void


    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = LockedFindTextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 17)  
        field.textColor = .label
        field.tintColor = UIColor(Palette.brandInk)
        field.placeholder = "Find"
        field.returnKeyType = .search
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .never
        field.accessibilityLabel = "Find on page"
        field.text = draftText
        field.preventResignWhileFinding = autoFocus
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if let findField = field as? LockedFindTextField {
            findField.preventResignWhileFinding = autoFocus
        }
        if field.text != draftText { field.text = draftText }
        guard autoFocus, !field.isFirstResponder, !context.coordinator.focusRequestScheduled else { return }
        context.coordinator.focusRequestScheduled = true
        DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
            guard let field, let coordinator else { return }
            coordinator.focusRequestScheduled = false
            guard field.window != nil, !field.isFirstResponder, coordinator.parent.autoFocus else { return }
            field.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        if let findField = field as? LockedFindTextField {
            findField.preventResignWhileFinding = false
        }
        field.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FindTextInput
        var focusRequestScheduled = false

        init(parent: FindTextInput) {
            self.parent = parent
        }

        // Text changed
        @objc func textChanged(_ sender: UITextField) {
            parent.draftText = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

final class LockedFindTextField: UITextField {
    var preventResignWhileFinding = false

    override func resignFirstResponder() -> Bool {
        if preventResignWhileFinding { return false }
        return super.resignFirstResponder()
    }
} 
