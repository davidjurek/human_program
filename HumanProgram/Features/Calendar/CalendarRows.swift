import SwiftUI
import EventKit
import DSKit

// MARK: - Shared EKEvent display helpers [#125]

extension EKEvent {
    /// The calendar's color for drawing this event (bar, chip, block).
    var displayColor: Color { Color(cgColor: calendar.cgColor) }
    /// Title to show, with one consistent fallback for untitled events.
    var displayTitle: String { (title?.isEmpty == false) ? title! : "(No title)" }
}

// MARK: - Month day cell

struct MonthDayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let hasEvents: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 30, height: 30)
                    } else if isToday {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 30, height: 30)
                    }
                    DSText("\(Calendar.current.component(.day, from: day))")
                        .dsTextStyle(.body,
                            isSelected ? .white :
                            isToday ? Color.accentColor :
                            Color.primary
                        )
                }
                if hasEvents {
                    Circle()
                        .fill(isSelected ? .white : Color.accentColor)
                        .frame(width: 5, height: 5)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .a11yTapBorder(Rectangle())
    }
}

// MARK: - Event row (agenda / day list)

struct EventRowView: View {
    let event: EKEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(event.displayColor)
                    .frame(width: 3)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    DSText(event.displayTitle)
                        .dsTextStyle(.body)
                        .lineLimit(1)
                    if !event.isAllDay {
                        DSText("\(clockString(date: event.startDate)) – \(clockString(date: event.endDate))")
                            .dsTextStyle(.caption1)
                    } else {
                        DSText("All day")
                            .dsTextStyle(.caption1)
                    }
                }

                Spacer()

                DSImageView(systemName: "chevron.right", size: .font(.caption1), tint: .color(.secondary))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .a11yTapBorder(Rectangle())
    }
}
