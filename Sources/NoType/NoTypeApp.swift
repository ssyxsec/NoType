import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct NoTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()
    var body: some Scene {
        Window("NoType", id: "main") {
            MainView(state: state)
                .frame(minWidth: 960, minHeight: 700)
                .onAppear { state.installHotkey() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in state.shutdown() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshInputPermission() }
        }
        .defaultSize(width: 1100, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("导入音频…") { state.importAudio() }.keyboardShortcut("o")
                Button("新建转写") { state.newDraft() }.keyboardShortcut("n")
            }
        }
        MenuBarExtra("NoType", systemImage: state.phase == .recording ? "mic.fill" : "waveform") {
            TrayMenu(state: state)
        }
        Settings {
            ScrollView { PreferencesView(state: state).padding(30).buttonStyle(GlassActionStyle()).tint(Palette.green) }
                .background(Palette.canvas).foregroundStyle(Palette.ink).frame(width: 680, height: 760)
        }
    }
}

struct TrayMenu: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(state.phase.title)
        Button(state.phase == .recording ? "结束录音" : "开始录音  \(state.recordingShortcut.displayName)") { state.toggleRecording() }
            .disabled(state.isBusy && state.phase != .recording)
        if state.phase == .recording { Button("取消录音") { state.cancelRecording() } }
        Divider()
        Button("打开 NoType") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("设置") { state.section = "settings"; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("退出 NoType") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
