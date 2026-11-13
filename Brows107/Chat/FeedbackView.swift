//
//  FeedbackView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/10/26.
//

import SwiftUI
import PhotosUI
import AVFoundation


enum FeedbackSheetPhase {
    case editing, sent
}

/// Thumbs-down reasons sheet.
struct FeedbackView: View {
    // local UI state
    @Environment(\.dismiss) private var dismissSheet
    @Environment(BrowserStore.self) private var vault
    @State private var selection: Set<String> = []
    @State private var draftText = ""
    @State private var feedbackPhase: FeedbackSheetPhase = .editing
    private let reasons = [
        "Not accurate", "Missing important details", "Not about this page", "Hard to read", "Unsafe or offensive",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What went wrong?").font(.ui(20)).foregroundStyle(.primary)
                Spacer()
                Button {
                    dismissSheet()
                } label: {
                    Image(systemName: "checkmark").font(.ui(16, weight: .semibold)).foregroundStyle(.white).frame(
                        width: 34, height: 34)
                }
                .browsGlassProminentButtonStyle().buttonBorderShape(.circle).tint(Palette.brandInk).accessibilityLabel("Done")
            }.padding(.horizontal, 20).padding(.top, 20).frame(height: 70)
            switch feedbackPhase {
            case .sent:
                result(
                    "feedback_done", "Thanks — got it", "We read every report. It helps make the next answer better.",
                    retry: false)
            case .editing: feedbackFormPane
            }
        }
        // smooth transition between states
        .animation(.smooth(duration: 0.3), value: feedbackPhase)
        .background(Palette.canvasView)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        // kicked off here so it cancels with the view
        .task {
            if vault.launchScenario == "feedback" { selection = ["Not accurate", "Missing important details"] }
            if vault.launchScenario == "feedback-sent" { feedbackPhase = .sent }
            if vault.launchScenario == "feedback-error" { feedbackPhase = .sent }
        }
    }
    // feedback form pane
    private var feedbackFormPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pick anything that applies. Optional, but it helps.").font(.ui(15)).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
            VStack(spacing: 0) {
                ForEach(Array(reasons.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Divider().padding(.leading, 16) }
                    Button {
                        if selection.contains(item) { selection.remove(item) } else { selection.insert(item) }
                    } label: {
                        HStack {
                            Text(item).font(.ui(17)).foregroundStyle(.primary)
                            Spacer()
                            Image(selection.contains(item) ? "check_on" : "check_off").resizable().frame(width: 22, height: 22)
                        }
                        .padding(.horizontal, 16).frame(height: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 0)
            Spacer(minLength: 20)
            TextField("Tell us more (optional)", text: $draftText, axis: .vertical).font(.ui(17)).lineLimit(3...4)
                .padding(16).frame(height: 84, alignment: .top)
                // overlay lives outside the layout
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 1))
                .padding(.horizontal, 20)
            Text("The answer and the page address are sent with your report.").font(.ui(12)).foregroundStyle(.tertiary)
                .padding(.horizontal, 20).padding(.top, 16)
            Button {
                feedbackPhase = .sent
            } label: {
                Text("Send feedback").font(.ui(17, weight: .semibold)).foregroundStyle(.white).frame(
                    maxWidth: .infinity
                ).frame(height: 50).background(Palette.brandInk, in: Capsule())
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
        }
    }
    // result
    private func result(_ asset: String, _ t: String, _ d: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(asset).resizable().frame(width: 56, height: 56)
            Text(t).font(.ui(17, weight: .semibold))
            Text(d).font(.ui(15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if retry {
                Button("Try again") { feedbackPhase = .editing }.browsGlassProminentButtonStyle().tint(Palette.brandInk).padding(
                    .top, 6)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(.horizontal, 30)
    }
}
