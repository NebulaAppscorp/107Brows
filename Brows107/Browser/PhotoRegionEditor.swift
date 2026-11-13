//
//  PhotoRegionEditor.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 25/10/26.
//

import SwiftUI

/// Lets the user pan/zoom a gallery photo inside the same viewfinder frame as the live camera.
struct PhotoRegionCanvas: View {
    let sourceBitmap: UIImage
    @Binding var zoomScale: CGFloat
    @Binding var panShift: CGSize
    var gesturesEnabled = true
    // view state
    @State private var gestureStartScale: CGFloat = 1
    @State private var panOrigin: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
                // drawn on top of the content
                .overlay {
                    Image(uiImage: sourceBitmap)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoomScale, anchor: .center)
                        .offset(panShift)
                }
                .clipped()
                .contentShape(Rectangle())
                .allowsHitTesting(false)
                .gesture(panGesture)
                .simultaneousGesture(magnifyGesture)
                .onChange(of: sourceBitmap) { _, _ in
                    gestureStartScale = 1
                    panOrigin = .zero
                }
        }
        .ignoresSafeArea()
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { slot in
                guard gesturesEnabled else { return }
                panShift = CGSize(
                    width: panOrigin.width + slot.translation.width,
                    height: panOrigin.height + slot.translation.height
                )
            }
            .onEnded { _ in
                guard gesturesEnabled else { return }
                panOrigin = panShift
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { slot in
                guard gesturesEnabled else { return }
                zoomScale = min(max(gestureStartScale * slot, 1), 4)
            }
            .onEnded { _ in
                guard gesturesEnabled else { return }
                gestureStartScale = zoomScale
            }
    }
}

/// Crop box with four draggable corners.
struct ResizablePhotoSelection: View {
    // injected state
    @Binding var selectedRect: CGRect
    let cropCanvas: CGSize
    var gesturesEnabled = true
    var selectionPending = false
    @State private var gestureStart: CGRect?

    private let minCropEdge: CGFloat = 96
    private let cropSideInset: CGFloat = 20
    private let topReserve: CGFloat = 104
    private let cropBottomReserve: CGFloat = 156

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: cropCanvas))
                path.addRoundedRect(in: selectedRect, cornerSize: CGSize(width: 14, height: 14))
            }
            .fill(.black.opacity(0.38), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.32), lineWidth: 1)
                .frame(width: selectedRect.width, height: selectedRect.height)
                .position(x: selectedRect.midX, y: selectedRect.midY)
                .allowsHitTesting(false)

            ViewfinderCorners()
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .shadow(color: .black.opacity(0.75), radius: 3)
                .frame(width: selectedRect.width, height: selectedRect.height)
                .position(x: selectedRect.midX, y: selectedRect.midY)
                .allowsHitTesting(false)

            if selectionPending {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                    .position(x: selectedRect.midX, y: selectedRect.midY)
                    .allowsHitTesting(false)
            }

            if gesturesEnabled {
                Color.clear
                    .frame(width: max(selectedRect.width - 56, 24), height: max(selectedRect.height - 56, 24))
                    .contentShape(Rectangle())
                    .position(x: selectedRect.midX, y: selectedRect.midY)
                    .gesture(moveGesture)

                dragSelectionCorner(.topLeft, x: selectedRect.minX, y: selectedRect.minY)
                dragSelectionCorner(.topRight, x: selectedRect.maxX, y: selectedRect.minY)
                dragSelectionCorner(.bottomLeft, x: selectedRect.minX, y: selectedRect.maxY)
                dragSelectionCorner(.bottomRight, x: selectedRect.maxX, y: selectedRect.maxY)
            }
        }
        .frame(width: cropCanvas.width, height: cropCanvas.height)
    }
}

// MARK: - Actions
extension ResizablePhotoSelection {
    // drag selection corner
    private func dragSelectionCorner(_ corner: CropHandleCorner, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 14, height: 14)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .gesture(resizeGesture(corner))
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { slot in
                let gestureAnchorRect = beginGesture()
                let dragMinX = cropSideInset
                let dragMaxX = max(dragMinX, cropCanvas.width - cropSideInset - gestureAnchorRect.width)
                let dragMinY = topReserve
                let dragMaxY = max(dragMinY, cropCanvas.height - cropBottomReserve - gestureAnchorRect.height)
                selectedRect.origin = CGPoint(
                    x: min(max(gestureAnchorRect.minX + slot.translation.width, dragMinX), dragMaxX),
                    y: min(max(gestureAnchorRect.minY + slot.translation.height, dragMinY), dragMaxY)
                )
            }
            .onEnded { _ in gestureStart = nil }
    }

    // resize gesture
    private func resizeGesture(_ corner: CropHandleCorner) -> some Gesture {
        DragGesture(coordinateSpace: .local)
            .onChanged { slot in
                let gestureAnchorRect = beginGesture()
                let fingerPoint = CGPoint(
                    x: corner.isLeft
                        ? gestureAnchorRect.minX + slot.translation.width : gestureAnchorRect.maxX + slot.translation.width,
                    y: corner.isTop
                        ? gestureAnchorRect.minY + slot.translation.height : gestureAnchorRect.maxY + slot.translation.height
                )
                let cropLeftBound = cropSideInset
                let cropRightBound = cropCanvas.width - cropSideInset
                let cropCeiling = topReserve
                let cropFloor = cropCanvas.height - cropBottomReserve

                let resizeMinX =
                    corner.isLeft
                    ? min(max(fingerPoint.x, cropLeftBound), gestureAnchorRect.maxX - minCropEdge) : gestureAnchorRect.minX
                let resizeMaxX =
                    corner.isLeft
                    ? gestureAnchorRect.maxX : max(min(fingerPoint.x, cropRightBound), gestureAnchorRect.minX + minCropEdge)
                let resizeMinY =
                    corner.isTop
                    ? min(max(fingerPoint.y, cropCeiling), gestureAnchorRect.maxY - minCropEdge) : gestureAnchorRect.minY
                let resizeMaxY =
                    corner.isTop
                    ? gestureAnchorRect.maxY : max(min(fingerPoint.y, cropFloor), gestureAnchorRect.minY + minCropEdge)
                selectedRect = CGRect(
                    x: resizeMinX, y: resizeMinY, width: resizeMaxX - resizeMinX, height: resizeMaxY - resizeMinY)
            }
            .onEnded { _ in gestureStart = nil }
    }

    // starts gesture
    private func beginGesture() -> CGRect {
        if let gestureStart { return gestureStart }
        gestureStart = selectedRect
        return selectedRect
    }

    private enum CropHandleCorner {
        case topLeft, topRight, bottomLeft, bottomRight
        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }
    }
}

enum PhotoRegionCrop {
    static let cropFrameSide: CGFloat = 252

    // default rect
    static func defaultRect(in size: CGSize) -> CGRect {
        let defaultSide = min(cropFrameSide, max(120, size.width - 80))
        return CGRect(
            x: (size.width - defaultSide) / 2,
            y: (size.height - defaultSide) / 2,
            width: defaultSide,
            height: defaultSide
        )
    }

    // Crops the original bitmap to the selection, handling orientation.
    static func crop(
        sourceBitmap: UIImage, containerSize: CGSize, cropRect: CGRect, zoomScale: CGFloat, panShift: CGSize
    ) -> UIImage {
        let normalizedBitmap = uprightBitmap(sourceBitmap)
        let pixelExtent = normalizedBitmap.size
        guard pixelExtent.width > 0, pixelExtent.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return normalizedBitmap
        }
        let fitScale = max(containerSize.width / pixelExtent.width, containerSize.height / pixelExtent.height)
        let total = fitScale * zoomScale
        let displayW = pixelExtent.width * total
        let displayH = pixelExtent.height * total
        let drawOriginX = (containerSize.width - displayW) / 2 + panShift.width
        let drawOriginY = (containerSize.height - displayH) / 2 + panShift.height
        var clipFrame = CGRect(
            x: (cropRect.minX - drawOriginX) / total,
            y: (cropRect.minY - drawOriginY) / total,
            width: cropRect.width / total,
            height: cropRect.height / total
        )
        clipFrame = clipFrame.intersection(CGRect(origin: .zero, size: pixelExtent))
        guard clipFrame.width > 8, clipFrame.height > 8, let cg = normalizedBitmap.cgImage else { return normalizedBitmap }
        let pixel = CGRect(
            x: clipFrame.origin.x * normalizedBitmap.scale,
            y: clipFrame.origin.y * normalizedBitmap.scale,
            width: clipFrame.width * normalizedBitmap.scale,
            height: clipFrame.height * normalizedBitmap.scale
        )
        guard let cropped = cg.cropping(to: pixel) else { return normalizedBitmap }
        return UIImage(cgImage: cropped, scale: normalizedBitmap.scale, orientation: .up)
    }

    // upright bitmap
    private static func uprightBitmap(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
