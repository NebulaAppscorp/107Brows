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
        if Apphud.hasActiveSubscription() { return true }
        for await entitlementEvent in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlementEvent,
                transaction.revocationDate == nil,
                transaction.productType == .autoRenewable,
                transaction.expirationDate.map({ $0 > Date() }) ?? true
            {
                return true
            }
        }
        return false
    }
}
