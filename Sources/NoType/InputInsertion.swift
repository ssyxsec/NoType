import AppKit
import ApplicationServices
import NoTypeCore

@MainActor
final class InputInsertion {
    private var target: NSRunningApplication?
    private var targetPID: pid_t?
    private var focusedElement: AXUIElement?
    private var selectedRange: CFTypeRef?
    private var previousApplication: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private(set) var failureReason = ""
    var targetName: String? { target?.localizedName }
    var hasTarget: Bool { target != nil }

    init() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor in self?.previousApplication = application }
        }
    }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    func captureTarget() {
        let front = NSWorkspace.shared.frontmostApplication
        let frontmost = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApplication : front
        focusedElement = nil
        selectedRange = nil
        guard let frontmost, !frontmost.isTerminated else {
            target = nil
            targetPID = nil
            return
        }
        target = frontmost
        targetPID = frontmost.processIdentifier
        focusedElement = AXIsProcessTrusted() ? focused(in: frontmost.processIdentifier) : nil
        if let focusedElement {
            AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        }
    }

    /// This is the only method that asks macOS to show the Accessibility prompt.
    @discardableResult
    func requestPermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Call only when the user enabled automatic insertion. False means text was copied instead.
    func insert(text: String) async throws -> Bool {
        failureReason = ""
        guard !text.isEmpty else { return false }
        let board = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = (board.pasteboardItems ?? []).map { item in
            let saved = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
        Self.copy(text)
        let ownChangeCount = board.changeCount
        guard AXIsProcessTrusted() else {
            failureReason = "结果已复制。请在“系统设置 → 隐私与安全性 → 辅助功能”允许 NoType，才能自动输入。"
            return false
        }
        guard let target, let targetPID, !target.isTerminated,
              InsertionPolicy.mayReturnToTarget(frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                               target: targetPID, own: ProcessInfo.processInfo.processIdentifier) else {
            failureReason = "结果已复制。原输入应用不可用或你已切换到其他应用，未自动粘贴。"
            return false
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            guard target.activate(options: []) else { failureReason = "结果已复制，无法返回原输入应用。"; return false }
        }
        try await Task.sleep(nanoseconds: 180_000_000)
        guard board.changeCount == ownChangeCount,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID,
              !target.isTerminated else { failureReason = "结果已复制，输入位置已切换。"; return false }
        let current = focused(in: targetPID)
        if let focusedElement, let current, !CFEqual(focusedElement, current) {
            failureReason = "结果已复制，原输入框的焦点已改变，未自动覆盖。"; return false
        }
        if let current {
            if let selectedRange {
                var currentRange: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXSelectedTextRangeAttribute as CFString, &currentRange) == .success,
                   let currentRange, !CFEqual(selectedRange, currentRange) {
                    failureReason = "结果已复制，原输入框的光标或选区已改变，未自动覆盖。"; return false
                }
            }
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subrole)
            if subrole as? String == kAXSecureTextFieldSubrole {
                failureReason = "结果已复制，不向密码输入框自动输入。"; return false
            }
            // Use real paste events so Electron/web editors also receive their
            // normal input events; AXSelectedText can report success without
            // updating the editor's internal document state.
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { failureReason = "结果已复制，无法发送粘贴按键。"; return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            failureReason = "结果已复制，前台应用已变化。"; return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Delay restoration so the receiving application has time to read the pasteboard.
        // Never replace clipboard content changed by the user or another application.
        try? await Task.sleep(nanoseconds: 900_000_000)
        restore(board, items: savedItems, changeCount: ownChangeCount)
        return true
    }
    private func restore(_ board: NSPasteboard, items: [NSPasteboardItem], changeCount: Int) {
        if board.changeCount == changeCount {
            board.clearContents()
            if !items.isEmpty { board.writeObjects(items) }
        }
    }
    private func focused(in pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
