import SwiftUI
import DSKit

// The Daily Schedule hour-timeline on the Today screen. The day's schedule blocks
// (generated from the Settings schedule) are drawn on a 24-hour grid. When viewing
// today, a red "now" bar sits at the current time with a red time pill OVER the
// time column (left), descending as time passes.
struct DailyTimeline: View {
    let blocks: [DailyPageScheduleBlock]
    let showNow: Bool
    let now: Date

    private let hourHeight: CGFloat = 26
    private let leftCol: CGFloat = 50

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Hour grid lines + labels every 3 hours.
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { h in
                HStack(spacing: 8) {
                    Text(String(format: "%02d:00", h % 24))
                        .font(appFont(12)).foregroundStyle(.secondary)
                        .frame(width: leftCol - 8, alignment: .leading)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                }
                .offset(y: CGFloat(h) * hourHeight)
            }

            // Schedule blocks.
            ForEach(blocks) { b in
                blockView(b)
                    .frame(height: max(16, CGFloat(min(duration(b), 1440 - b.startMinuteOfDay)) / 60 * hourHeight))
                    .offset(y: CGFloat(b.startMinuteOfDay) / 60 * hourHeight)
            }

            // Now bar (pill over the time column + red line).
            if showNow {
                HStack(spacing: 0) {
                    Text(hhmm(currentMinute))
                        .font(appFont(11, bold: true)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                    Rectangle().fill(Color.red).frame(height: 1)
                }
                .offset(y: CGFloat(currentMinute) / 60 * hourHeight - 9)
            }
        }
        .frame(height: 24 * hourHeight)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popupGlass(cornerRadius: 16)
    }

    private func blockView(_ b: DailyPageScheduleBlock) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.45)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                DSText(b.title).dsTextStyle(.subheadline).lineLimit(1)
                Text("\(hhmm(b.startMinuteOfDay))–\(hhmm(b.endMinuteOfDay))")
                    .font(appFont(11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, leftCol).padding(.trailing, 8)
    }

    private func duration(_ b: DailyPageScheduleBlock) -> Int {
        let d = ((b.endMinuteOfDay - b.startMinuteOfDay) % 1440 + 1440) % 1440
        return d == 0 ? 60 : d
    }

    private var currentMinute: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func hhmm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
