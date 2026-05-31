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
    /// Schedule-block colour (left lane). nil → gray fallback. Calendar lane
    /// ignores this and always uses the fixed light blue.
    var color: Color? = nil
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

    private let timeColW: CGFloat = 52   // fits "00:00" in the pixel font
    private let laneW: CGFloat = 36      // [#1] widened 1.8× (was 20)
    private let laneGap: CGFloat = 7.2   // [#1] widened 1.8× (was 4)
    private let laneLeadingGap: CGFloat = 24  // tripled: gap between time column and lanes/lines

    /// Fixed light blue for the calendar (right) lane. [#15]
    private static let calendarBlue = Color(red: 0.46, green: 0.67, blue: 0.96).opacity(0.55)

    var body: some View {
        // A clear square (height == width) reserves the layout height; the
        // GeometryReader overlay then lays the timeline out inside it.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    content(S: geo.size.width)
                }
            }
    }

    @ViewBuilder
    private func content(S: CGFloat) -> some View {
        let orangeX = timeColW + laneLeadingGap
        let greenX = orangeX + laneW + laneGap
        let labelX = greenX + laneW + 10
        let labelW = max(40, S - labelX)
        let placed = placedLabels(S: S)

        ZStack(alignment: .topLeading) {
            let laneSpan = laneW * 2 + laneGap

            // Schedule lane (left) + calendar lane (right). Calendar blocks are a
            // fixed light blue; schedule blocks use their assigned colour (gray
            // fallback). Drawn BEFORE the grid lines so the hour lines sit on top.
            ForEach(items) { it in
                let top = yFor(it.startMin, S: S)
                let h = max(3, yFor(it.endMin, S: S) - top)
                RoundedRectangle(cornerRadius: 4)
                    .fill(it.isCalendar ? Self.calendarBlue : (it.color ?? Color.primary.opacity(0.50)))
                    .frame(width: laneW, height: h)
                    .offset(x: it.isCalendar ? greenX : orangeX, y: top)
            }

            // Hour grid lines (span only the two lanes) + 3-hour labels. Drawn on
            // top of the blocks so the hour lines stay visible across them.
            ForEach(Array(stride(from: 0, through: 24, by: 3)), id: \.self) { h in
                let y = CGFloat(h) / 24 * S
                // Label is framed to a fixed height and CENTERED on y so it lines
                // up with its hour line (both centred on the same y). The line
                // starts at orangeX, leaving the laneLeadingGap after the labels.
                // Label centred on its line. No end-clamping (clamping the first
                // and last labels was compressing the top/bottom gaps and making
                // the spacing look uneven). The -7 centres the pixel-font digits
                // (which sit high in the box) on the line at y.
                Text(String(format: "%02d:00", h))
                    .font(appFont(13)).foregroundStyle(.secondary)
                    .fixedSize()
                    .frame(height: 16)
                    .offset(x: 0, y: y - 7)
                Rectangle().fill(Color.primary.opacity(0.18))
                    .frame(width: laneSpan, height: 1)
                    .offset(x: orangeX, y: y)
            }

            // Item labels in the open space to the right, top-aligned to each
            // block, stacked so they don't collide.
            ForEach(placed, id: \.item.id) { entry in
                Text("\(entry.item.title), \(hhmm(entry.item.startMin))–\(hhmm(entry.item.endMin))")
                    .font(appFont(13)).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: labelW, alignment: .leading)
                    .offset(x: labelX, y: entry.y)
            }

            // Live "now" line: pill over the time column + full-width red line.
            if showNow {
                let y = yFor(currentMinute, S: S)
                // Stop the line at the right edge of the block column (time column +
                // both lanes), not the full square width.
                Rectangle().fill(Color.red).frame(width: orangeX + laneSpan, height: 1)
                    .offset(x: 0, y: y)
                Text(hhmm(currentMinute))
                    .font(appFont(13, bold: true)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                    // Shift left by the capsule's horizontal padding (6) so the pill's
                    // time digits line up with the hour-label digits; the rounded left
                    // edge is allowed to spill into the left margin.
                    .offset(x: -6, y: min(max(0, y - 10), S - 20))
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
