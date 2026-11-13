//
//  PaywallView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 28/10/26.
//

import SwiftUI
import StoreKit

/// Plan picker and purchase button; purchasing lives in PurchaseStore.
struct PaywallView: View {
    let dismissHandler: () -> Void
    // view state
    @State private var purchase = PurchaseStore()
    @Environment(BrowserStore.self) private var vault
    @Environment(\.colorScheme) private var interfaceScheme
    private var usesSampleData: Bool { vault.launchScenario != nil }

    var body: some View {
        ZStack {
            paywallBackdrop
            VStack(spacing: 0) {
                HStack {
                    IconButton(headingText: "Close", iconName: "xmark", action: dismissHandler)
                        .foregroundStyle(interfaceScheme == .dark ? Color.white : Color.primary)
                        .tint(interfaceScheme == .dark ? Color.white : Color.primary)
                        .frame(width: 44, height: 44)
                        .accessibilityIdentifier("paywall.close")
                    Spacer()
                    Button("Restore") { Task { await purchase.restoreEntitlements() } }
                        .font(.ui(15, weight: .semibold))
                        .foregroundStyle(interfaceScheme == .dark ? Color.white : Color.primary)
                        .browsGlassButtonStyle()
                        .controlSize(.large)
                        .tint(interfaceScheme == .dark ? Color.white : Color.primary)
                        .frame(width: 104, height: 40)
                        .disabled(purchase.busy)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .frame(height: 56) 

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Ask as much as you want")
                            .font(.ui(28, weight: .semibold))
                            .tracking(0.38)
                            .foregroundStyle(.primary)

                        Text("Unlimited answers, unlimited photo search and longer pages.")
                            .font(.ui(15))
                            .browsExactLineHeight(20)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)

                        HStack(spacing: 6) {
                            Image("paywall_stars")
                                .renderingMode(.original)
                                .resizable()
                                .frame(width: 88, height: 14)
                                .accessibilityHidden(true)
                            Text("4.8  ·  12k ratings in the App Store")
                                .font(.ui(12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 14)

                        self.perksPanel.padding(.top, 24)

                        VStack(spacing: 10) {
                            paywallPlanTile("yearly", headingText: "Yearly", price: "$119.99")
                            paywallPlanTile("weekly", headingText: "Weekly", price: "$4.99")
                        }
                        .padding(.top, 28)

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image("paywall_tick")
                                    .renderingMode(.original)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .accessibilityHidden(true)
                                Text("Secure payment · Cancel anytime")
                                    .font(.ui(12))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8) 

                            Button {
                                Task { await purchase.commitPurchase() }
                            } label: {
                                Text(purchase.busy ? "Please wait…" : purchaseCTALabel)
                                    .font(.ui(17, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 20)
                            }  
                            .browsGlassProminentButtonStyle()
                            .tint(Palette.brandInk)
                            .controlSize(.large)
                            .disabled(purchase.busy)
                            .accessibilityIdentifier("paywall.purchase")

                            HStack(spacing: 4) {
                                Button("Privacy Policy") { vault.openLegal(.privacy) }
                                Text("·")
                                Button("Restore") { Task { await purchase.restoreEntitlements() } }
                                    .disabled(purchase.busy)
                                Text("·")
                                Button("Terms of Use") { vault.openLegal(.terms) }
                            }
                            .font(.ui(12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                        .padding(.top, 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        // runs every time the view shows up
        .onAppear { PaywallLog.paywallPresented(scenario: vault.launchScenario) }
        .task { if !usesSampleData { await purchase.fetchProducts() } }
        .onChange(of: purchase.entitlementActive) { _, slot in
            if slot {
                self.vault.proEntitlementActive = true
                dismissHandler()
            }
        }
        .alert(
            "Subscription",
            isPresented: Binding(get: { purchase.checkoutNotice != nil }, set: { if !$0 { purchase.checkoutNotice = nil } })
        ) {
            Button("OK", role: .cancel) { purchase.checkoutNotice = nil }
            Button("Try again") { Task { await purchase.fetchProducts() } }
        } message: {
            Text(purchase.checkoutNotice ?? "")
        }
    }

    private var purchaseCTALabel: String {
        guard purchase.pickedPlanID == "yearly", !usesSampleData else { return "Continue" }
        if purchase.chosenProduct?.subscription?.introductoryOffer != nil {
            return "Start 3-day free trial"
        }
        return "Continue"
    }

    @ViewBuilder
    private var paywallBackdrop: some View {
        if interfaceScheme == .dark {
            ZStack(alignment: .top) {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                LinearGradient(
                    colors: [Palette.rgb(0x087D57).opacity(0.52), Palette.rgb(0x0A503B).opacity(0.2), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 520)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
        } else {
            ArtworkBackdrop(
                assetName: AssetCatalog.topGlow, useArtwork: vault.prefersLightBackdropArt(systemScheme: interfaceScheme)
            ) {
                BrowserHomeBackdrop()
            }
        }
    }

    // the perks panel block
    private var perksPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            benefitRow("Unlimited answers", "Ask anything, any time — no daily limits.", "text.bubble")
            benefitRow("Photo search", "Snap a photo to solve, translate or identify.", "camera.viewfinder")
            benefitRow("Longer pages", "Get detailed answers and long-form texts.", "doc.text")
            benefitRow("Faster responses", "Priority access, even at peak hours.", "bolt.fill")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (interfaceScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color.white),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Palette.rgb(0x002417).opacity(0.06), radius: 8, y: 2)
        .shadow(color: Palette.rgb(0x002417).opacity(0.05), radius: 30, y: 14) 
    }
}

// MARK: - Private helpers
extension PaywallView {
    // benefit row
    private func benefitRow(_ headingText: String, _ subtitle: String, _ iconName: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.ui(14))
                .foregroundStyle(Palette.brandInk)
                .frame(width: 30, height: 30)
                // background goes behind everything
                .background(Palette.brandWash, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(headingText)
                    .font(.ui(15, weight: .semibold))
                Text(subtitle)
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }


    // paywall plan tile
    private func paywallPlanTile(_ id: String, headingText: String, price: String) -> some View {
        let planActive = purchase.pickedPlanID == id
        return Button {
            self.purchase.pickedPlanID = id
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(planActive ? Palette.brandInk : Color(uiColor: .tertiarySystemFill))
                    .frame(width: 22, height: 22)
                Text(headingText)
                    .font(.ui(17, weight: .semibold))
                Spacer(minLength: 4)
                Text(usesSampleData ? price : purchase.storeProduct(forPlanID: id)?.displayPrice ?? "—")
                    .font(.ui(17, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(planActive ? Palette.brandWash : Palette.paywallUnselected, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(planActive ? Palette.brandInk : Palette.paywallUnselectedStroke, lineWidth: planActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.\(id)")
        .accessibilityAddTraits(planActive ? .isSelected : [])
    }
}
