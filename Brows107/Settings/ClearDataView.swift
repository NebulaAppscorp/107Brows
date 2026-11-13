//
//  ClearDataView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 11/10/26.
//

import SwiftUI
import StoreKit
import WebKit


/// Clear browsing data: toggles, footnote, red Clear button, confirm alert and toast.
struct ClearDataView: View {
    let webLane: WebSession
    @Environment(BrowserStore.self) private var vault
    @Environment(\.colorScheme) private var interfaceScheme
    @State private var clearHistory = true
    @State private var cookies = true
    @State private var cache = false
    @State private var aiAnswers = false
    @State private var confirm = false
    @State private var busy = false
    @State private var showToast = false
    private let separator = Palette.rgb(0xD6E2DC)
    private var hasSelection: Bool { clearHistory || cookies || cache || aiAnswers }
    private var cardFill: Color {
        interfaceScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : .white
    }
    private var screenFill: Color {
        interfaceScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Palette.rgb(0xF2F5F3)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    clearToggle("History", isOn: $clearHistory)
                    rowDivider
                    clearToggle("Cookies and site data", isOn: $cookies)
                    rowDivider
                    clearToggle("Cached files", isOn: $cache)
                    rowDivider
                    clearToggle("AI answers", isOn: $aiAnswers)
                }
                .background(cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("Clearing history also removes AI answers saved with those pages.")
                    .font(.ui(12))
                    .browsExactLineHeight(16)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                Button {
                    self.confirm = true
                } label: {
                    Text(busy ? "Clearing…" : "Clear")
                        .font(.ui(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Palette.rgb(0xFF383C), in: Capsule())
                }
                .buttonStyle(.plain)
                .opacity(hasSelection && !busy ? 1 : 0.4)
                .disabled(!hasSelection || busy)
                .padding(.top, 26)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12) 

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(screenFill.ignoresSafeArea())
        .navigationTitle("Clear browsing data")
        .navigationBarTitleDisplayMode(.inline)
        .browsLiquidNavBar()
        // drawn on top of the content
        .overlay(alignment: .top) {
            if showToast {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Palette.brandInk)
                        .frame(width: 18, height: 18)
                    Text("Data cleared")
                        .font(.ui(15))
                        .browsExactLineHeight(20)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
                // enter/leave animation
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // smooth transition between states
        .animation(.smooth(duration: 0.25), value: showToast)
        .alert("Clear selected data?", isPresented: $confirm) {
            Button("Clear", role: .destructive) { performClear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }


    // row divider
    private var rowDivider: some View {
        Rectangle().fill(separator).frame(height: 1).padding(.leading, 16)
    }
}  


// MARK: - Helpers
extension ClearDataView {
    // Clears toggle
    private func clearToggle(_ headingText: String, isOn: Binding<Bool>) -> some View {  
        Toggle(isOn: isOn) {
            Text(headingText)
                .font(.ui(17))
                .browsExactLineHeight(22)
        }
        .tint(Palette.brandInk)
        .padding(.horizontal, 16)
        .frame(height: 54)
    }


    // Runs the selected wipes and shows the toast.
    private func performClear() {
        let wipeHistory = clearHistory
        let wipeCookies = cookies
        let wipeCache = cache
        let wipeAI = aiAnswers
        busy = true
        Task {
            if wipeHistory {
                self.vault.visitLedger.removeAll()
                vault.flushSnapshot()
            }
            if wipeHistory || wipeAI {
                vault.clearAiAnswers()
            }
            var types = Set<String>()
            if wipeCookies {
                types.formUnion([
                    WKWebsiteDataTypeCookies,
                    WKWebsiteDataTypeLocalStorage,
                    WKWebsiteDataTypeSessionStorage,
                    WKWebsiteDataTypeIndexedDBDatabases,
                ])
            }
            if wipeCache {
                types.formUnion([
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache,
                    WKWebsiteDataTypeOfflineWebApplicationCache,
                ])
            }
            if !types.isEmpty {
                await WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast)
            }
            self.clearHistory = false
            cookies = false
            cache = false
            aiAnswers = false
            busy = false
            showToast = true
            do {
                try await Task.sleep(for: .seconds(2.2))
            } catch {
                logSwallowed(error)
            }
            showToast = false
        }
    }
}
