import SwiftUI

/// A segmented control that moves like the macOS 26 system one (Photos' Years / Months / All Photos):
/// a soft pill that lifts and stretches as it glides to the new segment, then settles,
/// while the newly selected label swells slightly as if seen through the bubble.
///
/// Custom rather than `Picker(.segmented)` because the system control can't fit this popover:
/// it shows icons only for labelled segments and truncates "Moderate" at this width.
/// The pill is drawn without `.glassEffect`: glass ignores opacity, so a glass lens can't fade out.
struct LiquidSegmented<Item: Hashable & Identifiable, Content: View>: View {
    let items: [Item]
    let selection: Item?
    var height: CGFloat = 30
    let onSelect: (Item) -> Void
    @ViewBuilder let label: (Item, Bool) -> Content
    /// Lets a segment ask for a fixed width (e.g. unselected modes are icon-only).
    var widthFor: (Item, Bool) -> CGFloat? = { _, _ in nil }
    /// Size segments to their labels and share the leftover width evenly, so the gaps between
    /// labels match ("Moderate" no longer crowds its neighbours while "Mild" floats).
    var fitToLabels = false

    @Namespace private var space
    @StateObject private var hover = HoverState<Item>()

    var body: some View {
        Group {
            if fitToLabels {
                EvenGapsLayout { segments }
            } else {
                HStack(spacing: 0) { segments }
            }
        }
        .background { if let selection { pill(following: selection) } }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: selection)
        .animation(.easeOut(duration: 0.15), value: hover.item)
    }

    private var segments: some View {
        ForEach(items) { item in
                let selected = item == selection
                Button {
                    onSelect(item)
                } label: {
                    label(item, selected)
                        .phaseAnimator(BubblePhase.allCases, trigger: selection) { content, phase in
                            content.scaleEffect(selected && phase == .lifted ? 1.12 : 1)
                        } animation: { $0.animation }
                        .frame(maxWidth: widthFor(item, selected) ?? .infinity, minHeight: height)
                        .padding(.horizontal, fitToLabels ? 8 : 4)
                        .background {
                            ZStack {
                                if hover.item == item && !selected {
                                    Capsule().fill(Color.primary.opacity(0.06))
                                }
                                // Where the pill should sit for this segment.
                                Capsule().fill(.clear).matchedGeometryEffect(id: item, in: space)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hover.item = item } else if hover.item == item { hover.item = nil }
                }
        }
    }

    /// A single persistent pill (so its bubble animation runs on every change) that tracks the
    /// selected segment's frame.
    private func pill(following item: Item) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.16))
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .phaseAnimator(BubblePhase.allCases, trigger: selection) { pill, phase in
                pill
                    .scaleEffect(phase == .lifted ? CGSize(width: 1.08, height: 1.3) : CGSize(width: 1, height: 1))
                    .brightness(phase == .lifted ? 0.1 : 0)
                    .shadow(color: .black.opacity(phase == .lifted ? 0.32 : 0.15),
                            radius: phase == .lifted ? 7 : 2, y: phase == .lifted ? 3 : 1)
            } animation: { $0.animation }
            .matchedGeometryEffect(id: item, in: space, isSource: false)
            .allowsHitTesting(false)
    }
}

/// `settled` looks like `resting`, so the pill ends at rest whether the animator stops on the
/// last phase or returns to the first.
/// Lays children out in a row at their ideal widths plus an equal share of the spare width.
/// If the labels don't fit, every segment shrinks by the same proportion instead.
private struct EvenGapsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? ideals.reduce(0) { $0 + $1.width },
                      height: ideals.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let total = ideals.reduce(0, +)
        let extra = (bounds.width - total) / CGFloat(subviews.count)
        var x = bounds.minX
        for (subview, ideal) in zip(subviews, ideals) {
            let width = extra >= 0 ? ideal + extra : ideal * bounds.width / total
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}

private enum BubblePhase: CaseIterable {
    case resting, lifted, settled

    var animation: Animation {
        switch self {
        case .lifted: .easeOut(duration: 0.13)
        case .settled, .resting: .spring(response: 0.38, dampingFraction: 0.62)
        }
    }
}

private final class HoverState<Item: Hashable>: ObservableObject {
    @Published var item: Item?
}
