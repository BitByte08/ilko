import AppKit
import SwiftUI

// MARK: - Video Grid View
struct VideoGridView: View {
    let videos: [VideoItem]
    let viewModel: WallpaperViewModel
    let onVideoSelect: (VideoItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 2)]

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = L.selectFolderTitle
                    panel.prompt = L.choose

                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.folderPath = url.path
                        viewModel.engine.selectFolder(url.path())
                        viewModel.reloadContent()
                    }
                } label: {
                    Text(L.selectWallpaperFolder)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(videos) { video in
                        VideoThumbnailButton(video: video, viewModel: viewModel) {
                            onVideoSelect(video)
                        }
                        .id(video.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Video Thumbnail Button
struct VideoThumbnailButton: View {
    let video: VideoItem
    let viewModel: WallpaperViewModel
    let action: () -> Void
    @ObservedObject private var cache = ThumbnailCache.shared

    // 썸네일 생성이 이 시간(초) 안에 끝나지 않으면 스피너 대신 재시도/폴백 UI를 보여준다.
    private let thumbnailTimeout: TimeInterval = 20
    @State private var timedOut = false
    // 재시도 버튼을 누르면 값을 증가시켜 .task(id:)를 새로 시작(타임아웃 재측정)시킨다.
    @State private var retryAttempt = 0

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                let _ = cache.lastUpdate

                if let thumbnail = video.loadThumbnail() {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: 140)
                        .clipped()
                } else if timedOut {
                    thumbnailFallbackView
                } else {
                    thumbnailGeneratingView
                }

                if let quality = video.quality, !quality.isEmpty {
                    QualityBadge(text: quality)
                        .padding(8)
                }
            }
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(video.filename)
        .task(id: "\(video.thumbnailPath)-\(retryAttempt)") {
            timedOut = false
            guard video.loadThumbnail() == nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(thumbnailTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if video.loadThumbnail() == nil {
                timedOut = true
            }
        }
    }

    private var thumbnailGeneratingView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 140)
            .overlay {
                VStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(L.generating)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
    }

    private var thumbnailFallbackView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 140)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text(video.filename)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)

                    Button {
                        // 미리보기 재생성 재시도: 캐시 무효화 후 엔진에 재생성 요청, 타이머도 다시 시작.
                        viewModel.regenerateThumbnails(for: video.thumbnailPath)
                        retryAttempt += 1
                    } label: {
                        Label(L.retry, systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
    }
}

// MARK: - Quality Badge
struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.black, lineWidth: 1)
            )
    }
}
