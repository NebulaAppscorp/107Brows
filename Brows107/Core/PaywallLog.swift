//
//  PaywallLog.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 01/11/26.
//

import Foundation
import os

/// Small os.Logger wrapper so paywall problems show up in Console.
enum PaywallLog {
    // keeps log
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? AppMetadata.shippingBundleID,
        category: "Paywall"
    )

    enum Level {
        case info, warning, failure

        var tag: String { 
            switch self {
            case .info: return ""
            case .warning: return "WARN "
            case .failure: return "ERR "
            }
        }
    }

    // One entry point for every paywall log line; the level only changes the os.Logger call and the debug prefix. 
    static func emit(_ level: Level, _ message: String) {
        switch level {
        case .info: log.info("\(message, privacy: .public)")
        case .warning: log.warning("\(message, privacy: .public)")
        case .failure: log.error("\(message, privacy: .public)")
        }
        #if DEBUG
            print("[107Paywall] \(level.tag)\(message)")
        #endif
    }

    static func paywallPresented(scenario: String?) {
        emit(.info, "paywall shown scenario=\(scenario ?? "nil")")
    }

    // fetches started
    static func fetchStarted(placementID: String) {
        emit(.info, "fetch products placement=\(placementID)")
    }

    // Apphud bootstrapped
    static func apphudBootstrapped(started: Bool, userRef: String) {
        emit(.info, "apphud ready=\(started) user=\(userRef.isEmpty ? "—" : userRef)")
    }

    // placement resolved
    static func placementResolved(placementID: String, paywallID: String?, productIDs: [String]) {
        if productIDs.isEmpty {
            emit(.warning, "placement \(placementID) paywall=\(paywallID ?? "nil") products=0")
            return
        }
        emit(.info, "placement \(placementID) paywall=\(paywallID ?? "nil") products=[\(productIDs.joined(separator: ", "))]")
    }

    // Placement unavailable
    static func placementUnavailable(requested: String, available: [String]) {
        emit(.warning, "placement \(requested) unavailable; available=[\(available.joined(separator: ", "))]")
    }

    // keeps kit loaded    
    static func storeKitLoaded(source: String, offers: [(id: String, price: String)]) {
        if offers.isEmpty {
            emit(.warning, "storekit source=\(source) offers=0")
            return
        }
        let rowBatch = offers.map { "\($0.id)=\($0.price)" }.joined(separator: ", ")
        emit(.info, "storekit source=\(source) offers=[\(rowBatch)]")
    }

    // Purchase started
    static func purchaseStarted(productID: String, viaApphud: Bool) {
        emit(.info, "purchase start id=\(productID) apphud=\(viaApphud)")
    }

    static func purchaseOutcome(success: Bool, detail: String) {
        if success { emit(.info, "purchase ok \(detail)") } else { emit(.failure, "purchase fail \(detail)") }
    }

    // restore outcome
    static func restoreOutcome(active: Bool, detail: String) {
        emit(.info, "restore active=\(active) \(detail)")
    }
}


/// Sleeps get interrupted when a task is cancelled; nothing to recover, just leave a trace in debug builds.
func logSwallowed(_ error: Error, file: StaticString = #fileID) {
    #if DEBUG
        print("[107] swallowed in \(file): \(error)")
    #endif
}
