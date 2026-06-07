import WidgetKit
import SwiftUI

// Two widgets, both opening the Today screen on tap:
//   • TodayCountWidget  (small / "4 app slots")  — the completed/total count.
//   • TodayListWidget   (medium / "8 app slots") — the day's outstanding tasks + count.
// When the day is complete both say "All done" but still show the count. The data is
// the snapshot the app publishes to the App Group (see WidgetShared).

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: WidgetSnapshot(
            dayStart: Date(), completed: 1, total: 3, isComplete: false,
            outstandingTitles: ["Exercise", "Journal"]))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), snapshot: WidgetShared.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), snapshot: WidgetShared.load() ?? .empty)
        // The app pokes WidgetCenter on every change; this fallback reload at the next
        // 00:01 covers the day rollover even if the app isn't launched.
        let nextMidnight = Calendar.current.nextDate(
            after: Date(), matching: DateComponents(hour: 0, minute: 1),
            matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

// MARK: - Shared bits

private let completeGreen = Color(red: 0.18, green: 0.62, blue: 0.32)

/// "completed/total" — always shown (even when the day is complete). [owner]
private struct CountText: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 40
    var body: some View {
        Text("\(completed)/\(total)")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

// MARK: - Small ("4 app slots"): the count

struct SmallTodayView: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        VStack(spacing: 4) {
            Text("Today")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            CountText(completed: snapshot.completed, total: snapshot.total)
            if snapshot.isComplete {
                Text("All done").font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(completeGreen)
            } else {
                Text("\(max(0, snapshot.total - snapshot.completed)) left")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Medium ("8 app slots"): outstanding list + count

struct MediumTodayView: View {
    let snapshot: WidgetSnapshot
    private let maxRows = 5

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                CountText(completed: snapshot.completed, total: snapshot.total, size: 30)
                if snapshot.isComplete {
                    Text("All done").font(.caption).fontWeight(.semibold).foregroundStyle(completeGreen)
                }
            }
            .frame(width: 90, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if snapshot.outstandingTitles.isEmpty {
                    Text("All done")
                        .font(.headline).foregroundStyle(completeGreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ForEach(Array(snapshot.outstandingTitles.prefix(maxRows).enumerated()), id: \.offset) { _, title in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(.secondary)
                            Text(title).lineLimit(1)
                        }
                        .font(.subheadline)
                    }
                    if snapshot.outstandingTitles.count > maxRows {
                        Text("+\(snapshot.outstandingTitles.count - maxRows) more")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Widget definitions

struct TodayCountWidget: Widget {
    let kind = "TodayCountWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            SmallTodayView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
                .widgetURL(WidgetShared.todayURL)
        }
        .configurationDisplayName("Today Count")
        .description("How many of today's tasks are done.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayListWidget: Widget {
    let kind = "TodayListWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            MediumTodayView(snapshot: entry.snapshot)
                .containerBackground(.background, for: .widget)
                .widgetURL(WidgetShared.todayURL)
        }
        .configurationDisplayName("Today Tasks")
        .description("Today's outstanding tasks and how many are done.")
        .supportedFamilies([.systemMedium])
    }
}
