//
//  ProtectionViews.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 05/11/26.
//

import SwiftUI
import StoreKit
import WebKit


/// Blocked counters and per-shield switches.
struct ProtectionView: View {
    let webLane: WebSession
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @State private var howItWorksOpen = false
    private let separator = Palette.rgb(0xD6E2DC)

    var body: some View {
        @Bindable var vault = vault
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        hero
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12)
                        {
                            statistic("shield.lefthalf.filled", groupedFill(vault.tallyAds), "Ads blocked")
                            statistic("eye.slash", groupedFill(vault.tallyTrackers), "Trackers blocked")
                            statistic("arrow.turn.up.right", groupedFill(vault.tallyRedirects), "Redirects stopped")
                            statistic("exclamationmark.shield", "0", "Unsafe sites")
                        }
                        .padding(.top, 4)

                        VStack(spacing: 0) {
                            protectionToggle("Block ads", isOn: $vault.shieldAds)
                            divider
                            protectionToggle("Block trackers", isOn: $vault.shieldTrackers)
                            divider
                            protectionToggle("Block redirects", isOn: $vault.shieldRedirects)
                            divider
                            NavigationLink {
                                ExceptionsView()
                            } label: {
                                disclosureRow("Manage exceptions", rotated: false)
                            }
                            .buttonStyle(.plain)
                            divider
                            Button {
                                withAnimation(.smooth(duration: 0.28)) { howItWorksOpen.toggle() }
                            } label: {
                                disclosureRow("How it works", rotated: howItWorksOpen)
                            }
                            .buttonStyle(.plain)
                            if howItWorksOpen {
                                Text(
                                    "Requests to known ad and tracker domains are blocked with bundled AdGuard-based filter lists, plus light cosmetic hiding for common ad slots. Turn protection off for a site if something breaks."
                                )
                                .font(.ui(14)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        // background goes behind everything
                        .background(
                            Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(
                Color(
                    uiColor: UIColor {
                        $0.userInterfaceStyle == .dark
                            ? .systemGroupedBackground : UIColor(red: 242 / 255, green: 245 / 255, blue: 243 / 255, alpha: 1)
                    }
                ).ignoresSafeArea()
            )
            .navigationTitle("Protection")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .browsLiquidNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismissSheet()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .onChange(of: vault.shieldAds) { _, _ in vault.writeShieldPrefs() }
        .onChange(of: vault.shieldTrackers) { _, _ in vault.writeShieldPrefs() }
        .onChange(of: vault.shieldRedirects) { _, _ in vault.writeShieldPrefs() }
    }

    // divider
    private var divider: some View {
        Rectangle().fill(separator).frame(height: 1).padding(.leading, 16)
    }

    // hero row
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark.shield.fill")
                .font(.ui(30)).browsExactLineHeight(34)
                .foregroundStyle(.white)
            Text(protectionHeadline)
                .font(.ui(20, weight: .semibold)).browsExactLineHeight(26)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 15)
            Text("Ads, trackers and redirects are filtered before the page loads.")
                .font(.ui(15)).browsExactLineHeight(20)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .frame(height: 190)
        // background goes behind everything
        .background(
            LinearGradient(
                colors: [Palette.brandInk, Palette.rgb(0x00B37A)], startPoint: UnitPoint(x: 0.076, y: -0.305),
                endPoint: UnitPoint(x: 0.698, y: 0.876)), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

// MARK: - Actions
extension ProtectionView {
    // Disclosure row
    private func disclosureRow(_ headingText: String, rotated: Bool) -> some View {
        HStack {
            Text(headingText).font(.ui(17)).browsExactLineHeight(22).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.ui(15, weight: .semibold)).foregroundStyle(
                Color(uiColor: .tertiaryLabel)
            )
            .rotationEffect(.degrees(rotated ? 90 : 0))
        }
        .padding(.horizontal, 16).frame(height: 48).contentShape(Rectangle())
    }

    // statistic
    private func statistic(_ iconName: String, _ number: String, _ headingText: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: iconName).font(.ui(15)).foregroundStyle(Palette.brandInk).frame(
                height: 18, alignment: .center)
            Text(number).font(.ui(22, weight: .semibold)).browsExactLineHeight(28).foregroundStyle(.primary).padding(
                .top, 6)
            Text(headingText).font(.ui(12)).browsExactLineHeight(16).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(height: 96)
        // background goes behind everything
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Palette.rgb(0x001A12).opacity(0.13), radius: 4, y: 2)
        .shadow(color: Palette.rgb(0x001A12).opacity(0.03), radius: 10, y: 4)
    }

    private var protectionHeadline: String {
        let total = vault.tallyAds + vault.tallyTrackers + vault.tallyRedirects
        if vault.launchScenario != nil { return "Browse with protection" }
        return total > 0 ? "Blocked \(groupedFill(total)) requests" : "Browse with protection"
    }

    // Grouped fill
    private func groupedFill(_ slot: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: slot)) ?? "\(slot)"
    }

    // protection toggle
    private func protectionToggle(_ headingText: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(headingText).font(.ui(17)).browsExactLineHeight(22) }
            .tint(Palette.brandInk)
            .padding(.horizontal, 16)
            .frame(height: 54)
    }
}

/// Sites where blocking is off.
struct ExceptionsView: View {
    @Environment(BrowserStore.self) private var vault
    @State private var exceptionDraft = ""
    var body: some View {
        List {
            Section {
                HStack {
                    TextField("example.com", text: $exceptionDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Add") {
                        if let domain = AddressResolver.coerceNavigableURL(exceptionDraft)?.host,
                            !vault.shieldExceptions.contains(domain)
                        {
                            vault.shieldExceptions.append(domain)
                            vault.writeShieldPrefs()
                            exceptionDraft = ""
                        }
                    }.disabled(exceptionDraft.isEmpty)
                }
            }
            Section("Protection is off for these sites") {
                ForEach(vault.shieldExceptions, id: \.self) { Text($0) }.onDelete {
                    vault.shieldExceptions.remove(atOffsets: $0)
                    vault.writeShieldPrefs()
                }
            }
        }.navigationTitle("Exceptions")
    }
}

/// Popover with the current site protection status.
struct SitePanelView: View {
    let webLane: WebSession
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    private var siteHostname: String { vault.currentTab?.pageURL?.host ?? "This site" }
    private var protected: Bool { !vault.shieldExceptions.contains(vault.currentTab?.pageURL?.host ?? "") }
    private var summary: String {
        if !protected { return "Protection is off for this site" }
        return vault.blockedTally > 0 ? "\(vault.blockedTally) blocked on this page" : "Ads and trackers are blocked"
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: protected ? "checkmark.shield.fill" : "shield.slash").foregroundStyle(Palette.brandInk)
                    Text(siteHostname).font(.body.weight(.semibold))
                }
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)
            Divider().padding(.leading, 16)
            Toggle(
                "Protection on this site",
                isOn: Binding(
                    get: { protected },
                    set: { enabled in
                        guard let host = vault.currentTab?.pageURL?.host else { return }
                        if enabled {
                            vault.shieldExceptions.removeAll { $0 == host }
                        } else if !vault.shieldExceptions.contains(host) {
                            vault.shieldExceptions.append(host)
                        }
                        vault.writeShieldPrefs()
                        webLane.refreshShieldScripts()
                        webLane.liveWebView?.reload()
                    })
            )
            .padding(.horizontal, 16).frame(height: 50)
            Divider().padding(.leading, 16)
            Button {
                vault.modalLane = .protection
            } label: {
                HStack {
                    Text("Protection settings").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16).frame(height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 330)
        // smooth transition between states
        .animation(.smooth(duration: 0.25), value: protected)
    }
}
