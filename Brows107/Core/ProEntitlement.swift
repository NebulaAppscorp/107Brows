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
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        if !ApphudBootstrap.isRunningAlternateBundle {
            let apphudActive = Apphud.hasActiveSubscription()
            AppDiagnosticsLog.event("entitlement source=apphud active=\(apphudActive) bundle=\(bundleID)")
            if apphudActive { return true }
        } else {
            AppDiagnosticsLog.event("entitlement source=apphud skipped bundle=\(bundleID)")
        }

        var inspected = 0
        var hasActiveStoreKitEntitlement = false
        for await entitlementEvent in Transaction.currentEntitlements {
            inspected += 1
            switch entitlementEvent {
            case .verified(let transaction):
                let notRevoked = transaction.revocationDate == nil
                let notExpired = transaction.expirationDate.map { $0 > Date() } ?? true
                let isSubscription = transaction.productType == .autoRenewable
                let isActive = notRevoked && notExpired && isSubscription
                AppDiagnosticsLog.event(
                    "entitlement source=storekit verified=true product=\(transaction.productID) type=\(transaction.productType) revoked=\(!notRevoked) expired=\(!notExpired) active=\(isActive)"
                )
                hasActiveStoreKitEntitlement = hasActiveStoreKitEntitlement || isActive
            case .unverified(let transaction, _):
                AppDiagnosticsLog.failure(
                    "entitlement source=storekit verified=false product=\(transaction.productID)"
                )
            }
        }
        AppDiagnosticsLog.event(
            "entitlement result active=\(hasActiveStoreKitEntitlement) source=storekit inspected=\(inspected) bundle=\(bundleID)"
        )
        return hasActiveStoreKitEntitlement
    }
}
