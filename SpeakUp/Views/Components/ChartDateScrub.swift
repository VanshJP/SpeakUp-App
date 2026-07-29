import Charts
import SwiftUI

extension View {
    /// Drag-to-scrub over a date-indexed chart: maps the touch x-position back
    /// to a date, selects the nearest data point, and clears on release.
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
    ///   - selection: index of the scrubbed item; nil when not scrubbing.
    ///   - date: each item's x-axis date. A closure rather than a `KeyPath`
    ///     because every chart here plots an array of labeled tuples, and
    ///     Swift has no key paths into tuple elements.
    func chartDateScrub<Item>(
        over items: [Item],
        selection: Binding<Int?>,
        date: @escaping (Item) -> Date
    ) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let relativeX = value.location.x - geometry[plotFrame].origin.x
                                guard let target: Date = proxy.value(atX: relativeX) else { return }

                                let nearest = items.indices.min {
                                    abs(date(items[$0]).timeIntervalSince(target))
                                        < abs(date(items[$1]).timeIntervalSince(target))
                                }

                                guard let nearest, selection.wrappedValue != nearest else { return }
                                selection.wrappedValue = nearest
                                Haptics.selection()
                            }
                            .onEnded { _ in
                                selection.wrappedValue = nil
                            }
                    )
            }
        }
    }
}
