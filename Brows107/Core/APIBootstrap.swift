//
//  APIBootstrap.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 12/11/26.
//

import Foundation

enum APIBootstrap {
    // First launch: seed the Keychain connection if nothing is there yet.
    static func primeAPIVault() {
        APIKeyVault.pinShippingAppID()
        if (try? APIKeyVault.readFromKeychain()) == nil {
            persistFirstConnection(userRef: resolveInstallUserID())
        }
    }

    // Stores the first connection record.
    private static func persistFirstConnection(userRef: String) {
        let sanitized = sanitizedUserID(userRef)
        let vaultDraft = APIVault.defaultProduction(userRef: sanitized)
        if (try? APIKeyVault.writeToKeychain(vaultDraft)) == nil {
            try? APIKeyVault.writeToKeychain(APIVault.defaultProduction(userRef: "1"))
        }
    }

    // Falls back to "1" when the id would not pass the vault validation.
    private static func sanitizedUserID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "1" }
        var vaultProbe = APIVault.defaultProduction(userRef: trimmed)
        return (try? vaultProbe.verifyVaultFields()) != nil ? trimmed : "1"
    }


    // Keeps the API user id aligned with the Apphud one.
    static func syncApphudIdentity() {
        refreshUserIDIfNeeded()
    }

    // Refreshes user id if needed
    static func refreshUserIDIfNeeded() {
        guard var vaultDraft = try? APIKeyVault.readFromKeychain() else { return }    
        let userRef = sanitizedUserID(resolveInstallUserID())
        let needsUserSync = vaultDraft.remoteUserID != userRef
        let pinnedVault = vaultDraft.pinningShippingAppID()
        let needsAppIDSync = pinnedVault.optionalAppID != vaultDraft.optionalAppID
        if !needsUserSync, !needsAppIDSync { return }
        if needsUserSync { vaultDraft.remoteUserID = userRef }
        if needsAppIDSync { vaultDraft.optionalAppID = pinnedVault.optionalAppID }
        try? APIKeyVault.writeToKeychain(vaultDraft.pinningShippingAppID())
    }

    // Falls back to a per-install id when Apphud has none yet.
    private static func resolveInstallUserID() -> String { 
        if let stored = UserDefaults.standard.string(forKey: "apphudUserID") {
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "1"
    }
}
