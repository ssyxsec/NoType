import AppKit
import SwiftUI

private struct LiquidSurface: ViewModifier {
    let capsule: Bool
    let clear: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Palette.card, in: RoundedRectangle(cornerRadius: capsule ? 24 : 12))
        } else if #available(macOS 26.0, *) {
            if capsule { content.glassEffect(clear ? .clear : .regular, in: .capsule) }
            else { content.glassEffect(clear ? .clear : .regular, in: .rect(cornerRadius: 12)) }
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: capsule ? 24 : 12))
        }
    }
}

struct GlassActionStyle: ButtonStyle {
    var prominent = false
    var accent: Color = Palette.green
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, prominent: prominent, accent: accent, enabled: enabled)
    }
    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let accent: Color
        let enabled: Bool
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.38)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
        }
        @ViewBuilder private var label: some View {
            if #available(macOS 26.0, *), !reduceTransparency {
                configuration.label.font(.system(size: 12, weight: .medium))
                    .foregroundStyle(prominent ? accent : Palette.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.clear.tint(prominent ? accent.opacity(0.12) : .clear).interactive(), in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0.5 : 0.32), lineWidth: 0.5))
            } else {
                configuration.label.font(.system(size: 12, weight: .medium))
                    .foregroundStyle(prominent ? accent : Palette.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(prominent ? accent.opacity(0.12) : Palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.7))
            }
        }
    }
}

extension View {
    func liquidSurface(capsule: Bool = false, clear: Bool = false) -> some View { modifier(LiquidSurface(capsule: capsule, clear: clear)) }
    func nativeCard(radius: CGFloat = 16) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: [Palette.card.opacity(0.65), Palette.sidebar.opacity(0.36)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(colors: [.white.opacity(0.65), Palette.line], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
        }
    }
    func nativeGlassButton(prominent: Bool = false) -> some View { buttonStyle(GlassActionStyle(prominent: prominent)) }
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}


struct GlacierTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
            .background(Palette.sidebar.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, lineWidth: 0.6))
            .foregroundStyle(Palette.ink)
    }
}

/// Keep the titlebar and the custom content in one visual plane.
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) { view.configure() }
    final class ChromeView: NSView {
        private weak var configuredWindow: NSWindow?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window, configuredWindow !== window else { return }
            configuredWindow = window
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar?.showsBaselineSeparator = false
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Palette.canvas)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
