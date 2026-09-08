import Charts
import SwiftUI

extension View {
    /// Drag-to-scrub over a date-indexed chart: maps the touch x-position back
    /// to a date, selects the nearest data point, and clears on release.
    ///
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
