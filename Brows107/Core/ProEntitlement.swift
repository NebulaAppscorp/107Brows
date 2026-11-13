//
//  ProEntitlement.swift
//  Brows107 
//
//  Created by Aleksandra Savchuk on 23/10/26.
//  

import ApphudSDK
import StoreKit

enum ProEntitlement {
    @MainActor
    static func isSubscribed() async -> Bool {
        // Apphud knows first, it caches the last receipt validation
        if Apphud.hasActiveSubscription() { return true }
        // fall back to StoreKit in case Apphud has not synced yet
        for await entitlementEvent in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlementEvent,
                transaction.revocationDate == nil,
                transaction.productType == .autoRenewable,
                transaction.expirationDate.map({ $0 > Date() }) ?? true
            {
                // verified, not revoked, auto-renewable and not expired
                return true
            }
        }
        // nothing active
        return false
    }
}
