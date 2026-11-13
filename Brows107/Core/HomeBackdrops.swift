//
//  HomeBackdrops.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 11/11/26.
//

import SwiftUI
import UIKit
import Speech
import AVFoundation


/// Soft coloured wash behind the welcome pages.
struct OnboardingBackdrop: View {
    var welcomeStepIndex: Int = 0
    @Environment(\.colorScheme) private var interfaceScheme


    private var washBlobs: [(x: CGFloat, y: CGFloat, stageWidth: CGFloat, h: CGFloat, color: Color, blur: CGFloat)] {
        switch welcomeStepIndex {
        case 1:
            return [
                (132, -130, 400, 330, Palette.rgb(0x1FB6A6), 140),
                (-118, -160, 360, 300, Palette.brandInk, 150),
                (-48, -90, 440, 280, Palette.rgb(0x00B37A), 140),
                (122, 40, 400, 250, Palette.brandWash, 130),
            ]
        case 2:
            return [
                (-118, -160, 360, 300, Palette.brandInk, 150),
                (132, -130, 400, 330, Palette.rgb(0x1FB6A6), 140),
                (-48, -90, 440, 280, Palette.rgb(0x00B37A), 140),
                (122, 40, 400, 250, Palette.brandWash, 130),
            ]
        case 3, 5:
            return [
                (-60, -210, 520, 360, Palette.rgb(0x1FB6A6), 140),
                (40, -150, 420, 320, Palette.brandInk, 150),
                (-90, -30, 580, 300, Palette.rgb(0x00B37A), 140),
                (60, 110, 380, 240, Palette.brandWash, 130),
            ]
        default:
            return [
                (-130, -170, 400, 330, Palette.rgb(0x1FB6A6), 140),
                (160, -190, 360, 300, Palette.brandInk, 150),
                (10, -60, 440, 280, Palette.rgb(0x00B37A), 140),
                (-120, 100, 400, 250, Palette.brandWash, 130),
            ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 402
            let opacity = interfaceScheme == .dark ? 0.17 : 1
            ZStack(alignment: .topLeading) {
                Palette.canvasView
                ForEach(Array(washBlobs.enumerated()), id: \.offset) { _, blob in
                    Ellipse()
                        .fill(blob.color.opacity(opacity))
                        .frame(width: blob.stageWidth * s, height: blob.h * s)
                        .blur(radius: blob.blur * s * (welcomeStepIndex == 1 ? 0.42 : 0.3))
                        .offset(x: blob.x * s, y: blob.y * s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        // background goes behind everything
        .background(Palette.canvasView)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}


/// Private home backdrop (light bitmap).
struct PrivateHomeBackdrop: View {
    // current private fill
    private let privateFill = Palette.rgb(0x0B0713)
    private let washBlobs: [(x: CGFloat, y: CGFloat, stageWidth: CGFloat, h: CGFloat, color: Color, blur: CGFloat)] = [
        (-130, -170, 400, 330, Palette.rgb(0x5B7CFF), 140),
        (160, -190, 360, 300, Palette.rgb(0x7C5CFF), 150),
        (10, -60, 440, 280, Palette.rgb(0xA78BFA), 140),
        (-120, 100, 400, 250, Palette.rgb(0x1E1A38), 130),
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 402
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            ZStack(alignment: .topLeading) {
                privateFill
                ForEach(Array(washBlobs.enumerated()), id: \.offset) { _, blob in
                    Ellipse()
                        .fill(blob.color)
                        .frame(width: blob.stageWidth * scale, height: blob.h * scale)
                        .blur(radius: blob.blur * scale)
                        .offset(x: blob.x * scale, y: blob.y * scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height + topInset + bottomInset, alignment: .topLeading)
            .offset(y: -topInset)
            .clipped()
        }
        .background(privateFill)
        .ignoresSafeArea()
    }
}

/// Browser home backdrop (light bitmap).
struct BrowserHomeBackdrop: View {  
    @Environment(\.colorScheme) private var interfaceScheme
    private let washBlobs: [(x: CGFloat, y: CGFloat, stageWidth: CGFloat, h: CGFloat, color: Color, blur: CGFloat)] = [
        (-130, -170, 400, 330, Palette.rgb(0x1FB6A6), 140),
        (160, -190, 360, 300, Palette.brandInk, 150),
        (10, -60, 440, 280, Palette.rgb(0x00B37A), 140),
        (-120, 100, 400, 250, Palette.rgb(0xE6F5EF), 130),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 402
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            let blobOpacity = interfaceScheme == .dark ? 0.38 : 1
            let sheetFill = interfaceScheme == .dark ? Palette.canvasView : Color.white
            ZStack(alignment: .topLeading) { 
                sheetFill
                ForEach(Array(washBlobs.enumerated()), id: \.offset) { _, blob in
                    Ellipse()
                        .fill(blob.color.opacity(blobOpacity))
                        .frame(width: blob.stageWidth * s, height: blob.h * s)
                        .blur(radius: blob.blur * s)
                        .offset(x: blob.x * s, y: blob.y * s)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height + topInset + bottomInset, alignment: .topLeading)
            .offset(y: -topInset)
            .clipped()
        }
        .background(interfaceScheme == .dark ? Palette.canvasView : Color.white) 
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
