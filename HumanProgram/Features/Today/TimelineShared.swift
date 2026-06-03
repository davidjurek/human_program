import SwiftUI
import DSKit
import EventKit

/// Identifiable wrapper so a tapped calendar event can drive a `.sheet(item:)`.
struct TimelineTappedEvent: Identifiable {
    let event: EKEvent
    var id: String { event.eventIdentifier ?? ObjectIdentifier(event).debugDescription }
}

/// Shared metrics + the red "now" pill for EVERY timeline gutter — the Today
/// schedule square, the Calendar week view, and the Calendar day view — so the
/// left margin and the now-pill are identical across all three. [owner]
///
/// The gutter is sized for the WIDEST clock label ("12:00 AM" in the 12-hour
/// format), and the pill is a fixed size that does not change between 12h/24h,
/// so the layout never shifts when the time-format setting flips.
enum TimelineMetrics {
    /// Left time-column width. Wide enough for "12:00 AM" in the pixel font; the
    /// same value is used by Today, Calendar week, and Calendar day so all three
    /// left margins line up.
    static let gutterW: CGFloat = 66
    /// Gap between the time column and the content (lines / day columns).
    static let gutterGap: CGFloat = 8
    /// Left inset (screen edge → gutter origin) shared by all three timelines so
    /// their left margins line up. Tuned so the CENTRED pill's left edge sits
    /// right at the content margin (it never pokes left of the Today "Schedule"
    /// header). [owner]
    static let leadingInset: CGFloat = 18
    /// Right inset for the Calendar grids. Moving the gutter against the left
    /// margin frees space on the right; this is the resulting gap to the right of
    /// Saturday (week) / the end of the hour lines (day). Day and Week share it so
    /// their content ends at the same x. [owner]
    static let trailingInset: CGFloat = 16
    /// Fixed now-pill size — identical across 12h/24h and all three views.
    static let pillW: CGFloat = 62
    static let pillH: CGFloat = 20
    /// X (from the gutter origin) of the CENTRED pill's right edge — where the red
    /// now-line starts so it sits attached to the pill. [owner]
    static var pillTrailingEdge: CGFloat { (gutterW + pillW) / 2 }
}

/// The clock label in a timeline gutter, shared by Today, Calendar week, and
/// Calendar day. Defaults to CENTRE-aligned in the gutter (Calendar week/day,
/// matching the centred now-pill). Today passes `.leading` so the labels line up
/// flush under the "Schedule" header. Each screen supplies its own vertical
/// placement. [owner]
struct TimelineGutterLabel: View {
    let minutesOfDay: Int
    var width: CGFloat = TimelineMetrics.gutterW
    var alignment: Alignment = .center
    var body: some View {
        Text(clockString(minutesOfDay: minutesOfDay))
            .font(appFont(13)).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: width, alignment: alignment)
    }
}

/// The red "now" time pill. Fixed size, text CENTER-aligned inside the capsule,
/// and honors the 12h/24h setting through `clockString`. Shared by Today /
/// Calendar week / Calendar day so the shape and size match everywhere. [owner]
struct NowPill: View {
    let minutesOfDay: Int
    /// Capsule width. Defaults to the shared fixed size (Calendar week/day). Today
    /// passes its measured time-column width so the pill exactly spans the column
    /// and shares its centre with the labels. [owner]
    var width: CGFloat = TimelineMetrics.pillW
    var body: some View {
        Text(clockString(minutesOfDay: minutesOfDay))
            .font(appFont(13, bold: true))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(width: width, height: TimelineMetrics.pillH)
            .background(Capsule().fill(Color.red))
    }
}

/// A gutter clock label (left time column), honoring the 12h/24h setting. Used by
/// the Calendar week/day hour rows so they match the Today gutter. [owner]
func timelineGutterLabel(minutesOfDay: Int) -> String {
    clockString(minutesOfDay: minutesOfDay)
}
