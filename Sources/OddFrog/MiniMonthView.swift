import SwiftUI
import OddFrogCore

struct MiniMonthView: View {
    let grid: MonthGrid
    let open: (Date) -> Void

    var body: some View {
        let weeks = self.weeks
        Button(action: { open(grid.month) }) {
            VStack(alignment: .leading) {
                Text(grid.name)
                    .font(.headline)
                Grid {
                    GridRow {
                        ForEach(grid.narrowWeekdays.indices, id: \.self) { index in
                            Text(grid.narrowWeekdays[index])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        GridRow {
                            ForEach(weeks[weekIndex], id: \.date) { day in
                                dayCell(day)
                            }
                        }
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(grid.heading)
        .accessibilityHint("Shows this month")
    }

    private var weeks: [[MonthGrid.Day]] {
        stride(from: 0, to: grid.days.count, by: grid.weekdays.count).map {
            Array(grid.days[$0..<min($0 + grid.weekdays.count, grid.days.count)])
        }
    }

    @ViewBuilder
    private func dayCell(_ day: MonthGrid.Day) -> some View {
        if day.inMonth {
            Text(day.number)
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(day.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .bold(day.isToday)
        } else {
            Text(day.number)
                .font(.body)
                .monospacedDigit()
                .hidden()
        }
    }
}
