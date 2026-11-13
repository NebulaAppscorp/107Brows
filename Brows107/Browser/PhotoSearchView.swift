//
//  PhotoSearchView.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 03/11/26.
//

import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO

/// Camera / gallery screen for visual search.
struct PhotoSearchView: View {
    @Environment(BrowserStore.self) private var vault
    @Environment(\.dismiss) private var dismissSheet
    @StateObject private var liveLens = LiveCamera()
    @State private var galleryToken: PhotosPickerItem?
    @State private var pickedFrame: UIImage?
    @State private var croppedImage: UIImage?
    @State private var cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var visualSearchBusy = false
    @State private var matchesVisible = false
    @State private var searchState: VisualSearchState = .results
    @State private var visualHits: [VisualMatch]?
    @State private var visualAnswer: String?
    @State private var hasUserQuestion = false
    @State private var torchLit = false
    @State private var showRecents = false
    @State private var visualSearchFlight: Task<Void, Never>?
    @State private var currentPhotoHistoryID: UUID?
    @State private var editingRegion = false
    @State private var photoQuestion = ""
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var photoQuestionFocused: Bool
    @State private var regionScale: CGFloat = 1
    @State private var regionOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var defaultViewfinderRect: CGRect = .zero
    @State private var selectionRect: CGRect = .zero
    @AppStorage("photoSearchTeachingDismissed") private var teachingDismissed = false

    var body: some View {
        Group {
            if matchesVisible {
                VisualMatchesView(
                    querySnapshot: croppedImage ?? pickedFrame, searchPhase: searchState, visualHits: visualHits,
                    answerText: visualAnswer, questionMode: hasUserQuestion, tapRetry: retryVisualSearch
                ) {
                    retakePhoto()
                }
            } else {
                GeometryReader { geo in
                    ZStack {
                        // handle shot bitmap if it is there
                        if let shotBitmap = pickedFrame, (editingRegion || visualSearchBusy) {
                            PhotoRegionCanvas(
                                sourceBitmap: shotBitmap,
                                zoomScale: $regionScale,
                                panShift: $regionOffset,
                                gesturesEnabled: editingRegion && !visualSearchBusy
                            )
                            // Size matches the mock
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        } else {
                            cameraBackground(size: geo.size)
                                // fixed size from the design
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .allowsHitTesting(false)
                        }
                        cameraChrome
                            .zIndex(10)
                    }
                    // size matches the mock
                    .frame(width: geo.size.width, height: geo.size.height) 
                    .clipped()
                    .coordinateSpace(name: "photo-search")
                    .onAppear { containerSize = geo.size }
                    // follow the value, not the action
                    .onChange(of: geo.size) { _, slot in containerSize = slot }
                }
                .onPreferenceChange(ViewfinderRectKey.self) { slot in
                    guard slot.width > 0 else { return }
                    defaultViewfinderRect = slot
                    if selectionRect == .zero {
                        selectionRect = slot
                    }
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        // native toolbar, so the glass comes for free
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if !matchesVisible { startCamera() } }  
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = max(0, UIScreen.main.bounds.height - frame.minY)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            self.keyboardHeight = 0
        } 
        // cleanup
        .onDisappear {
            liveLens.stop()
            visualSearchFlight?.cancel()
        }
        .onChange(of: galleryToken) { _, pickerToken in
            guard let pickerToken else { return }
            // runs off the current call stack
            Task {
                guard let slot = await loadPickerImage(pickerToken) else {
                    self.vault.bannerText = "This photo couldn’t be loaded. Try another image."
                    galleryToken = nil
                    return
                }
                // suspends here until the result is back
                let decodedShot = await Task.detached(priority: .userInitiated) {
                    PhotoSearchJPEG.downsampleForDisplay(ImagePayload(slot).bitmap)
                }.value
                commitPickedPhoto(decodedShot, chooseRegion: true)
                galleryToken = nil
            }
        }
        // sheet for the current route
        .sheet(isPresented: $showRecents) {
            RecentPhotosView { record, picked in
                showRecents = false
                openRecentPhoto(record, picked)
            }
        }
    }

    // active selection binding
    private func activeSelectionBinding(in size: CGSize) -> Binding<CGRect> {
        Binding(
            get: { layoutCropRect(in: size) },
            set: { selectionRect = $0 }
        )
    }


    // layout crop rect
    private func layoutCropRect(in size: CGSize) -> CGRect {
        if selectionRect.width > 0 { return selectionRect }
        if defaultViewfinderRect.width > 0 { return defaultViewfinderRect }
        return photoSelectionRect(in: size)  
    }

    // photo selection rect
    private func photoSelectionRect(in size: CGSize) -> CGRect {
        let topEdge: CGFloat = 134
        // local shutter top
        let shutterTop = size.height - 58 - 74
        let questionCenterY = min(640, shutterTop - 82)
        // available height
        let availableHeight = max(120, questionCenterY - 22 - 24 - topEdge)
        let side = min(300, max(120, size.width - 102), availableHeight)
        let defaultCenterY = defaultViewfinderRect.width > 0 ? defaultViewfinderRect.midY + 4 : size.height / 2 - 7
        // work out the min center y
        let minCenterY = topEdge + side / 2
        let maxCenterY = questionCenterY - 22 - 24 - side / 2
        // Work out the center y
        let centerY = min(max(defaultCenterY, minCenterY), maxCenterY)
        return CGRect(x: (size.width - side) / 2, y: centerY - side / 2, width: side, height: side)
    }

    // camera chrome section
    private var cameraChrome: some View {
        GeometryReader { proxy in
            let showSelectionOverlay = editingRegion || (visualSearchBusy && pickedFrame != nil)
            let stageWidth = proxy.size.width
            let viewportHeight = proxy.size.height
            // work out the top reserve
            let topReserve = max(proxy.safeAreaInsets.top + 8, 70)
            let shutterReserve = max(proxy.safeAreaInsets.bottom + 24, 58)
            let topChromeBottom = topReserve + 40
            // Local shutter top
            let shutterTop = viewportHeight - shutterReserve - 74
            let focusSide: CGFloat = 252
            let focusCenterY = (topChromeBottom + shutterTop) / 2
            let hintTop = focusCenterY + focusSide / 2 + 24
            let keyboardTop = viewportHeight - keyboardHeight
            let questionCenterY = keyboardHeight > 0 ? max(topReserve + 22, keyboardTop - 34) : min(640, shutterTop - 82)
            ZStack {
                if showSelectionOverlay {
                    ResizablePhotoSelection(
                        selectedRect: activeSelectionBinding(in: proxy.size),
                        cropCanvas: proxy.size,
                        gesturesEnabled: editingRegion && !visualSearchBusy,
                        selectionPending: visualSearchBusy
                    )
                }
                if visualSearchBusy {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            // Size matches the mock
                            .frame(width: 82, height: 82)
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Palette.rgb(0x3DDC97))
                            .scaleEffect(1.8)
                    }
                    // fixed size from the design
                    .frame(width: 82, height: 82)
                    .position(
                        x: stageWidth / 2,
                        y: showSelectionOverlay && selectionRect.height > 0 ? selectionRect.midY : focusCenterY
                    )
                    .accessibilityLabel("Searching the web for this photo")
                    .accessibilityIdentifier("photo.search.processing")
                    .zIndex(5)
                }
                if !showSelectionOverlay {
                    ViewfinderCorners()
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter))
                        // size matches the mock
                        .frame(width: focusSide, height: focusSide) 
                        // background goes behind everything
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: ViewfinderRectKey.self,
                                    value: geometry.frame(in: .named("photo-search"))
                                )  
                            }
                        }
                        .position(x: stageWidth / 2, y: focusCenterY)
                        .allowsHitTesting(false)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        cameraControl("xmark", label: (editingRegion || visualSearchBusy) ? "Cancel crop" : "Close") {
                            if editingRegion || visualSearchBusy {
                                visualSearchFlight?.cancel()
                                visualSearchBusy = false
                                cancelRegionEdit()
                            } else {
                                dismissSheet()
                            }
                        }
                        Spacer(minLength: 0)
                        if !editingRegion && !visualSearchBusy {
                            cameraControl(torchLit ? "bolt.fill" : "bolt.slash", label: "Flash") {
                                liveLens.toggleTorch { torchLit = $0 }
                            }
                            cameraControl("arrow.triangle.2.circlepath.camera", label: "Switch camera") { liveLens.flip() }
                        }
                    }
                    // spacing from the design
                    .padding(.horizontal, 16)
                    // spacing from the design
                    .padding(.top, topReserve)
                    Spacer(minLength: 0)
                    shutterRow
                        // fixed size from the design
                        .frame(height: 74)
                        .padding(.horizontal, 36)
                        // spacing from the design
                        .padding(.bottom, shutterReserve)
                }
                // fixed size from the design
                .frame(width: stageWidth, height: viewportHeight)    
                if !showSelectionOverlay {
                    hintPill
                        // fixed size from the design
                        .frame(maxWidth: .infinity, alignment: .center)
                        // Breathing room
                        .padding(.top, hintTop)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
                if editingRegion && !visualSearchBusy {
                    photoQuestionField
                        // fixed size from the design
                        .frame(width: min(330, max(240, stageWidth - 72)), height: 44)
                        .position(x: stageWidth / 2, y: questionCenterY)
                }
                if showTeachingCard {
                    photoTeachingCard
                }
            }
            // size matches the mock
            .frame(width: stageWidth, height: viewportHeight)
        } 
    }

}

// MARK: - PhotoSearchView helpers
extension PhotoSearchView {
    // Photo question field (view)
    private var photoQuestionField: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.ui(14, weight: .regular))
                .foregroundStyle(Palette.brandInk)
            TextField("Add a question (optional)", text: $photoQuestion)
                .focused($photoQuestionFocused)
                .onSubmit { photoQuestionFocused = false }
                .font(.ui(15))
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
        // spacing from the design 
        .padding(.horizontal, 14)
        // size matches the mock
        .frame(maxWidth: .infinity, maxHeight: .infinity) 
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
        .accessibilityIdentifier("photo.question")
    }


    private var showTeachingCard: Bool {
        !teachingDismissed && !editingRegion && !visualSearchBusy && pickedFrame == nil && !matchesVisible
    }

    // Hint pill row
    private var hintPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.ui(13, weight: .regular))
            Text(hint)
                .font(.ui(15, weight: .regular))
                .tracking(-0.23)
        }
        .foregroundStyle(.white)
        // spacing from the design
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        // background goes behind everything
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                // background goes behind everything
                .background(Capsule().fill(Color.black.opacity(0.38)))
        }
    }

    // Shutter row, built separately to keep body short
    private var shutterRow: some View {
        HStack(alignment: .center) {
            // Tap handler below
            Button {
                showRecents = true
            } label: {
                Image(systemName: "clock")
                    .font(.ui(18))
                    .foregroundStyle(.white)
                    // size matches the mock
                    .frame(width: 46, height: 46)
                    .browsGlassBackground(radius: 14)
            }
            .buttonStyle(.plain)
            .disabled(visualSearchBusy)
            .opacity(visualSearchBusy ? 0.45 : 1)
            .accessibilityLabel("Recent searches")
            Spacer(minLength: 0)
            // Plain button, styling comes from the modifiers
            Button {
                editingRegion ? confirmRegionSearch() : capture()
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4)
                    Circle().fill(Palette.rgb(0x3DDC97)).frame(width: 58, height: 58)
                }
                // Fixed size from the design
                .frame(width: 74, height: 74)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(visualSearchBusy)
            .accessibilityLabel(editingRegion ? "Search this photo" : "Take photo")
            Spacer(minLength: 0)
            if editingRegion {
                Button {
                    cancelRegionEdit()  
                } label: {
                    GalleryButtonLabel()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick another photo")
            } else {
                PhotosPicker(selection: $galleryToken, matching: .images) {
                    GalleryButtonLabel()
                }
                .buttonStyle(.plain)
                .disabled(visualSearchBusy)
                .opacity(visualSearchBusy ? 0.45 : 1)
                .accessibilityLabel("Photo library")
            }
        }
    }

    // photo teaching card, built separately to keep body short
    private var photoTeachingCard: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.brandInk)
                    // fixed size from the design
                    .frame(width: 52, height: 52)
                Image(systemName: "viewfinder")
                    .font(.ui(24))
                    .foregroundStyle(Palette.rgb(0x0A2E20))
            }
            Spacer().frame(height: 22)
            Text("Point at one thing")
                .font(.ui(20, weight: .semibold))  
                .tracking(-0.45)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 8)
            Text("One object in the frame works better than a whole shelf. Hold steady until the frame locks.")
                .font(.ui(15))
                .tracking(-0.23)
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)  
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 20)
            Button("Got it") { teachingDismissed = true }
                .font(.ui(17, weight: .semibold))    
                .tracking(-0.43)
                .foregroundStyle(Palette.rgb(0x0A2E20))
                // spacing from the design
                .padding(.horizontal, 24)
                // Breathing room
                .padding(.vertical, 15)
                // background goes behind everything
                .background(Palette.brandInk, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(22)
        // Size matches the mock
        .frame(width: 330)
        // background fill
        .background(Palette.rgb(0x141B18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // camera control
    private func cameraControl(_ iconName: String, label: String, action: @escaping () -> Void) -> some View {
        // tap handler below
        Button(action: action) {
            Image(systemName: iconName)
                .font(.ui(16, weight: .regular))
                .foregroundStyle(.white)
                // Size matches the mock
                .frame(width: 40, height: 40)
                .browsGlassCircle()
        } 
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // camera background
    @ViewBuilder private func cameraBackground(size: CGSize) -> some View {
        if let shotBitmap = pickedFrame {
            Color.black
                // size matches the mock
                .frame(width: size.width, height: size.height)
                .overlay {
                    Image(uiImage: shotBitmap)
                        .resizable()
                        .scaledToFill()
                        // fixed size from the design
                        .frame(width: size.width, height: size.height)
                }
                .overlay(.black.opacity(0.24)) 
                .clipped()
                .ignoresSafeArea()
        } else if liveLens.running {
            CameraPreview(captureSession: liveLens.captureSession)
                .frame(width: size.width, height: size.height)
                .clipped()
                .ignoresSafeArea()
        } else {
            // work out the stage scale
            let stageScale = size.width / 402
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Palette.rgb(0x212926), location: 0),
                        .init(color: Palette.rgb(0x121716), location: 0.55),
                        .init(color: Palette.rgb(0x080A09), location: 1),
                    ]), startPoint: .top, endPoint: .bottom)
                Ellipse()
                    .fill(Palette.rgb(0x3D574D).opacity(0.55))
                    .frame(width: 360 * stageScale, height: 300 * stageScale)
                    .blur(radius: 90 * stageScale * 0.42)
                    .offset(x: 30 * stageScale, y: 300 * stageScale)
            }
            // Fixed size from the design
            .frame(width: size.width, height: size.height)
            .clipped()
            .ignoresSafeArea()
        }
    }

    private var hint: String {
        if visualSearchBusy { return "Searching the web for this photo" }
        if cameraAuth == .denied || cameraAuth == .restricted { return "Camera access is off" }
        if editingRegion { return "Resize the frame, then search" }
        if pickedFrame != nil { return "Photo ready" }
        return "Point at an object to search"
    }

    // Takes a picked photo and moves on to region selection.
    private func commitPickedPhoto(_ slot: UIImage, chooseRegion: Bool) {
        let size = containerSize == .zero ? CGSize(width: 402, height: 874) : containerSize
        pickedFrame = slot
        croppedImage = nil
        liveLens.stop()
        editingRegion = chooseRegion
        visualAnswer = nil
        visualHits = nil
        hasUserQuestion = false
        currentPhotoHistoryID = nil
        regionScale = 1
        regionOffset = .zero
        selectionRect =
            chooseRegion
            ? photoSelectionRect(in: size)
            : (defaultViewfinderRect.width > 0 ? defaultViewfinderRect : PhotoRegionCrop.defaultRect(in: size))
        if chooseRegion {
            photoQuestion = ""
            return
        }
        search()
    }

    // opens the recent photo
    private func openRecentPhoto(_ record: RecentPhoto, _ image: UIImage) {
        Task {
            let payload = ImagePayload(image)
            // Async hop, keep the work above it cheap
            let decoded = await Task.detached(priority: .userInitiated) {
                PhotoSearchJPEG.downsampleForDisplay(payload.bitmap)
            }.value
            // No raw phase, no point continuing
            guard let rawPhase = record.searchPhase, let phase = VisualSearchState(rawValue: rawPhase) else {
                commitPickedPhoto(decoded, chooseRegion: true) 
                return
            }
            pickedFrame = decoded
            croppedImage = decoded
            editingRegion = false
            regionScale = 1
            regionOffset = .zero
            selectionRect = .zero
            currentPhotoHistoryID = record.id
            photoQuestion = record.prompt ?? ""
            hasUserQuestion = !photoQuestion.isEmpty
            visualAnswer = record.answerText
            visualHits = VisualMatch.fromSavedPages(record.savedPages ?? [])
            self.searchState = phase
            matchesVisible = true
        }
    }

    // Confirm region search
    private func confirmRegionSearch() {
        guard !visualSearchBusy, let frameStill = pickedFrame else { return }
        guard !vault.incognito else {
            vault.bannerText = "Photo search is off in private mode."
            return
        }
        let size = containerSize == .zero ? CGSize(width: 402, height: 874) : containerSize
        let targetRect = layoutCropRect(in: size)
        selectionRect = targetRect
        let regionZoom = regionScale
        let offset = regionOffset
        let question = photoQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let rasterEnvelope = ImagePayload(frameStill)
        self.photoQuestionFocused = false
        editingRegion = false
        visualSearchBusy = true
        visualAnswer = nil
        visualHits = nil
        hasUserQuestion = !question.isEmpty
        visualSearchFlight = Task {
            // Suspends here until the result is back
            let cropped = await Task.detached(priority: .userInitiated) {
                PhotoRegionCrop.crop(
                    sourceBitmap: rasterEnvelope.bitmap,
                    containerSize: size,
                    cropRect: targetRect,
                    zoomScale: regionZoom,
                    panShift: offset
                )
            }.value
            guard !Task.isCancelled else {
                visualSearchBusy = false
                return
            }
            croppedImage = cropped
            // wait for it before moving on
            await performSearch(for: cropped, question: question)
        }
    }

    // Cancels region edit
    private func cancelRegionEdit() {
        editingRegion = false
        pickedFrame = nil
        croppedImage = nil
        self.regionScale = 1
        regionOffset = .zero
        selectionRect = .zero
        startCamera()
    }


    // loads picker image
    private func loadPickerImage(_ pickerToken: PhotosPickerItem) async -> UIImage? {
        if let payloadBytes = try? await pickerToken.loadTransferable(type: Data.self) {
            return await Task.detached(priority: .userInitiated) {
                PhotoSearchJPEG.decodeDownsampled(payloadBytes: payloadBytes, maxPixelSize: 1600) ?? UIImage(data: payloadBytes)    
            }.value
        }
        // picked payload must exist here
        guard let pickedPayload = try? await pickerToken.loadTransferable(type: PickedPhotoData.self) else { return nil }
        let raw = pickedPayload.payloadBytes
        return await Task.detached(priority: .userInitiated) {
            PhotoSearchJPEG.decodeDownsampled(payloadBytes: raw, maxPixelSize: 1600) ?? UIImage(data: raw)
        }.value
    }

    private func startCamera() {
        if cameraAuth == .denied || cameraAuth == .restricted { return }
        Task {
            let allowed = cameraAuth == .authorized ? true : await AVCaptureDevice.requestAccess(for: .video)
            cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
            if allowed { liveLens.start() }
        }
    }

    // captures it
    private func capture() {
        if pickedFrame != nil {
            search()
            return
        }
        if cameraAuth == .denied || cameraAuth == .restricted {
            // only when there is a link url
            if let linkURL = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(linkURL) } 
            return
        }
        guard liveLens.running else { 
            vault.bannerText = "A camera is not available on this device. Choose a photo from your library."
            return
        }
        visualSearchBusy = true
        currentPhotoHistoryID = nil
        visualAnswer = nil
        visualHits = nil
        liveLens.capture { capturedShot in
            // Need shot to go on
            guard let shot = capturedShot else {
                visualSearchBusy = false
                self.vault.bannerText = "Couldn’t take this photo. Try again."
                return
            }
            guard !vault.incognito else {
                visualSearchBusy = false
                vault.bannerText = "Photo search is off in private mode."
                return
            }
            let size = containerSize == .zero ? CGSize(width: 402, height: 874) : containerSize
            let targetRect = defaultViewfinderRect.width > 0 ? defaultViewfinderRect : PhotoRegionCrop.defaultRect(in: size)
            selectionRect = targetRect
            photoQuestion = ""
            let rasterEnvelope = ImagePayload(shot)  
            liveLens.stop()
            pickedFrame = nil
            visualSearchFlight = Task {
                // Async hop, keep the work above it cheap
                let cropped = await Task.detached(priority: .userInitiated) {
                    PhotoRegionCrop.crop(
                        sourceBitmap: rasterEnvelope.bitmap,
                        containerSize: size,
                        cropRect: targetRect,
                        zoomScale: 1,
                        panShift: .zero
                    )
                }.value
                guard !Task.isCancelled else {
                    visualSearchBusy = false
                    return
                }
                // State flips inside the animation block
                withAnimation(.snappy(duration: 0.2)) {
                    pickedFrame = rasterEnvelope.bitmap
                    croppedImage = cropped
                    editingRegion = true
                    visualSearchBusy = false
                }
            }
        }
    }


    // search
    private func search() {
        guard !visualSearchBusy, let shot = pickedFrame else { return }
        guard !vault.incognito else {
            vault.bannerText = "Photo search is off in private mode."
            return
        }
        visualSearchBusy = true
        visualSearchFlight = Task {
            // Suspends here
            await performSearch(for: shot)
        }
    }

    // tries visual search again
    private func retryVisualSearch() {
        // early exit
        guard let shot = croppedImage ?? pickedFrame else { return }
        searchState = .loading
        visualSearchFlight?.cancel()
        // detached from the call site on purpose
        visualSearchFlight = Task {
            await performSearch(for: shot)
        }
    }

    // retake photo
    private func retakePhoto() {
        matchesVisible = false
        self.pickedFrame = nil
        croppedImage = nil
        editingRegion = false
        regionScale = 1
        regionOffset = .zero
        selectionRect = .zero
        startCamera()
    }

    private func performSearch(for shot: UIImage, question: String? = nil) async {  
        defer { visualSearchBusy = false }
        guard await vault.requireServerSubscription(), !Task.isCancelled else { return }
        let historyID = currentPhotoHistoryID ?? UUID()
        currentPhotoHistoryID = historyID
        let questionContext = question ?? photoQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if vault.launchScenario != nil {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                logSwallowed(error)
            }
            guard !Task.isCancelled else { return }
            visualHits = nil
            searchState = .results
            matchesVisible = true
            return
        }
        // work out the raster envelope
        let rasterEnvelope = ImagePayload(shot)
        // async hop, keep the work above it cheap
        let payloadBytes = await Task.detached(priority: .userInitiated) { PhotoSearchJPEG.data(from: rasterEnvelope.bitmap) }
            .value
        // no payload bytes, no point continuing
        guard let payloadBytes, payloadBytes.count <= 5_242_880 else {
            vault.bannerText = APIError.tooLarge.localizedDescription
            return
        }
        do {
            let client = vault.aiService
            hasUserQuestion = !questionContext.isEmpty
            let prompt =
                questionContext.isEmpty
                ? """
                Inspect the attached photo first and identify the actual object, not the act of taking or searching for a photo. Name its category and only visible details: shape, colors, material, distinctive parts, clothing, markings, and likely brand/model when readable. Search for that object using two or more specific visual details. Compare each candidate against the photo before including it.
                Return a brief identification and at most 4 direct pages for the same object or a genuinely close match in the same category. A doll photo must return dolls, not fashion, phones, or image-search products. Each link must open the listing for that matching item itself; only state a price if it is visible on that listing. Do not include image-search tools, tutorials, editorial articles, comparison pages, broad category pages, unrelated products, search results, or generic homepages. Never tell the user to use another service or website. If no close item page can be verified, say that plainly and return no substitute links. Answer in the user's language.
                """
                : """
                The user asks: \(questionContext)
                Inspect the attached photo and answer that question directly, using visible details as evidence. Use web search only to verify facts about the object or find a genuinely close item when useful. Do not guess identity, brand, or price. Any price must come from a direct page for the same item or a close match in the same object category. Never include search-service suggestions, tutorials, editorial articles, broad category/search pages, unrelated products, or generic homepages. If no reliable direct source supports the answer, say that clearly. Answer in the same language as the user's question.
                """
            let reply = try await client.relayChat(
                remoteChatID: UUID().uuidString,
                promptText: prompt,
                additionalPrompt:
                    "Photo result quality rules: use the photo as the primary evidence, identify its object category before searching, and reject any candidate from a different category or without at least two matching visible features. Sources must be direct item pages, not advice about searching or tools that search images. Never tell the user to visit another service, upload the photo elsewhere, or search manually. Prefer zero sources to irrelevant or unverifiable links. Do not invent names, matches, or prices.",
                photoJPEG: payloadBytes,
                sourceIDs: [],
                webLookupEnabled: true,
                think: false
            )
            guard !Task.isCancelled else { return }
            var answer = PhotoSearchJPEG.cleanVisualAnswer(reply.assistantBody)
            visualAnswer = answer
            if answer.isEmpty || answer.uppercased().contains("UNREADABLE") {
                visualHits = []
                searchState = .unreadable
                matchesVisible = true
                // Suspends here
                await RecentPhotoStore.savePhotoResult(
                    shot, id: historyID, question: questionContext, answer: answer, pages: [], phase: .unreadable)
                return
            }
            let candidatePages = PhotoSearchJPEG.savedPagesFromReply(reply) 
            let relevantPages = PhotoSearchJPEG.filterVisualPages(candidatePages, question: questionContext, answer: answer)
            let checkedPages = await PhotoSearchJPEG.verifyVisualPages(relevantPages)
            let deduplicated = PhotoSearchJPEG.deduplicate(checkedPages)
            if deduplicated.isEmpty && (questionContext.isEmpty || answer.isEmpty) {
                answer =
                    "I couldn’t verify any close product matches for this photo. Try a closer crop or add the brand or model if you know it."
                self.visualAnswer = answer
            }
            // found
            let found = VisualMatch.fromSavedPages(deduplicated)
            visualHits = found
            searchState = found.isEmpty ? .empty : .results
            matchesVisible = true
            // wait for it before moving on
            await RecentPhotoStore.savePhotoResult(
                shot, id: historyID, question: questionContext, answer: answer, pages: deduplicated, phase: searchState)
        } catch is CancellationError {
        } catch let error as APIError where error == .network {
            guard !Task.isCancelled else { return }
            visualHits = []
            searchState = .offline
            matchesVisible = true
            // Wait for it before moving on
            await RecentPhotoStore.savePhotoResult(
                shot, id: historyID, question: questionContext, answer: nil, pages: [], phase: .offline)
        } catch {
            if !Task.isCancelled { vault.bannerText = error.localizedDescription }
        }
    }
}


struct ViewfinderRectKey: PreferenceKey {
    // keeps default value
    static let defaultValue: CGRect = .zero
    // Reduce
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

/// Rounded-square glass side button; the glyph is a bundled image, not an SF Symbol.
struct PickedPhotoData: Transferable {
    let payloadBytes: Data

    // current transfer representation
    static var transferRepresentation: some TransferRepresentation { 
        DataRepresentation(importedContentType: .image) { PickedPhotoData(payloadBytes: $0) }
    }
}


struct GalleryButtonLabel: View {
    var body: some View {
        Image("camera_gallery")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 21, height: 16.5)
            // size matches the mock
            .frame(width: 46, height: 46)
            .browsGlassBackground(radius: 14)
    }
}

struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length = min(36, min(rect.width, rect.height) * 0.3)
        let radius = min(14, length * 0.45)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}
