import AppKit
import SwiftUI
import NoTypeCore

struct ShortcutSettings: View {
    @ObservedObject var state: AppState
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("开始 / 结束录音")
                Spacer()
                Text(state.recordingShortcut.displayName).font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 7).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 6))
                Button("修改快捷键") { state.beginHotkeyCapture(); editing = true }
                Button("恢复默认") { state.hotkeyStatus = ""; _ = state.applyHotkey(.standard) }
            }
            Text("点击修改后，直接按下新的组合键。至少包含 ⌘ Command、⌥ Option 或 ⌃ Control；按 Esc 取消。")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            if !state.hotkeyStatus.isEmpty { Text(state.hotkeyStatus).font(.system(size: 12)).foregroundStyle(Palette.muted) }
        }.disabled(state.isBusy)
            .sheet(isPresented: $editing, onDismiss: { state.endHotkeyCapture() }) { ShortcutEditor(state: state) }
    }
}

private struct ShortcutEditor: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecordingShortcut?
    @State private var validation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设置录音快捷键").font(.system(size: 22, weight: .semibold))
            Text("直接按下组合键，例如 Control + Option + K。录入期间暂停全局录音热键。")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            ShortcutCapture { shortcut in
                draft = shortcut; validation = shortcut.validationError ?? ""; state.hotkeyStatus = ""
            } onCancel: { dismiss() }
                .frame(height: 76)
                .overlay(Text(draft?.displayName ?? "请按下新的快捷键…").font(.system(size: 22, weight: .medium, design: .monospaced)).allowsHitTesting(false))
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.green.opacity(0.4)))
                .accessibilityLabel("快捷键录入区域：\(draft?.displayName ?? "等待按键")")
            Text(validation.isEmpty ? state.hotkeyStatus : validation).font(.system(size: 12)).foregroundStyle(.red).frame(minHeight: 32)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存快捷键") {
                    guard let draft else { return }
                    if state.applyHotkey(draft) { dismiss() }
                }.buttonStyle(GlassActionStyle(prominent: true)).disabled(draft == nil || !validation.isEmpty)
            }
        }.padding(28).frame(width: 450).background(Palette.canvas).foregroundStyle(Palette.ink)
            .onDisappear { state.endHotkeyCapture() }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    let onCapture: (RecordingShortcut) -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView(); view.onCapture = onCapture; view.onCancel = onCancel; return view
    }
    func updateNSView(_ view: CaptureView, context: Context) { view.onCapture = onCapture; view.onCancel = onCancel }
    final class CaptureView: NSView {
        var onCapture: ((RecordingShortcut) -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self) }
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            keyDown(with: event); return true
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onCancel?(); return }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= RecordingShortcut.command }
            if event.modifierFlags.contains(.option) { modifiers |= RecordingShortcut.option }
            if event.modifierFlags.contains(.control) { modifiers |= RecordingShortcut.control }
            if event.modifierFlags.contains(.shift) { modifiers |= RecordingShortcut.shift }
            onCapture?(RecordingShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        }
    }
}
