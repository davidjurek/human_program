import SwiftUI
import DSKit

/// One item placed on the day timeline. `isCalendar` decides the lane:
/// schedule blocks go in the left lane, Apple Calendar events in the right lane.
struct TimelineItem: Identifiable {
    let id: String
    let title: String
    let startMin: Int
    let endMin: Int
    let isCalendar: Bool
}

// The Daily "Schedule" square on the Today screen. It is exactly as tall as it is
// wide (a square), with a left time column (00:00 … 24:00 in 3-hour steps), two
// lanes of blocks (schedule on the left, calendar on the right — distinguished by
// position, no colored fills, no divider line), and item labels in the open space
// to the right. When viewing today, a live red "now" line spans the full width
// with a time pill over the time column.
struct DailyTimeline: View {
    let items: [TimelineItem]
    let showNow: Bool
    let now: Date

    private let timeColW: CGFloat = 44
    private let laneW: CGFloat = 20
    private let laneGap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let S = geo.size.width        // square: height == width
            content(S: S)
                .frame(width: S, height: S)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func content(S: CGFloat) -> some View {
        let orangeX = timeColW
        let greenX = timeColW + laneW + laneGap
        let labelX = greenX + laneW + 10
        let labelW = max(40, S - labelX)
        let placed = placedLabels(S: S)

        ZStack(alignment: .topLeading) {
            // Hour grid lines + 3-hour labels.
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { h in
                let y = CGFloat(h) / 24 * S
                Rectangle().fill(Color.primary.opacity(0.08))
                    .frame(width: S - timeColW, height: 1)
                    .offset(x: timeColW, y: min(y, S - 1))
                Text(String(format: "%02d:00", h))
                    .font(appFont(11)).foregroundStyle(.secondary)
                    .offset(x: 0, y: min(max(0, y - 6), S - 12))
            }

            // Schedule lane (left) + calendar lane (right). No fills/colors — the
            // lane (x position) is the only distinction.
            ForEach(items) { it in
                let top = yFor(it.startMin, S: S)
                let h = max(3, yFor(it.endMin, S: S) - top)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: laneW, height: h)
                    .offset(x: it.isCalendar ? greenX : orangeX, y: top)
            }

            // Item labels in the open space to the right, top-aligned to each
            // block, stacked so they don't collide.
            ForEach(placed, id: \.item.id) { entry in
                Text("\(entry.item.title), \(hhmm(entry.item.startMin))–\(hhmm(entry.item.endMin))")
                    .font(appFont(10)).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: labelW, alignment: .leading)
                    .offset(x: labelX, y: entry.y)
            }

            // Live "now" line: pill over the time column + full-width red line.
            if showNow {
                let y = yFor(currentMinute, S: S)
                Rectangle().fill(Color.red).frame(width: S, height: 1)
                    .offset(x: 0, y: y)
                Text(hhmm(currentMinute))
                    .font(appFont(11, bold: true)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 0, y: min(max(0, y - 10), S - 20))
            }
        }
    }

    /// Top-aligned label y per item, pushed down to avoid overlapping the prior.
    private func placedLabels(S: CGFloat) -> [(item: TimelineItem, y: CGFloat)] {
        let labelH: CGFloat = 14
        var result: [(item: TimelineItem, y: CGFloat)] = []
        var lastBottom: CGFloat = -labelH
        for it in items.sorted(by: { $0.startMin < $1.startMin }) {
            var y = yFor(it.startMin, S: S)
            if y < lastBottom { y = lastBottom }
            y = min(y, S - labelH)
            result.append((it, y))
            lastBottom = y + labelH
        }
        return result
    }

    private func yFor(_ minute: Int, S: CGFloat) -> CGFloat {
        CGFloat(min(max(minute, 0), 1440)) / 1440 * S
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
