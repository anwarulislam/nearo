//
//  PhotosPane.swift
//  Nearo
//
//  A high-performance photo gallery for photos stored on the connected phone.
//  Uses fast synchronous in-memory thumbnail lookup, paginated grid rendering,
//  and on-demand large image preview.
//

import AppKit
import SwiftUI

public struct PhotosPane: View {
    @Environment(\.workspaceTheme) private var theme
    @Bindable var device: DeviceViewModel

    @State private var selectedPhotos: Set<String> = []
    @State private var isDownloading = false
    @State private var downloadStatus = ""
    @Binding private var searchText: String
    @State private var selectedFolder: String? = nil
    @State private var previewPhoto: PhonePhoto? = nil

    // Performance: Paginate rendered cells to maintain silky smooth 120 FPS
    @State private var displayLimit = 90
    @State private var filteredPhotos: [PhonePhoto] = []
    @State private var availableFolders: [String] = ["All"]

    public init(device: DeviceViewModel, searchText: Binding<String> = .constant("")) {
        self.device = device
        self._searchText = searchText
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                if device.photos.isEmpty && device.isLoadingPhotos {
                    loadingView
                } else if device.photos.isEmpty {
                    emptyGalleryView
                } else if filteredPhotos.isEmpty {
                    emptySearchView
                } else {
                    photosGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Large Image Preview Modal
            if let photo = previewPhoto {
                PhotoPreviewModal(
                    photo: photo,
                    deviceId: device.id,
                    photosList: filteredPhotos,
                    onSelectPhoto: { previewPhoto = $0 },
                    onDismiss: { previewPhoto = nil }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.15), value: previewPhoto != nil)
        .onAppear {
            recomputeFilters()
            if device.photos.isEmpty {
                device.refreshPhotos()
            }
        }
        .onChange(of: device.photos) {
            selectedPhotos.formIntersection(device.photos.map(\.id))
            recomputeFilters()
        }
        .onChange(of: searchText) {
            recomputeFilters()
        }
        .onChange(of: selectedFolder) {
            recomputeFilters()
        }
    }

    private func recomputeFilters() {
        // Compute available folders
        var folders = Set<String>()
        for photo in device.photos {
            if !photo.folder.isEmpty {
                folders.insert(photo.folder)
            }
        }
        availableFolders = ["All"] + folders.sorted()

        // Filter photos
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let folderFilter = (selectedFolder == nil || selectedFolder == "All") ? nil : selectedFolder?.lowercased()

        let filtered = device.photos.filter { photo in
            if let folderFilter, photo.folder.lowercased() != folderFilter {
                return false
            }
            if query.isEmpty {
                return true
            }
            return photo.name.localizedCaseInsensitiveContains(query)
                || photo.folder.localizedCaseInsensitiveContains(query)
        }

        self.filteredPhotos = filtered
        self.displayLimit = 90
    }

    // MARK: - Top Bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Photos").font(.system(size: 25, weight: .semibold))
                    Text("Photos and albums on " + device.name).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { device.refreshPhotos() } label: { WorkspaceLabel("Refresh", .refresh) }
                    .glassButton().disabled(device.isLoadingPhotos || !device.isConnected)
            }

            HStack(spacing: 9) {
                ScrollView(.horizontal, showsIndicators: false) { folderPicker }
                Spacer(minLength: 0)
                downloadButton
            }
            HStack {
                if device.isLoadingPhotos { ProgressView().controlSize(.small) }
                Text(device.isLoadingPhotos ? "Scanning…" : summaryText)
                Spacer()
                Text(downloadStatus.isEmpty ? "Recently added" : downloadStatus)
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 12)
    }

    private var folderPicker: some View {
        HStack(spacing: 2) {
            ForEach(availableFolders, id: \.self) { folder in
                let selected = (selectedFolder ?? "All") == folder
                Button {
                    selectedFolder = folder == "All" ? nil : folder
                } label: {
                    Text(folder).font(.callout).lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(selected ? theme.color(.panel) : .clear, in: .rect(cornerRadius: 5))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize().padding(2).workspaceField()
    }

    private var downloadButton: some View {
        Button {
            let photos = device.photos.filter { selectedPhotos.contains($0.id) }
            isDownloading = true
            downloadStatus = "Downloading…"
            Task {
                var saved = Set<String>()
                for photo in photos {
                    do {
                        try await PhotoDownloads.shared.save(photo)
                        saved.insert(photo.id)
                    } catch {
                        downloadStatus = error.localizedDescription
                    }
                }
                selectedPhotos.subtract(saved)
                isDownloading = false
                let failed = photos.count - saved.count
                downloadStatus = failed == 0 ? "Saved to Downloads" : "Saved \(saved.count) · \(failed) failed"
            }
        } label: {
            WorkspaceLabel(selectedPhotos.isEmpty ? "Download" : "Download (\(selectedPhotos.count))", .download)
        }
        .buttonStyle(.borderedProminent).disabled(selectedPhotos.isEmpty || isDownloading)
    }

    private var summaryText: String {
        if searchText.isEmpty && (selectedFolder == nil || selectedFolder == "All") {
            return "\(device.photos.count) Photos"
        } else {
            return "\(filteredPhotos.count) of \(device.photos.count) Photos"
        }
    }

    // MARK: - Photos Grid

    private var visiblePhotos: [PhonePhoto] {
        Array(filteredPhotos.prefix(displayLimit))
    }

    private var photosGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 133), spacing: 6)],
                spacing: 6
            ) {
                ForEach(visiblePhotos) { photo in
                    PhotoGridCell(
                        photo: photo,
                        deviceId: device.id,
                        isSelected: selectedPhotos.contains(photo.id),
                        toggle: {
                            if selectedPhotos.contains(photo.id) { selectedPhotos.remove(photo.id) }
                            else { selectedPhotos.insert(photo.id) }
                            downloadStatus = ""
                        },
                        onSelect: { previewPhoto = photo }
                    )
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 18)

            // Infinite scroll trigger
            if displayLimit < filteredPhotos.count {
                Color.clear
                    .frame(height: 40)
                    .onAppear {
                        displayLimit = min(displayLimit + 80, filteredPhotos.count)
                    }
            }
        }
    }

    // MARK: - Empty & Loading States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning Photos on \(device.name)…")
                .font(.headline)
            Text("Discovering pictures in DCIM, Camera, and Downloads.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyGalleryView: some View {
        ContentUnavailableView {
            Label("No Photos Found", systemImage: "photo.stack.fill")
        } description: {
            Text("Make sure \(device.name) is connected and mounted, and has photos stored in DCIM, Pictures, or Downloads.")
        } actions: {
            Button("Scan for Photos") {
                device.refreshPhotos()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchView: some View {
        ContentUnavailableView {
            Label("No Matching Photos", systemImage: "magnifyingglass")
        } description: {
            Text("No photos matching \"\(searchText)\" were found.")
        } actions: {
            Button("Clear Filter") {
                searchText = ""
                selectedFolder = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid Cell

private struct PhotoGridCell: View {
    @Environment(\.workspaceTheme) private var theme
    let photo: PhonePhoto
    let deviceId: String
    let isSelected: Bool
    let toggle: () -> Void
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?

    init(photo: PhonePhoto, deviceId: String, isSelected: Bool, toggle: @escaping () -> Void, onSelect: @escaping () -> Void) {
        self.photo = photo
        self.deviceId = deviceId
        self.toggle = toggle
        self.isSelected = isSelected
        self.onSelect = onSelect
        // Fast-path: Synchronous RAM cache hit eliminates initial blank flicker
        _thumbnail = State(initialValue: PhotoThumbnailService.shared.cachedThumbnail(for: photo.id))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    Rectangle().fill(theme.color(.panel))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                            else { WorkspaceIcon.image.view(22).foregroundStyle(.tertiary) }
                        }
                        .clipShape(.rect(cornerRadius: 3))
                    Text(photo.name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(photo.folder) · \(photo.formattedSize)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(3)
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected ? theme.color(.accent) : .clear, lineWidth: 2) }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(action: toggle) {
                ZStack {
                    Circle().fill(isSelected ? theme.color(.selection) : Color.black.opacity(0.25))
                    Circle().strokeBorder(.white.opacity(0.9))
                    if isSelected { WorkspaceIcon.check.view(12).foregroundStyle(.white) }
                }.frame(width: 18, height: 18)
            }
            .buttonStyle(.plain).padding(7)
            .accessibilityLabel((isSelected ? "Deselect " : "Select ") + photo.name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .task(id: photo.id) {
            if thumbnail == nil {
                let img = await PhotoThumbnailService.shared.thumbnail(for: photo, deviceId: deviceId)
                if !Task.isCancelled {
                    self.thumbnail = img
                }
            }
        }
    }
}

// MARK: - Photo Preview Modal

private struct PhotoPreviewModal: View {
    let photo: PhonePhoto
    let deviceId: String
    let photosList: [PhonePhoto]
    let onSelectPhoto: (PhonePhoto) -> Void
    let onDismiss: () -> Void

    @State private var fullImage: NSImage?
    @State private var previewThumbnail: NSImage?
    @State private var isLoadingFull = true
    @State private var downloadError: String?
    @State private var isSavedToDownloads = false
    @State private var keyMonitor: Any?

    private var currentIndex: Int {
        photosList.firstIndex(where: { $0.id == photo.id }) ?? 0
    }

    private var hasPrevious: Bool {
        currentIndex > 0
    }

    private var hasNext: Bool {
        currentIndex < photosList.count - 1
    }

    var body: some View {
        ZStack {
            // Dark Backdrop
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Main Content Area
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Spacer(minLength: 8)

                // Image with Chevrons
                HStack(spacing: 16) {
                    chevronButton(direction: .left, isEnabled: hasPrevious) {
                        selectPrevious()
                    }

                    imageContainer
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    chevronButton(direction: .right, isEnabled: hasNext) {
                        selectNext()
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 8)

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .task(id: photo.id) {
            loadPhotoData()
        }
        .alert("Couldn’t save photo", isPresented: Binding(get: { downloadError != nil }, set: { if !$0 { downloadError = nil } })) {
            Button("OK") { downloadError = nil }
        } message: { Text(downloadError ?? "") }
        .onAppear {
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
    }

    // MARK: - Modal Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .help(photo.name)

                HStack(spacing: 8) {
                    Text(photo.folder)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: .capsule)

                    Text("\(currentIndex + 1) of \(photosList.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Image Container

    private var imageContainer: some View {
        ZStack {
            if let fullImage {
                Image(nsImage: fullImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                    .transition(.opacity)
            } else if let previewThumbnail {
                Image(nsImage: previewThumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .blur(radius: 2)
                    .overlay {
                        if isLoadingFull {
                            ProgressView()
                                .controlSize(.large)
                        }
                    }
            } else {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    // MARK: - Modal Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Metadata
            VStack(alignment: .leading, spacing: 2) {
                Text(photo.modifiedDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                Text(photo.formattedSize)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Actions
            HStack(spacing: 10) {
                // Save to Downloads
                Button {
                    saveToDownloads()
                } label: {
                    if isSavedToDownloads {
                        WorkspaceLabel("Saved", .check)
                            .foregroundStyle(.green)
                    } else {
                        WorkspaceLabel("Save to Downloads", .download)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.bordered)
                .help("Save a copy to your Mac's Downloads folder")

                // Reveal in Finder
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([photo.url])
                } label: {
                    Label("Finder", systemImage: "folder.fill")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .help("Reveal file on mounted phone drive")

                // Copy Image
                Button {
                    copyImageToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc.fill")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .help("Copy image to clipboard")

                // Native Share Link
                ShareLink(item: photo.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .help("Share photo")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Navigation Buttons

    private enum ChevronDirection {
        case left, right
        var systemName: String {
            switch self {
            case .left: "chevron.left.circle.fill"
            case .right: "chevron.right.circle.fill"
            }
        }
    }

    private func chevronButton(direction: ChevronDirection, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: direction.systemName)
                .font(.system(size: 36))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.white.opacity(0.2)))
                .shadow(color: .black.opacity(0.3), radius: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(direction == .left ? "Previous (Left Arrow)" : "Next (Right Arrow)")
    }

    // MARK: - Actions & Helpers

    private func selectPrevious() {
        guard hasPrevious else { return }
        onSelectPhoto(photosList[currentIndex - 1])
    }

    private func selectNext() {
        guard hasNext else { return }
        onSelectPhoto(photosList[currentIndex + 1])
    }

    private func loadPhotoData() {
        isLoadingFull = true
        fullImage = nil
        isSavedToDownloads = false

        previewThumbnail = PhotoThumbnailService.shared.cachedThumbnail(for: photo.id)

        let fileURL = photo.url
        Task.detached(priority: .userInitiated) {
            let loaded: NSImage?
            if let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                loaded = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } else {
                loaded = NSImage(contentsOf: fileURL)
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.fullImage = loaded
                    self.isLoadingFull = false
                }
            }
        }
    }

    private func saveToDownloads() {
        Task {
            do {
                try await PhotoDownloads.shared.save(photo)
                isSavedToDownloads = true
            } catch {
                downloadError = error.localizedDescription
            }
        }
    }

    private func copyImageToClipboard() {
        if let image = fullImage ?? previewThumbnail {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 123: // Left arrow
                selectPrevious()
                return nil
            case 124: // Right arrow
                selectNext()
                return nil
            case 53: // Escape
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

/// Single and multiple selections use the same collision-safe destination on a background actor.
actor PhotoDownloads {
    static let shared = PhotoDownloads()

    func save(_ photo: PhonePhoto) throws {
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let destination = SafeFilename.uniqueURL(in: downloads, for: photo.name)
        try FileManager.default.copyItem(at: photo.url, to: destination)
    }
}
