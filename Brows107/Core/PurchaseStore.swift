//
//  PurchaseStore.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 26/10/26.
//

import ApphudSDK
import Observation
import StoreKit

/// Apphud paywall + StoreKit. On a non-shipping bundle (local test) falls back to `SubscriptionProductIDs` + StoreKit Configuration.
@Observable @MainActor final class PurchaseStore {
    var storeKitOffers: [Product] = []
    var busy = false
    var checkoutNotice: String?
    var entitlementActive = false
    var pickedPlanID = "weekly"

    // keeps apphud product by sku
    private var apphudProductBySKU: [String: ApphudProduct] = [:]
    private var storeKitFallback = false
    private var loadedPaywall: ApphudPaywall?

    var chosenProduct: Product? { storeProduct(forPlanID: pickedPlanID) }


    // keeps product
    func storeProduct(forPlanID planID: String) -> Product? {
        let normalizedPlan = planID.lowercased()
        if let periodMatch = storeKitOffers.first(where: { product in
            guard let period = product.subscription?.subscriptionPeriod else { return false }
            // map the state to what we show
            switch normalizedPlan {
            case "yearly": return period.unit == .year
            case "weekly": return period.unit == .week || (period.unit == .day && period.value == 7)
            default: return false
            }
        }) {
            return periodMatch
        }
        return storeKitOffers.first { $0.id.lowercased().contains(normalizedPlan) }
    }

    // Loads offers from Apphud, falling back to the StoreKit file.
    func fetchProducts() async {
        guard !busy else { return }    
        busy = true
        defer { busy = false }
        self.checkoutNotice = nil
        storeKitOffers = []
        self.apphudProductBySKU = [:]
        storeKitFallback = false
        loadedPaywall = nil

        let placementKey = AppMetadata.apphudPaywallPlacementID
        PaywallLog.fetchStarted(placementID: placementKey)
        // suspends here
        await ApphudBootstrap.awaitApphudBootstrapped()
        PaywallLog.apphudBootstrapped(
            started: ApphudBootstrap.apphudUserID() != "",
            userRef: ApphudBootstrap.apphudUserID()
        )
        // suspends here
        await loadFromApphud()
        if storeKitOffers.isEmpty, ApphudBootstrap.isRunningAlternateBundle || storeKitFallbackEligible {
            // suspends here 
            await loadFromStoreKitConfiguration()
        }
        if storeKitOffers.isEmpty {
            checkoutNotice = "Plans are not available right now. Check StoreKit Configuration or Apphud placement."
            PaywallLog.emit(.warning, "fetch finished with zero offers")
        }
    }


    private var storeKitFallbackEligible: Bool {
        #if DEBUG
            true
        #else
            ApphudBootstrap.isRunningAlternateBundle
        #endif
    } 
}

// MARK: - PurchaseStore helpers
extension PurchaseStore {
    // loads from apphud
    private func loadFromApphud() async {
        let placementKey = AppMetadata.apphudPaywallPlacementID
        let placementBatch = await Apphud.placements()
        let resolvedPlacement = placementBatch.first(where: {
            $0.identifier.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(placementKey) == .orderedSame
        })
        guard let resolvedPlacement else {
            PaywallLog.placementUnavailable(requested: placementKey, available: placementBatch.map(\.identifier))
            return
        }
        // resolved paywall
        let resolvedPaywall = resolvedPlacement.paywall
        // local apphud skulist
        let apphudSKUList = resolvedPaywall?.products.map(\.productId) ?? []
        PaywallLog.placementResolved(
            placementID: placementKey,
            paywallID: resolvedPaywall?.identifier,
            productIDs: apphudSKUList
        )
        // resolved paywall must exist here
        guard let resolvedPaywall, !resolvedPaywall.products.isEmpty else { return }
        self.loadedPaywall = resolvedPaywall
        Apphud.paywallShown(resolvedPaywall)

        var storeKitBatch: [Product] = []
        var apphudSKUMap: [String: ApphudProduct] = [:]
        // Go through each apphud product
        for apphudProduct in resolvedPaywall.products {
            apphudSKUMap[apphudProduct.productId] = apphudProduct
            do {
                if let storeProduct = try await apphudProduct.product() {
                    storeKitBatch.append(storeProduct)
                }
            } catch {
                PaywallLog.emit(.warning, "storekit product lookup failed: \(error.localizedDescription)")
            }
        }
        let missingSKUList = resolvedPaywall.products.map(\.productId).filter { sku in
            !storeKitBatch.contains(where: { $0.id == sku })
        }
        var fallbackBatch: [Product] = []
        if !missingSKUList.isEmpty {
            do {
                fallbackBatch = try await Product.products(for: missingSKUList)
            } catch {
                PaywallLog.emit(.warning, "storekit fallback fetch failed: \(error.localizedDescription)")
            }
        }
        if !fallbackBatch.isEmpty {
            storeKitBatch.append(contentsOf: fallbackBatch)
            storeKitFallback = true
        }
        apphudProductBySKU = apphudSKUMap
        storeKitOffers = storeKitBatch
        let offerRows = storeKitBatch.map { (id: $0.id, price: $0.displayPrice) }
        PaywallLog.storeKitLoaded(
            source: storeKitFallback ? "apphud+storekit-fallback" : "apphud",
            offers: offerRows
        )
        if storeProduct(forPlanID: pickedPlanID) == nil {
            if storeProduct(forPlanID: "weekly") != nil {
                pickedPlanID = "weekly"
            } else if storeProduct(forPlanID: "yearly") != nil {
                pickedPlanID = "yearly"
            }
        }
    }

    // loads from store kit configuration
    private func loadFromStoreKitConfiguration() async {
        let productSKUList = AppMetadata.subscriptionProductIDs
        guard !productSKUList.isEmpty else { return }
        do {
            storeKitOffers = try await Product.products(for: productSKUList)
            self.storeKitFallback = true
            PaywallLog.storeKitLoaded(
                source: "storekit-config",
                offers: storeKitOffers.map { (id: $0.id, price: $0.displayPrice) }
            )
        } catch {
            self.checkoutNotice = "Prices could not be loaded from StoreKit. Please try again."
            PaywallLog.emit(.failure, "storekit-config \(error.localizedDescription)")
        }
    }

    // Starts the purchase for the picked plan. 
    func commitPurchase() async {
        // skip when the input is unusable
        guard !busy else { return }
        guard let chosenProduct else {
            checkoutNotice = "Plans are not available right now. Please try again later."
            return
        }
        busy = true
        defer { busy = false }
        if let apphudProduct = apphudProductBySKU[chosenProduct.id], !storeKitFallback {
            PaywallLog.purchaseStarted(productID: chosenProduct.id, viaApphud: true)
            // suspends here until the result is back
            let apphudOutcome = await Apphud.purchase(apphudProduct)
            if apphudOutcome.success {
                entitlementActive = await ProEntitlement.isSubscribed()
                PaywallLog.purchaseOutcome(success: entitlementActive, detail: "apphud entitlement=\(entitlementActive)")
                if !entitlementActive { checkoutNotice = "Your purchase is being confirmed. Try Restore if needed." }
            } else if let purchaseError = apphudOutcome.error {
                checkoutNotice = purchaseError.localizedDescription
                PaywallLog.purchaseOutcome(success: false, detail: purchaseError.localizedDescription)
            }
            return
        }
        PaywallLog.purchaseStarted(productID: chosenProduct.id, viaApphud: false)    
        do {
            switch try await chosenProduct.purchase() {
            // When success
            case .success(let verificationPayload):
                if case .verified(let transaction) = verificationPayload {
                    await transaction.finish()
                    entitlementActive = true
                    PaywallLog.purchaseOutcome(success: true, detail: "storekit verified")
                } else {
                    checkoutNotice = "The purchase could not be verified."
                    PaywallLog.purchaseOutcome(success: false, detail: "storekit unverified")
                } 
            // When pending
            case .pending:
                checkoutNotice = "Your purchase is pending approval."
                PaywallLog.emit(.info, "purchase pending")
            case .userCancelled:
                PaywallLog.emit(.info, "purchase cancelled")
            @unknown default:
                break
            }
        } catch {
            self.checkoutNotice = "The purchase could not be completed. Please try again."
            PaywallLog.purchaseOutcome(success: false, detail: error.localizedDescription)
        } 
    }

    // Restore purchases button.
    func restoreEntitlements() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { 
            // Wait for it before moving on
            try await AppStore.sync()
            _ = await Apphud.restorePurchases()
            let isActive = await ProEntitlement.isSubscribed()
            if isActive {
                entitlementActive = true
                PaywallLog.restoreOutcome(active: true, detail: "entitlement found")
                return
            }
            checkoutNotice = "No active subscription was found."
            PaywallLog.restoreOutcome(active: false, detail: "no subscription")
        } catch {
            self.checkoutNotice = "Purchases could not be restored. Please try again."
            PaywallLog.restoreOutcome(active: false, detail: error.localizedDescription)
        }
    }
}
