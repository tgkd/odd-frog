import SwiftUI
import OddFrogCore

struct CalendarView: View {
    let model: CalendarWindowModel
    let open: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            switch model.browser.mode {
            case .month:
                let grid = model.browser.monthGrid
                Text(grid.heading)
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                MonthView(grid: grid)
            case .year:
                let grid = model.browser.yearGrid
                Text(grid.heading)
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                YearView(grid: grid, open: open)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
