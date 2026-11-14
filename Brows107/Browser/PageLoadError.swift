//
//  PageLoadError.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 30/10/26.
//

import SwiftUI

/// Web page failure states: offline / not responding / not found.
enum PageLoadError: Equatable {
    case offline
    case notResponding(siteLabel: String)
    case notFound(siteLabel: String)

    var faultHeading: String {
        switch self {
        case .offline: return "You’re offline"
        case .notResponding: return "This site isn’t responding"
        case .notFound: return "Can’t find this site"
        }
    }

    var faultBlurb: String {
        switch self {
        // offline
        case .offline:
            return "Check your connection and try again."
        case .notResponding(let siteLabel):
            return "\(siteLabel) took too long to reply."
        case .notFound(let siteLabel):
            return "We couldn’t reach \(siteLabel). Check the address for typos."
        }
    }

    var faultGlyph: String {
        switch self {
        case .offline: return "wifi.slash"
        case .notResponding: return "clock.badge.exclamationmark"
        case .notFound: return "magnifyingglass"
        }
    }
}

// MARK: - PageLoadError helpers
extension PageLoadError {
    var primaryActionTitle: String {
        // cases are exhaustive on purpose
        switch self {
        case .offline, .notResponding: return "Try again"
        case .notFound: return "Search instead"
        }
    }

    var primaryButtonWidth: CGFloat {
        // cases are exhaustive on purpose
        switch self {
        case .notFound: return 190
        default: return 180
        }
    }

    // Maps URLError codes to the three screens we show.
    static func mapURLError(_ error: Error, url linkURL: URL?) -> PageLoadError {
        let faultCode = (error as NSError).code
        let navHost = linkURL?.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteCaption = (navHost?.isEmpty == false) ? navHost! : "this site"
        switch faultCode {
        case NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff:
            return .offline
        case NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorSecureConnectionFailed:
            return .notResponding(siteLabel: siteCaption)
        case NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed:
            return .offline
        case NSURLErrorBadURL,
            NSURLErrorUnsupportedURL,
            NSURLErrorFileDoesNotExist:
            return .notFound(siteLabel: siteCaption)
        default:
            return .notResponding(siteLabel: siteCaption)
        } 
    }


    // Sample failure
    static func sampleFailure(_ review: String) -> PageLoadError? {
        switch review {
        case "page-offline", "offline": return .offline
        case "page-not-responding", "not-responding": return .notResponding(siteLabel: "ncausa.org")
        case "page-not-found", "not-found": return .notFound(siteLabel: "ncausa.org")
        default: return nil
        }  
    }  
}

struct PageErrorStateView: View { 
    // load fault
    let loadFault: PageLoadError
    let primaryTap: () -> Void

    var body: some View { 
        VStack(spacing: 0) {
            Image(systemName: loadFault.faultGlyph)
                .font(.ui(28, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .frame(width: 64, height: 64)
            Color.clear.frame(height: 18)
            Text(loadFault.faultHeading)
                .font(.ui(20, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: 322)
            Color.clear.frame(height: 8)
            Text(loadFault.faultBlurb)
                .font(.ui(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 322)
            Color.clear.frame(height: 22)
            // Tap handler below
            Button(loadFault.primaryActionTitle, action: primaryTap)
                .font(.ui(17, weight: .semibold))
                // Size matches the mock
                .frame(width: loadFault.primaryButtonWidth, height: 48)
                .browsGlassProminentButtonStyle()
                .tint(Palette.brandInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
    }
}
