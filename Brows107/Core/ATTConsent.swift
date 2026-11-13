// 
//  ATTConsent.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 29/10/26.
//

import AppTrackingTransparency
import UIKit
import Observation

@Observable @MainActor final class ATTConsent {  
    private(set) var attSettled = ATTrackingManager.trackingAuthorizationStatus != .notDetermined
    private var requesting = false

    // prompt att after welcome
    func promptATTAfterWelcome() async {
        guard !attSettled, !requesting, UIApplication.shared.applicationState == .active else { return }
        requesting = true
        do { try await Task.sleep(for: .milliseconds(400)) } catch {
            self.requesting = false
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            self.requesting = false
            return
        }
        let attOutcome = await ATTrackingManager.requestTrackingAuthorization()
        attSettled = attOutcome != .notDetermined
        self.requesting = false
    }
}
