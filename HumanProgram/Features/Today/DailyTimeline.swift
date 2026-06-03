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
    /// True → draw the coloured block but NO text label. Used for the AM half of
    /// an overnight-wrapping block so the wrap shows ONE label, not two.
    var suppressLabel: Bool = false
    /// Overrides the end-minute shown in the LABEL only (not the block geometry).
    /// Lets the PM half of an overnight block read its true morning end (e.g.
    /// "21:30–05:30") instead of the midnight cut used to draw the segment.
    var labelEndMin: Int? = nil
}

// The Daily "Schedule" square on the Today screen. A left time column (honoring
// the 12h/24h setting), two lanes of blocks (schedule on the left, calendar on
// the right), and item labels to the right. When viewing today a live red "now"
// line spans the block column with a centred time pill over the time column.
//
// PINCH-ZOOM: the viewport is a fixed square; pinching vertically zooms the day
// in (down to a 4-hour window) and out (the full 00:00–24:00). The grid gains
// finer lines as it zooms — 3-hour lines, then hourly, then half-hourly — and
// every visible line is labelled. The content scrolls vertically when taller
// than the viewport. Zoom is in-memory only (resets when the screen is left;
// survives backgrounding). [owner]
struct DailyTimeline: View {
    let items: [TimelineItem]
    let showNow: Bool
    let now: Date
    /// Called with the tapped calendar event's id. Schedule blocks are inert.
    var onTapCalendar: (String) -> Void = { _ in }

    private let timeColW = TimelineMetrics.gutterW
    private let laneW: CGFloat = 25
    private let laneGap: CGFloat = 0
    private let laneLeadingGap = TimelineMetrics.gutterGap

    /// Fixed light blue for the calendar (right) lane (shared design token). [#31]
    private static let calendarBlue = appCalendarLaneBlue.opacity(0.55)

    /// zoom == 1 → whole day fills the square (00:00–24:00). zoom == maxZoom → a
    /// 4-hour window. (contentHeight = viewport * zoom.)
    private let maxZoom: CGFloat = 6
    @State private var zoom: CGFloat = 1
    @State private var scrollY: CGFloat = 0      // content top offset, ≤ 0
    @State private var pinchBaseZoom: CGFloat = 1
    @State private var pinchBaseScroll: CGFloat = 0
    @State private var pinching = false
    @State private var dragBaseScroll: CGFloat = 0
    @State private var dragging = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geo in
                    let W = geo.size.width
                    let viewportH = geo.size.height
                    let contentH = viewportH * zoom
                    content(W: W, contentH: contentH)
                        .frame(width: W, height: contentH, alignment: .topLeading)
                        .offset(y: scrollY)
                        .frame(width: W, height: viewportH, alignment: .topLeading)
                        .clipped()
                        .contentShape(Rectangle())
                        .highPriorityGesture(dragGesture(viewportH: viewportH),
                                             including: zoom > 1 ? .all : .subviews)
                        .simultaneousGesture(magnifyGesture(viewportH: viewportH))
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(W: CGFloat, contentH: CGFloat) -> some View {
        let orangeX = timeColW + laneLeadingGap
        let greenX = orangeX + laneW + laneGap
        let labelX = greenX + laneW + 10
        let labelW = max(40, W - labelX)
        let laneSpan = laneW * 2 + laneGap
        let placed = placedLabels(contentH: contentH)
        let marks = gridMarks()

        ZStack(alignment: .topLeading) {
            // Blocks (drawn before the grid so the hour lines sit on top). Calendar
            // blocks are tappable (→ event card); schedule blocks are inert.
            ForEach(items) { it in
                let top = yFor(it.startMin, contentH: contentH)
                let h = max(3, yFor(it.endMin, contentH: contentH) - top)
                RoundedRectangle(cornerRadius: 4)
                    .fill(it.isCalendar ? Self.calendarBlue : (it.color ?? Color.primary.opacity(0.50)))
                    .frame(width: laneW, height: h)
                    .contentShape(Rectangle())
                    .allowsHitTesting(it.isCalendar)
                    .onTapGesture { if it.isCalendar { onTapCalendar(it.id) } }
                    .offset(x: it.isCalendar ? greenX : orangeX, y: top)
            }

            // Grid lines + labels. The set of lines (3-hour / hourly / half-hourly)
            // and their weight come from the current zoom; every line is labelled.
            ForEach(marks, id: \.minute) { mark in
                let y = yFor(mark.minute, contentH: contentH)
                lineFor(mark)
                    .frame(width: laneSpan, height: mark.lineWidth)
                    .offset(x: orangeX, y: y - mark.lineWidth / 2)
                Text(clockString(minutesOfDay: mark.minute))
                    .font(appFont(13)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: timeColW, height: 16, alignment: .center)
                    .offset(x: 0, y: y - 8)
            }

            // Item labels to the right, top-aligned per block, stacked to avoid
            // collisions. "Title period–period" (no comma), honoring 12h/24h.
            ForEach(placed, id: \.item.id) { entry in
                Text("\(entry.item.title) \(clockString(minutesOfDay: entry.item.startMin))–\(clockString(minutesOfDay: entry.item.labelEndMin ?? entry.item.endMin))")
                    .font(appFont(13)).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: labelW, alignment: .leading)
                    .offset(x: labelX, y: entry.y)
            }

            // Live "now" line: centred pill over the time column + red line across
            // the block column.
            if showNow {
                let y = yFor(currentMinute, contentH: contentH)
                let cy = min(max(y, TimelineMetrics.pillH / 2), contentH - TimelineMetrics.pillH / 2)
                Rectangle().fill(Color.red).frame(width: orangeX + laneSpan, height: 1)
                    .offset(x: 0, y: cy)
                NowPill(minutesOfDay: currentMinute)
                    .frame(width: timeColW, alignment: .center)
                    .offset(x: 0, y: cy - TimelineMetrics.pillH / 2)
            }
        }
    }

    // MARK: - Grid marks

    private struct GridMark {
        let minute: Int
        let tier: Int          // 0 = 3-hour, 1 = hourly, 2 = half-hourly
        let lineWidth: CGFloat
    }

    /// The lines to draw at the current zoom. Below 3× only 3-hour lines; from 3×
    /// hourly lines appear (3-hour lines thicken); from 6× half-hourly lines
    /// appear (dashed), with the 3-hour lines thickest.
    private func gridMarks() -> [GridMark] {
        let step: Int = zoom >= maxZoom ? 30 : (zoom >= 3 ? 60 : 180)
        return stride(from: 0, through: 1440, by: step).map { m in
            let tier = (m % 180 == 0) ? 0 : (m % 60 == 0 ? 1 : 2)
            let width: CGFloat
            switch tier {
            case 0: width = zoom >= maxZoom ? 2 : (zoom >= 3 ? 1.5 : 1)
            case 1: width = 1
            default: width = 1
            }
            return GridMark(minute: m, tier: tier, lineWidth: width)
        }
    }

    private func lineFor(_ mark: GridMark) -> some View {
        // Half-hour separators are dotted-dashed; 3-hour/hourly lines are solid.
        let opacity = (mark.tier == 0 && zoom >= 3) ? 0.30 : 0.18
        return HLine().stroke(Color.primary.opacity(opacity),
                              style: StrokeStyle(lineWidth: mark.lineWidth,
                                                 dash: mark.tier == 2 ? [3, 3] : []))
    }

    // MARK: - Labels

    private func placedLabels(contentH: CGFloat) -> [(item: TimelineItem, y: CGFloat)] {
        let labelH: CGFloat = 16
        var result: [(item: TimelineItem, y: CGFloat)] = []
        var lastBottom: CGFloat = -labelH
        for it in items.sorted(by: { $0.startMin < $1.startMin }) where !it.suppressLabel {
            var y = yFor(it.startMin, contentH: contentH)
            if y < lastBottom { y = lastBottom }
            y = min(y, contentH - labelH)
            result.append((it, y))
            lastBottom = y + labelH
        }
        return result
    }

    private func yFor(_ minute: Int, contentH: CGFloat) -> CGFloat {
        CGFloat(min(max(minute, 0), 1440)) / 1440 * contentH
    }

    private var currentMinute: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// A single horizontal line at the vertical centre of its frame.
    private struct HLine: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }

    // MARK: - Gestures

    private func maxScroll(_ viewportH: CGFloat) -> CGFloat { max(0, viewportH * zoom - viewportH) }

    /// Vertical pinch zoom that keeps the time under the fingers fixed. Damped so
    /// it takes a bit more finger travel — easier to control. [owner]
    private func magnifyGesture(viewportH: CGFloat) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                if !pinching { pinching = true; pinchBaseZoom = zoom; pinchBaseScroll = scrollY }
                let damped = 1 + (value.magnification - 1) * 0.55
                let newZoom = min(max(pinchBaseZoom * damped, 1), maxZoom)
                // Keep the content point under the pinch's start location anchored.
                let focal = value.startLocation.y
                let u = (focal - pinchBaseScroll) / pinchBaseZoom     // base (zoom-1) y
                var newScroll = focal - u * newZoom
                let limit = viewportH * newZoom - viewportH
                newScroll = min(0, max(-(max(0, limit)), newScroll))
                zoom = newZoom
                scrollY = newScroll
            }
            .onEnded { _ in pinching = false }
    }

    /// Vertical scroll of the zoomed-in day. Only active when zoomed (the modifier
    /// masks it out at 1×, so the page itself scrolls instead).
    private func dragGesture(viewportH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if !dragging { dragging = true; dragBaseScroll = scrollY }
                let proposed = dragBaseScroll + value.translation.height
                scrollY = min(0, max(-maxScroll(viewportH), proposed))
            }
            .onEnded { _ in dragging = false }
    }
}
