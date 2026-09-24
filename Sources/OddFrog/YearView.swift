import SwiftUI
import OddFrogCore

struct YearView: View {
    let grid: YearGrid
    let open: (Date) -> Void

    var body: some View {
        ScrollView(.vertical) {
            ViewThatFits(in: .horizontal) {
                columns(4)
                columns(3)
                columns(2)
                columns(1)
            }
        }
    }

    private func columns(_ count: Int) -> some View {
        Grid(alignment: .topLeading) {
            ForEach(chunks(of: count).indices, id: \.self) { row in
                GridRow {
                    ForEach(chunks(of: count)[row], id: \.month) { month in
                        MiniMonthView(grid: month, open: open)
                            .padding([.trailing, .bottom])
                    }
                }
            }
        }
    }

    private func chunks(of count: Int) -> [[MonthGrid]] {
        stride(from: 0, to: grid.months.count, by: count).map {
            Array(grid.months[$0..<min($0 + count, grid.months.count)])
        }
    }
}
