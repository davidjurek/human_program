import SwiftUI
import DSKit

// A short tutorial covering how to use Human Program well. Shown once at the end
// of onboarding (full-screen, "Done" enters the app) and available any time from
// Settings → About → Tutorial (pushed page, back button to leave).
struct TutorialView: View {
    enum Mode { case onboarding, reference }
    let mode: Mode
    /// Called when the user finishes in onboarding mode.
    var onDone: () -> Void = {}

    private let lightBlue = Color(red: 0.42, green: 0.69, blue: 0.99)

    var body: some View {
        switch mode {
        case .reference:
            SettingsScreen(centered: true) {
                header
                tipsBody
            }
        case .onboarding:
            ZStack {
                SettingsBackground()
                VStack(spacing: 0) {
                    // Frozen header — stays put while the tips scroll.
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 40)
                        .padding(.bottom, 18)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            tipsBody
                            doneButton
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }

    private var doneButton: some View {
        Button { onDone() } label: {
            Text("Done").font(appFont(20)).foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(lightBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .a11yTapBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Title + intro line. Frozen above the scroll in onboarding mode; sits at the
    /// top of the scroll in reference mode.
    private var header: some View {
        VStack(alignment: .leading, spacing: 22) {
            DSText("How Human Program Works").dsTextStyle(.title2)
            DSText("A quick tour to get you going. You can reopen this any time from Settings → About → Tutorial.")
                .dsTextStyle(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tipsBody: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(displayTips.indices, id: \.self) { i in
                tip(displayTips[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The closing "That's it" tip tells the user to "Tap Done to start," which
    /// only makes sense during onboarding. In the reference page (no Done button)
    /// we drop it.
    private var displayTips: [Tip] {
        mode == .onboarding ? Self.tips : Array(Self.tips.dropLast())
    }

    private func tip(_ t: Tip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DSImageView(systemName: t.icon, size: .font(.title3), tint: .color(.primary))
                DSText(t.title).dsTextStyle(.headline)
            }
            DSText(t.body).dsTextStyle(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Tip { let icon: String; let title: String; let body: String }

    private static let tips: [Tip] = [
        Tip(icon: "sun.max",
            title: "One page per day",
            body: "Each day, Human Program builds a single page for you by pulling together your recurring tasks, anything you've scheduled from the backlog, your daily schedule blocks, and your calendar events. Open the app and you land on Today."),
        Tip(icon: "checkmark.circle",
            title: "Finish your day",
            body: "Check off every task on Today. When all of them are done, the day counts as complete and your streak grows. An empty day (no tasks) is not complete — give yourself something to do."),
        Tip(icon: "clock",
            title: "The schedule timeline",
            body: "The timeline on Today shows your day at a glance: schedule blocks on the left lane, calendar events on the right, with a live red line marking the current time."),
        Tip(icon: "tray.full",
            title: "Backlog",
            body: "Backlog is where you capture everything you might do later. Group items into projects, assign a date to pull an item onto that day's page, and swipe a row to delete. Use the select button to move or delete several at once."),
        Tip(icon: "calendar",
            title: "Calendar",
            body: "Browse your device calendar by month, week, day, or list. Tap + to add an event, or tap an event and choose Edit to change it. You choose which calendars feed Today in Settings → Calendar."),
        Tip(icon: "repeat",
            title: "Routines",
            body: "Routines are reusable checklists — a morning routine, a packing list, anything. Build one once with an emoji and a set of items, then reuse it."),
        Tip(icon: "bell",
            title: "Recurring tasks & reminders",
            body: "In Settings, set up tasks that repeat on chosen weekdays, and notification reminders that fire once or on an interval. Reminders can carry a sound and an image."),
        Tip(icon: "figure.run",
            title: "Schedule & exercise",
            body: "Build your daily schedule (Settings → Schedule) as a set of time blocks — sleep is always first. Set a separate exercise routine per weekday under Settings → Exercise. Exercise is a reference; it only counts toward your day if you also add it as a task."),
        Tip(icon: "lock",
            title: "Edit a past day",
            body: "Past days are locked snapshots so your history stays accurate. To change one, open that date and tap-and-hold the red padlock to unlock it; it re-locks automatically when you leave."),
        Tip(icon: "paintbrush",
            title: "Make it yours",
            body: "Under Settings → Customization, change the font, font size, background, app icon, and light/dark appearance. Settings → Format controls your date and 12-hour / 24-hour time display."),
        Tip(icon: "lock.shield",
            title: "Lock & backups",
            body: "Protect the app with a PIN and Face ID (Settings → Security). Everything stays on your device — nothing syncs to the cloud — so use Settings → Export to make your own backup file, and Import to restore it. Keep backups safe; they're the only copy."),
        Tip(icon: "hand.thumbsup",
            title: "That's it",
            body: "Tap Done to start. You can revisit this tutorial whenever you like from Settings → About → Tutorial."),
    ]
}
