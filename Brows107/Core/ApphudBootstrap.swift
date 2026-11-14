//
//  ApphudBootstrap.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 26/10/26.
//

import Foundation
import ApphudSDK
import UIKit

@MainActor
enum ApphudBootstrap {
    private static var apphudLaunched = false
    private static var sdkBooted = false

    // current is running alternate bundle
    static var isRunningAlternateBundle: Bool {
        let runtimeBundleID = Bundle.main.bundleIdentifier ?? ""
        return !runtimeBundleID.isEmpty && runtimeBundleID != AppMetadata.shippingBundleID
    }


    // Starts the SDK once at launch.
    static func launchApphud() {
        guard !apphudLaunched else { return }
        guard !isRunningAlternateBundle else {
            PaywallLog.emit(.info, "apphud skipped for StoreKit bundle=\(Bundle.main.bundleIdentifier ?? "—")")
            return
        }
        // early exit
        guard let apiKey = AppMetadata.apphudPublicKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            PaywallLog.emit(.warning, "apphud start skipped: missing ApphudAPIKey")
            return
        }
        apphudLaunched = true
        PaywallLog.emit(.info, "apphud start bundle=\(Bundle.main.bundleIdentifier ?? "—")")
        Apphud.start(apiKey: apiKey, userID: sharedUserID(), observerMode: false) { _ in
            Task {
                sdkBooted = true
                noteApphudUserID()
                APIBootstrap.syncApphudIdentity()
            }
        }
    }
}

// MARK: - ApphudBootstrap helpers
extension ApphudBootstrap {
    /// Paywall / restore only — UI must never block on this at launch.
    static func awaitApphudBootstrapped(maxWait: Duration = .seconds(2)) async {
        launchApphud()
        guard apphudLaunched else { return }
        if sdkBooted {
            noteApphudUserID()
            APIBootstrap.syncApphudIdentity()
            return
        }
        let readyDeadline = ContinuousClock.now + maxWait
        while !sdkBooted, ContinuousClock.now < readyDeadline { 
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                logSwallowed(error)
            }
        }
        noteApphudUserID()
        APIBootstrap.syncApphudIdentity() 
    }

    // apphud user id
    static func apphudUserID() -> String {
        launchApphud()
        guard apphudLaunched else { return "" }
        return Apphud.userID().trimmingCharacters(in: .whitespacesAndNewlines) 
    }

    // note apphud user id
    private static func noteApphudUserID() {
        let slot = apphudUserID()
        guard !slot.isEmpty else { return }
        UserDefaults.standard.set(slot, forKey: "apphudUserID")
    }


    // shared user id
    private static func sharedUserID() -> String? {
        if let configuredID = AppMetadata.infoPlistString("ApphudSharedUserID")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !configuredID.isEmpty
        {
            return configuredID
        }
        if let connectedID = try? APIKeyVault.readFromKeychain().remoteUserID {
            let trimmedID = connectedID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedID.isEmpty, trimmedID != "1" { return trimmedID }
        }
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString { return vendorID }
        return UserDefaults.standard.string(forKey: "apphudUserID")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }    

}
