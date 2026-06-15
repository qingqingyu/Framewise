//
//  ContentView.swift
//  Framwise
//
//  Main application view
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var importViewModel = VideoImportViewModel()
    @StateObject private var gridViewModel = ClipGridViewModel()
    @StateObject private var exportViewModel = ExportViewModel()

    @State private var showExportSheet = false
    @State private var showFileImporter = false

    private var hasImportedClips: Bool {
        appState.importSession?.allClips.isEmpty == false
    }

    var body: some View {
        VStack(spacing: 0) {
            appChromeBar

            NavigationView {
                SidebarView()
                    .environmentObject(importViewModel)
                    .frame(minWidth: 280, idealWidth: 300)

                ZStack {
                    FramwiseTheme.appGradient
                        .ignoresSafeArea()

                    if let session = appState.importSession, !session.allClips.isEmpty {
                        ClipGridView()
                            .environmentObject(gridViewModel)
                    } else {
                        DropZoneView()
                            .environmentObject(importViewModel)
                    }
                }
            }
        }
        .background(FramwiseTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView()
                .environmentObject(exportViewModel)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
            if !appState.selectedClipIDs.isEmpty {
                showExportSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importRequested)) { _ in
            showFileImporter = true
        }
    }

    private var appChromeBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [FramwiseTheme.warm.opacity(0.22), FramwiseTheme.accent.opacity(0.38)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("F")
                        .font(.framwiseDisplay(15, weight: .bold))
                        .foregroundStyle(.black.opacity(0.78))
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DIGITAL LIGHT TABLE")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.warm)
                    Text("Framwise")
                        .font(.framwiseDisplay(20, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                }
            }

            Spacer(minLength: 12)

            if importViewModel.isResolvingSources {
                HStack(spacing: 8) {
                    FramwiseLoadingIndicator(tint: FramwiseTheme.warning, diameter: 14)
                    Text("Reading sources")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 16)
            } else if importViewModel.isAnalyzing {
                HStack(spacing: 8) {
                    FramwiseLoadingIndicator(tint: FramwiseTheme.warning, diameter: 14)
                    Text("\(importViewModel.clipsFoundCount) clips found")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 16)
            }

            if let persistenceError = appState.persistenceError {
                Label("Session issue", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.framwiseMono(11))
                    .foregroundStyle(FramwiseTheme.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .framwisePanel(background: FramwiseTheme.warning.opacity(0.08), radius: 16)
                    .help(persistenceError.localizedDescription)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                if hasImportedClips {
                    Button(action: { showFileImporter = true }) {
                        Label("Import", systemImage: "plus")
                    }
                    .buttonStyle(FramwisePrimaryButtonStyle())
                } else {
                    Button(action: { showFileImporter = true }) {
                        Label("Import", systemImage: "plus")
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: FramwiseTheme.surface,
                        border: FramwiseTheme.line.opacity(0.75),
                        foreground: FramwiseTheme.textMuted
                    ))
                }

                if appState.importSession != nil {
                    Text("\(appState.selectedClipIDs.count) selected")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 999)

                    Button(action: { showExportSheet = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: appState.selectedClipIDs.isEmpty ? FramwiseTheme.surface : FramwiseTheme.accentSoft,
                        border: appState.selectedClipIDs.isEmpty ? FramwiseTheme.line.opacity(0.7) : FramwiseTheme.accent.opacity(0.45),
                        foreground: appState.selectedClipIDs.isEmpty ? FramwiseTheme.textMuted : FramwiseTheme.textPrimary
                    ))
                    .disabled(appState.selectedClipIDs.isEmpty)

                    Button(action: { clearSession() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: FramwiseTheme.surface,
                        border: FramwiseTheme.line.opacity(0.8),
                        foreground: FramwiseTheme.textMuted
                    ))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                FramwiseTheme.backgroundElevated
                FramwiseTheme.subtleHighlight.opacity(0.6)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FramwiseTheme.line.opacity(0.9))
                .frame(height: 1)
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            appState.importResolvedURLs(urls, into: importViewModel)
        case .failure(let error):
            guard importViewModel.recordFileSelectionFailure(error) else { return }
            AppLogger.error(AppLogger.importFlow, "File importer failed", error: error, context: [
                "surface": "toolbar"
            ])
        }
    }

    private func clearSession() {
        importViewModel.cancelImport()
        if appState.clearSession() {
            gridViewModel.resetTransientUIState()
        }
    }
}
#Preview {
    ContentView()
        .environmentObject(AppState())
}
