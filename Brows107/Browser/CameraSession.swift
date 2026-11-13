//
//  CameraSession.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 08/11/26.
//

import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO


/// AVCapture session wrapper.
final class LiveCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let captureSession = AVCaptureSession()
    private let photoCaptureSink = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "brows.camera", qos: .userInitiated)
    private let imageQueue = DispatchQueue(label: "brows.camera.image", qos: .userInitiated)
    private var position: AVCaptureDevice.Position = .back
    private var onCapture: (@MainActor @Sendable (UIImage?) -> Void)?
    @Published var running = false

    // starts it
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                DispatchQueue.main.async { self.running = true }
                return
            }
            self.configure(shouldRun: true)
        }
    }

    // stops it
    func stop() {
        queue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async { self.running = false }
        }
    }

    func flip() {
        queue.async { [weak self] in
            guard let self else { return }
            self.position = self.position == .back ? .front : .back
            self.configure(shouldRun: true)
        }
    }

    // Torch on/off; reports the new state.
    func toggleTorch(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self, let device = self.currentDevice, device.hasTorch else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let on: Bool
            do {
                try device.lockForConfiguration()
                on = device.torchMode != .on
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                on = false
            }
            DispatchQueue.main.async { completion(on) }
        }
    }

    // captures it
    func capture(completion: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.onCapture = completion
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            if let device = self.currentDevice, device.hasFlash {
                settings.flashMode = device.torchMode == .on ? .on : .off
            }
            self.photoCaptureSink.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let payloadBytes = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.onCapture?(nil) }
            return
        }
        imageQueue.async { [weak self] in
            let shot = PhotoSearchJPEG.decodeDownsampled(payloadBytes: payloadBytes, maxPixelSize: 1600)
            DispatchQueue.main.async { self?.onCapture?(shot) }
        }
    }

    private var currentDevice: AVCaptureDevice? {
        captureSession.inputs.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first
    }

    // Configure
    private func configure(shouldRun: Bool) {
        captureSession.beginConfiguration()
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
        for input in captureSession.inputs { captureSession.removeInput(input) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            DispatchQueue.main.async { self.running = false }
            return
        }
        captureSession.addInput(input)
        if !captureSession.outputs.contains(photoCaptureSink), captureSession.canAddOutput(photoCaptureSink) {
            captureSession.addOutput(photoCaptureSink)
            photoCaptureSink.maxPhotoQualityPrioritization = .balanced
        }
        captureSession.commitConfiguration()
        if shouldRun, !captureSession.isRunning { captureSession.startRunning() }
        DispatchQueue.main.async { self.running = self.captureSession.isRunning }
    }
}

struct CameraPreview: UIViewRepresentable {
    let captureSession: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let hostName = PreviewView()
        hostName.preview.videoGravity = .resizeAspectFill
        hostName.preview.session = captureSession
        return hostName
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.preview.session !== captureSession { uiView.preview.session = captureSession }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = preview.connection else { return }
            let angle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
        }
    }
}
