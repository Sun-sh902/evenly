import SwiftUI

struct Avatar: View {
    let name: String
    let colorIndex: Int
    var size: CGFloat = 34

    var body: some View {
        let c = Palette.member(colorIndex)
        Text(Self.initials(name))
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(c)
            .frame(width: size, height: size)
            .background(c.opacity(0.18), in: Circle())
            .overlay(Circle().strokeBorder(c.opacity(0.3)))
            .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        guard let first = parts.first else { return "?" }
        let second = parts.count > 1 ? parts.last!.prefix(1) : first.dropFirst().prefix(1)
        return (first.prefix(1) + second).uppercased()
    }
}

struct CategoryIcon: View {
    let category: String
    var size: CGFloat = 42

    var body: some View {
        let style = CategoryStyle.of(category)
        Image(systemName: style.symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(style.color)
            .frame(width: size, height: size)
            .background(style.color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Wrapping row layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Selectable person chip used for "paid by" and identity pickers.
struct PersonChip: View {
    let name: String
    let colorIndex: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Avatar(name: name, colorIndex: colorIndex, size: 30)
                Text(name).font(.system(size: 15, weight: .medium)).lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 14)
            .frame(height: 40)
            .background(selected ? Color.fieldBackground : Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.ink : Color.line, lineWidth: selected ? 1.5 : 1))
            .foregroundStyle(Color.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small transient banner shown at the bottom of a screen.
struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brand)
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ink, in: Capsule())
        .foregroundStyle(Color.paper)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Shows `text` as a toast for a few seconds, then clears it.
    func toast(_ text: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let value = text.wrappedValue {
                ToastView(text: value)
                    .padding(.bottom, 96)
                    .task(id: value) {
                        try? await Task.sleep(for: .seconds(2.6))
                        withAnimation(.easeOut) { text.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: text.wrappedValue)
    }
}

/// UIKit share sheet for files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
