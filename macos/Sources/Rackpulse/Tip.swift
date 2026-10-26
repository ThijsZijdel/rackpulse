import SwiftUI

private struct Tip: ViewModifier {
    let text: String

    @State private var shown = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        if hovering { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .onTapGesture { shown.toggle() }
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text)
                    .font(.system(size: 12))
                    .frame(width: 250, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
            .accessibilityHint(text)
    }
}

extension View {
    @ViewBuilder
    func tip(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            modifier(Tip(text: text))
        } else {
            self
        }
    }
}

extension View {
    func rolling<Value: Equatable>(_ value: Value) -> some View {
        contentTransition(.numericText()).animation(.snappy(duration: 0.3), value: value)
    }
}
