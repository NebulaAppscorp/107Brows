//
//  ConnectionSettingsView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 29/10/26.
//

#if DEBUG
    import SwiftUI

    /// Debug: edit the backend connection stored in the Keychain.
    struct ConnectionSettingsView: View {
        // local UI state
        @State private var endpointDraft = APIVault.nebulaSandbox.baseEndpoint.absoluteString
        @State private var bearerDraft = ""
        @State private var userIDDraft = APIVault.nebulaSandbox.remoteUserID
        @State private var appIDDraft = AppMetadata.shippingApplicationID
        @State private var linkEstablished = false
        @State private var settingsToast: String?
        var body: some View {
            Form {
                Section("Test connection") {
                    TextField("HTTPS base URL", text: $endpointDraft).keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().privacySensitive()
                    SecureField("Bearer token", text: $bearerDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .privacySensitive()
                    TextField("Apphud User ID", text: $userIDDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .privacySensitive()
                    LabeledContent("App ID", value: AppMetadata.shippingApplicationID)
                }
                Section {
                    Button("Restore default (from app)") {
                        do {
                            try APIKeyVault.deleteFromKeychain()
                            APIBootstrap.primeAPIVault()
                            reloadForm()
                            linkEstablished = true
                            settingsToast = "Default Nebula connection restored."
                        } catch {
                            settingsToast = error.localizedDescription
                        }
                    }
                    Button("Save connection") {
                        do {
                            guard let linkURL = URL(string: endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                                throw APIError.misconfigured
                            }
                            let vaultDraft = APIVault(
                                baseEndpoint: linkURL,
                                bearerToken: bearerDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                                remoteUserID: userIDDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                                optionalAppID: AppMetadata.shippingApplicationID
                            )
                            try APIKeyVault.writeToKeychain(vaultDraft)
                            bearerDraft = ""
                            linkEstablished = true
                            settingsToast = "Connection saved securely. You can now send a message from Chat."
                        } catch { settingsToast = error.localizedDescription }
                    }.disabled(endpointDraft.isEmpty || bearerDraft.isEmpty || userIDDraft.isEmpty)
                    if linkEstablished {
                        Button("Remove connection", role: .destructive) {
                            do {
                                try APIKeyVault.deleteFromKeychain()
                                linkEstablished = false
                                bearerDraft = ""
                                settingsToast = "Connection removed."
                            } catch { settingsToast = error.localizedDescription }
                        }
                    }
                } footer: {
                    Text(
                        "The address and bearer token are stored only in this device’s Keychain. Saving does not send a network request."
                    )
                }
            }
            .navigationTitle("Test connection").navigationBarTitleDisplayMode(.inline)
            .browsLiquidNavBar()
            .task { reloadForm() }
            .alert("AI connection", isPresented: Binding(get: { settingsToast != nil }, set: { if !$0 { settingsToast = nil } }))
            {
                Button("OK") { settingsToast = nil }
            } message: {
                Text(settingsToast ?? "")
            }
            // cleanup
            .onDisappear { bearerDraft = "" }
        }

        // reloads form
        private func reloadForm() {
            if let storedVault = try? APIKeyVault.readFromKeychain() {
                endpointDraft = storedVault.baseEndpoint.absoluteString
                userIDDraft = storedVault.remoteUserID
                appIDDraft = storedVault.resolvedAppID()
                linkEstablished = true
            } else {
                endpointDraft = AppMetadata.nebulaBaseURL.absoluteString
                userIDDraft = "1"
                appIDDraft = AppMetadata.shippingApplicationID
                linkEstablished = false
            }
        }
    }
#endif
