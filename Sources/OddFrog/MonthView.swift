import SwiftUI
import OddFrogCore

struct MonthView: View {
    let grid: MonthGrid

    var body: some View {
        let weeks = self.weeks
        Grid {
            GridRow {
                ForEach(grid.weekdays.indices, id: \.self) { index in
                    Text(grid.weekdays[index])
                        .font(.headline)
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

    private var weeks: [[MonthGrid.Day]] {
        stride(from: 0, to: grid.days.count, by: grid.weekdays.count).map {
            Array(grid.days[$0..<min($0 + grid.weekdays.count, grid.days.count)])
        }
    }

    @ViewBuilder
    private func dayCell(_ day: MonthGrid.Day) -> some View {
        Text(day.number)
            .font(.title)
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foreground(for: day))
            .bold(day.isToday && day.inMonth)
            .accessibilityLabel(day.isToday ? "Today, " + day.label : day.label)
    }

    private func foreground(for day: MonthGrid.Day) -> AnyShapeStyle {
        if day.isToday && day.inMonth { return AnyShapeStyle(.tint) }
        return day.inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
    }
}
