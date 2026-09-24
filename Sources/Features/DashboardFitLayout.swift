import Foundation

/// Fixed minimum reading size; paginate instead of squeezing text or building
/// invisible cards. No timers and no measurement feedback loop.
struct DashboardFitLayout {
    let columns: Int
    let capacity: Int
    let pageCount: Int
    let cardHeight: CGFloat
    var contentScale: CGFloat { min(1.5, max(1, cardHeight / 340)) }
    init(size: CGSize, count: Int, compact: Bool = false) {
        let width = max(1, size.width), height = max(1, size.height - 36)
        if compact {
            columns = 1
            cardHeight = min(136, height)
            capacity = max(1, Int((height + 12) / (cardHeight + 12)))
            pageCount = max(1, (count + capacity - 1) / capacity)
            return
        }
        // A wide portrait monitor still needs a vertical reading order.
        let portrait = size.height > size.width
        columns = width >= 1400 && !portrait ? 4 : width >= 508 ? 2 : 1
        let rows = max(1, min(max(1, (count + columns - 1) / columns), Int((height + 12) / 256)))
        capacity = columns * rows
        pageCount = max(1, (count + capacity - 1) / capacity)
        // More height used to stretch sparse cards into large empty surfaces.
        cardHeight = min(340, max(1, (height - CGFloat(rows - 1) * 12) / CGFloat(rows)))
    }
    func range(page: Int, count: Int) -> Range<Int> {
        let start = min(max(0, page) * capacity, max(0, count))
        return start..<min(count, start + capacity)
    }
}
