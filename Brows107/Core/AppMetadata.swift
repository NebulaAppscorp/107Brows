//
//  AppMetadata.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 27/10/26.
//

import SwiftUI
import WebKit

/// Names, ids and support links read from Info.plist.
enum AppMetadata {
    static let shippingBundleID = "com.GraOls.com"

    // info plist string
    static func infoPlistString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    // marketing title
    static var marketingTitle: String {
        infoPlistString("CFBundleDisplayName") ?? "107Brows"
    }

    static var shareBlurb: String {
        if let linkURL = appStoreListingURL?.absoluteString {
            return "\(marketingTitle) — a browser that reads any page for you.\n\(linkURL)"
        }
        return "\(marketingTitle) — a browser that reads any page for you."
    }

    static var appStoreReviewListingURL: URL? {
        if let linkURL = appStoreListingURL {
            var storeReviewParts = URLComponents(url: linkURL, resolvingAgainstBaseURL: false)
            var reviewQueryParts = storeReviewParts?.queryItems ?? []
            reviewQueryParts.append(URLQueryItem(name: "action", value: "write-review"))
            storeReviewParts?.queryItems = reviewQueryParts
            if let reviewURL = storeReviewParts?.url { return reviewURL }
        }    
        if let appleAppID = infoPlistString("AppleAppID")?.trimmingCharacters(in: .whitespacesAndNewlines), !appleAppID.isEmpty {
            return URL(string: "https://apps.apple.com/app/id\(appleAppID)?action=write-review")
        }
        return appStoreListingURL
    } 

    static var versionCaption: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(shortVersion) (\(bundleVersion))"
    }

    static var shippingApplicationID: String {
        let plistBundleID = infoPlistString("ApplicationID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return plistBundleID.isEmpty ? shippingBundleID : plistBundleID
    }

    // keeps apphud public key
    static var apphudPublicKey: String? {
        infoPlistString("ApphudAPIKey")
    }

    // keeps nebula base url
    static var nebulaBaseURL: URL {
        if let slot = infoPlistString("NebulaBaseURL"), let linkURL = URL(string: slot) {
            return linkURL
        }
        return URL(string: "https://nebulaapsdola.site")!
    }

    static var nebulaBearerToken: String {
        infoPlistString("NebulaBearerToken")
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIiwiZW1haWwiOiJzaGFyb3ZfMTk5OUBsaXN0LnJ1Iiwicm9sZSI6IkFETUlOIiwiZXhwIjo0OTM1MjA4NjcxLCJpYXQiOjE3ODE2MDg2NzEsInR5cGUiOiJhY2Nlc3MifQ.0GRnZq1LZA__0G0tYEsPER8lQiCiX_myE6_T_nMwUmc"
    }

    // apphud paywall placement id
    static var apphudPaywallPlacementID: String { 
        infoPlistString("ApphudPaywallPlacementID") ?? "main"
    }

    static var subscriptionProductIDs: [String] {
        Bundle.main.object(forInfoDictionaryKey: "SubscriptionProductIDs") as? [String] ?? []
    }

    private static let defaultPrivacyURL = URL(
        string: "https://docs.google.com/document/d/13NkEq9FxrU91SubGsoA0S8d43Mx9wH6DKfwAMzy64Ik/edit?tab=t.0")!
    private static let defaultTermsURL = URL(
        string:
            "https://docs.google.com/document/d/1TEcLp4wx7OIYM3A88Glu7N9XtQn7oJn-cv4gtFhHWFo/edit?tab=t.0#heading=h.g8o8t9y57hes")!

    static var privacyPolicyLink: URL? {
        infoPlistString("PrivacyURL").flatMap(URL.init(string:)) ?? defaultPrivacyURL
    }

    static var termsOfUseLink: URL? {
        infoPlistString("TermsURL").flatMap(URL.init(string:)) ?? defaultTermsURL
    }

    static var supportMailbox: String? {
        let slot = infoPlistString("SupportEmail")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return slot.isEmpty ? nil : slot
    }

    static var supportMailTopic: String {
        "support \(marketingTitle)"
    }

    static var appStoreListingURL: URL? {
        infoPlistString("AppStoreURL").flatMap(URL.init(string:))
    }


    // apphud user id
    static func apphudUserID() -> String {
        if let stored = UserDefaults.standard.string(forKey: "apphudUserID") {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let vaultSnapshot = try? APIKeyVault.readFromKeychain() {
            let trimmed = vaultSnapshot.remoteUserID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "—"
    }

    // support inquiry mail body
    static func supportInquiryMailBody(apphudUserID userRef: String) -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let trimmed = userRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let supportSnippet = trimmed.isEmpty ? "—" : trimmed
        return "Apphud user id: \(supportSnippet)\nApp version: \(shortVersion) (\(bundleVersion))\n\n"
    }

    // mailto: link with app version and user id pre-filled.
    static func supportMailtoURL(apphudUserID userRef: String) -> URL? {
        guard let supportMailbox else { return nil }
        var mailURLParts = URLComponents()
        mailURLParts.scheme = "mailto"
        mailURLParts.path = supportMailbox
        mailURLParts.queryItems = [
            URLQueryItem(name: "subject", value: supportMailTopic),
            URLQueryItem(name: "body", value: supportInquiryMailBody(apphudUserID: userRef)),
        ]
        return mailURLParts.url
    }
}

struct LegalSheet: Identifiable, Equatable {
    let sheetHeading: String
    let policyURL: URL
    var id: String { sheetHeading + policyURL.absoluteString }
}

struct LegalWebSheet: View {
    // sheet heading
    let sheetHeading: String
    let policyURL: URL
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        NavigationStack {
            LegalWebView(policyURL: policyURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(sheetHeading)
                .navigationBarTitleDisplayMode(.inline)
                .browsLiquidNavBar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", systemImage: "xmark") { dismissSheet() }
                    }
                }
        }
    }
}

private struct LegalWebView: UIViewRepresentable {
    let policyURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let webKitConfig = WKWebViewConfiguration()
        webKitConfig.defaultWebpagePreferences.allowsContentJavaScript = true
        let hostName = WKWebView(frame: .zero, configuration: webKitConfig)
        hostName.isOpaque = false
        let embedTarget = Self.legalEmbedURL(for: policyURL)
        var policyRequest = URLRequest(url: embedTarget)  
        policyRequest.cachePolicy = .reloadIgnoringLocalCacheData
        hostName.load(policyRequest)
        return hostName
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        _ = uiView
        _ = context
    }


    // legal embed url
    static func legalEmbedURL(for linkURL: URL) -> URL {
        let isGoogleDoc = linkURL.host?.contains("docs.google.com") == true
        if !isGoogleDoc { return linkURL }
        let pathSegments = linkURL.pathComponents
        if let docIndex = pathSegments.firstIndex(of: "d"), docIndex + 1 < pathSegments.count {
            let docID = pathSegments[docIndex + 1]
            if let preview = URL(string: "https://docs.google.com/document/d/\(docID)/preview") { return preview }
        }
        return linkURL
    }
}
