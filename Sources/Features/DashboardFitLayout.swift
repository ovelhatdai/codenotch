import Foundation

/// Fixed minimum reading size; paginate instead of squeezing text or building
/// invisible cards. No timers and no measurement feedback loop.
struct DashboardFitLayout {
    let columns: Int
    let capacity: Int
    let pageCount: Int
    let cardHeight: CGFloat
    var contentScale: CGFloat { min(1.5, max(1, cardHeight / 340)) }
    init(size: CGSize, count: Int) {
        let width = max(1, size.width), height = max(1, size.height - 36)
        // A wide portrait monitor still needs a vertical reading order.
        // Width alone used to pack everything into two short rows at the top.
        let portrait = size.height > size.width
        columns = width >= 1028 && !portrait ? 4 : width >= 508 ? 2 : 1
        let rows = max(1, min(max(1, (count + columns - 1) / columns), Int((height + 12) / 256)))
        capacity = columns * rows
        pageCount = max(1, (count + capacity - 1) / capacity)
        cardHeight = min(portrait ? 600 : 340, max(1, (height - CGFloat(rows - 1) * 12) / CGFloat(rows)))
    }
    func range(page: Int, count: Int) -> Range<Int> {
        let start = min(max(0, page) * capacity, max(0, count))
        return start..<min(count, start + capacity)
    }
}
