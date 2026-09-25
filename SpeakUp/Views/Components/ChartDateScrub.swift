import Charts
import SwiftUI

extension View {
    /// Drag-to-scrub over a date-indexed chart: maps the touch x-position back
    /// to a date and selects the nearest data point.
    ///
    /// The selection stays pinned when the finger lifts, so the readout under
    /// the plot can hold an action (Score and Pace open the take there); a tap
    /// on the pinned point clears it. It used to clear on release, which left
    /// the readout nothing a finger could reach. A change in the plotted
    /// collection (another window, a new take) clears it too, since the index
    /// would point at a different item.
    ///
    /// This block was copy-pasted four times in `ProgressChartsView` (score,
    /// fillers, pace, activity), differing only in the collection and its date
    /// keypath. Three copies guarded the haptic behind an index change; the
    /// score chart's did not, so scrubbing it fired a selection haptic on every
    /// gesture callback rather than once per data point. Collapsing them fixes
    /// that by construction.
    ///
    /// - Parameters:
    ///   - items: the same collection the chart plots, in plotted order.
    ///   - selection: index of the pinned item; nil when nothing is pinned.
    ///   - date: each item's x-axis date.
    func chartDateScrub<Item>(
        over items: [Item],
        selection: Binding<Int?>,
        date: @escaping (Item) -> Date
    ) -> some View {
        modifier(ChartDateScrub(items: items, selection: selection, date: date))
    }
}

private struct ChartDateScrub<Item>: ViewModifier {
    let items: [Item]
    @Binding var selection: Int?
    let date: (Item) -> Date

    /// Whether a touch is under way, and what was pinned when it began: a tap
    /// that lands on the pinned point again unpins instead of re-selecting.
    @State private var isTouching = false
    @State private var pinnedAtTouchDown: Int?

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isTouching {
                                        isTouching = true
                                        pinnedAtTouchDown = selection
                                    }

                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let relativeX = value.location.x - geometry[plotFrame].origin.x
                                    guard let target: Date = proxy.value(atX: relativeX) else { return }

                                    let nearest = items.indices.min {
                                        abs(date(items[$0]).timeIntervalSince(target))
                                            < abs(date(items[$1]).timeIntervalSince(target))
                                    }

                                    guard let nearest, selection != nearest else { return }
                                    selection = nearest
                                    Haptics.selection()
                                }
                                .onEnded { value in
                                    isTouching = false
                                    let isTap = abs(value.translation.width) < 8
                                        && abs(value.translation.height) < 8
                                    if isTap, let pinned = pinnedAtTouchDown, pinned == selection {
                                        selection = nil
                                    }
                                }
                        )
                }
            }
            .onChange(of: items.count) {
                selection = nil
            }
    }
}
