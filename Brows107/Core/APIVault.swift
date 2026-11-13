//
//  APIVault.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 11/11/26.
//

import Foundation
import Security

struct APIVault: Codable, Sendable {
    var baseEndpoint: URL
    var bearerToken: String
    var remoteUserID: String
    var optionalAppID: String?

    private enum CodingKeys: String, CodingKey {
        case baseEndpoint = "baseURL"
        case bearerToken = "bearer"
        case remoteUserID = "userID"
        case optionalAppID = "appID"
    }

    init(baseEndpoint: URL, bearerToken: String, remoteUserID: String, optionalAppID: String? = nil) {
        self.baseEndpoint = baseEndpoint
        self.bearerToken = bearerToken
        self.remoteUserID = remoteUserID
        self.optionalAppID = optionalAppID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseEndpoint = try container.decode(URL.self, forKey: .baseEndpoint)
        bearerToken = try container.decode(String.self, forKey: .bearerToken)
        remoteUserID = try container.decode(String.self, forKey: .remoteUserID)
        optionalAppID = try container.decodeIfPresent(String.self, forKey: .optionalAppID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseEndpoint, forKey: .baseEndpoint)
        try container.encode(bearerToken, forKey: .bearerToken)
        try container.encode(remoteUserID, forKey: .remoteUserID)
        try container.encodeIfPresent(optionalAppID, forKey: .optionalAppID)
    }

    // Throws if any stored field is empty or malformed.
    func verifyVaultFields() throws {
        guard baseEndpoint.scheme == "https", let host = baseEndpoint.host, !host.isEmpty,
            baseEndpoint.user == nil, baseEndpoint.password == nil, baseEndpoint.query == nil, baseEndpoint.fragment == nil,
            !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !bearerToken.contains(where: \.isWhitespace),
            remoteUserID.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) != nil
        else { throw APIError.misconfigured }
        if let optionalAppID, !optionalAppID.isEmpty {
            guard optionalAppID.range(of: "^[A-Za-z0-9.-]{3,256}$", options: .regularExpression) != nil else {
                throw APIError.misconfigured
            }
        }
    }

    // Resolved app id
    func resolvedAppID(bundleDefault: String = AppMetadata.shippingApplicationID) -> String {
        let trimmed = optionalAppID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AppMetadata.shippingApplicationID : trimmed
    }

    // Returns a copy that always carries the shipping app id.
    func pinningShippingAppID() -> APIVault {
        var vaultClone = self
        vaultClone.optionalAppID = AppMetadata.shippingApplicationID
        return vaultClone
    }

    // Default connection for the production backend.
    static func defaultProduction(userRef: String) -> APIVault {
        APIVault(
            baseEndpoint: AppMetadata.nebulaBaseURL,
            bearerToken: AppMetadata.nebulaBearerToken,
            remoteUserID: userRef,
            optionalAppID: AppMetadata.shippingApplicationID
        )
    }

    #if DEBUG
        static let nebulaSandbox = APIVault(
            baseEndpoint: URL(string: "https://nebulaapsdola.site")!,
            bearerToken:
                "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIiwiZW1haWwiOiJzaGFyb3ZfMTk5OUBsaXN0LnJ1Iiwicm9sZSI6IkFETUlOIiwiZXhwIjo0OTM1MjA4NjcxLCJpYXQiOjE3ODE2MDg2NzEsInR5cGUiOiJhY2Nlc3MifQ.0GRnZq1LZA__0G0tYEsPER8lQiCiX_myE6_T_nMwUmc",
            remoteUserID: "1",
            optionalAppID: AppMetadata.shippingBundleID
        )
    #endif
}

/// Keychain read/write for the API connection.
enum APIKeyVault {
    private static var keychainLookup: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "107Brows") + ".connection",
            kSecAttrAccount as String: "api",
        ]
    }

    // Reads the connection; throws if it is missing.
    static func readFromKeychain() throws -> APIVault {
        var secLookup = keychainLookup
        secLookup[kSecReturnData as String] = true
        secLookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var secMatch: CFTypeRef?
        let secStatus = SecItemCopyMatching(secLookup as CFDictionary, &secMatch)
        guard secStatus == errSecSuccess, let payloadBytes = secMatch as? Data,
            var storedVault = try? JSONDecoder().decode(APIVault.self, from: payloadBytes)
        else { throw APIError.misconfigured }
        storedVault = storedVault.pinningShippingAppID()
        try storedVault.verifyVaultFields()
        return storedVault
    }

    static func writeToKeychain(_ vaultRecord: APIVault) throws {
        var vaultRecord = vaultRecord.pinningShippingAppID()
        try vaultRecord.verifyVaultFields()
        let itemAttributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(vaultRecord),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let secStatus = SecItemUpdate(keychainLookup as CFDictionary, itemAttributes as CFDictionary)
        if secStatus == errSecItemNotFound {
            let addStatus = SecItemAdd(keychainLookup.merging(itemAttributes) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainFailure(secStatusCode: addStatus) }
        } else if secStatus != errSecSuccess {
            throw KeychainFailure(secStatusCode: secStatus)
        }
    }

    // Removes the connection (Settings → Remove connection).
    static func deleteFromKeychain() throws {
        let secStatus = SecItemDelete(keychainLookup as CFDictionary)
        guard secStatus == errSecSuccess || secStatus == errSecItemNotFound else { throw APIError.storage }
    }

    #if DEBUG
        static func installDebugKeychainConnection() throws {
            let envMap = ProcessInfo.processInfo.environment
            guard envMap["BROWS107_INSTALL_CONNECTION"] == "1" else { return }
            guard let endpointString = envMap["BROWS107_BASE_URL"], let linkURL = URL(string: endpointString),
                let bearer = envMap["BROWS107_BEARER"], let userRef = envMap["BROWS107_USER_ID"]
            else { throw APIError.misconfigured }
            let appRef = envMap["BROWS107_APP_ID"]
            try writeToKeychain(
                APIVault(
                    baseEndpoint: linkURL,
                    bearerToken: bearer,
                    remoteUserID: userRef,
                    optionalAppID: appRef ?? AppMetadata.shippingApplicationID
                )
            )
        }
    #endif

    // pin shipping app id
    static func pinShippingAppID() {
        if var storedVault = try? readFromKeychain() {
            let pinnedVault = storedVault.pinningShippingAppID()
            if pinnedVault.resolvedAppID() != storedVault.resolvedAppID() {
                try? writeToKeychain(pinnedVault)
            }
        }
    }
}

/// Wraps an OSStatus so it can be shown as text.
private struct KeychainFailure: LocalizedError {
    let secStatusCode: OSStatus
    var errorDescription: String? {
        #if DEBUG
            APIError.storage.localizedDescription + " (Keychain: \(secStatusCode))"
        #else
            APIError.storage.localizedDescription
        #endif
    }
}
