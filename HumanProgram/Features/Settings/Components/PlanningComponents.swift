import SwiftUI
import DSKit

// Shared custom controls for the planning editors (Reminders, Recurring Tasks,
// Schedule). Text uses the chosen app font; containers are fixed-height so the
// layout doesn't shift when the font changes.
//
// Expandable rows (dropdown, time/interval pickers) share a single
// `openSection` binding so only one can be open at a time.

// MARK: - Weekday circle selector (S M T W T F S, 1=Sun … 7=Sat), centered

struct WeekdayCircleSelector: View {
    @Binding var selected: Set<Int>

    private let days: [(day: Int, letter: String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(days, id: \.day) { item in
                let isOn = selected.contains(item.day)
                Button {
                    if isOn { selected.remove(item.day) } else { selected.insert(item.day) }
                } label: {
                    ZStack {
                        Circle().fill(isOn ? weekdaySelectedColor : Color.clear)
                        Text(item.letter)
                            .font(appFont(16, bold: true))
                            .foregroundStyle(Color.primary)
                            .fixedSize()
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - App dropdown (translucent floating panel, no tail, on top)

struct AppDropdown: View {
    let label: String
    let options: [(value: String, title: String)]
    @Binding var selection: String
    @Binding var openSection: String?
    let id: String

    private var isOpen: Bool { openSection == id }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        HStack {
            DSText(label).dsTextStyle(.title3)
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.15)) { openSection = isOpen ? nil : id }
            } label: {
                HStack(spacing: 4) {
                    Text(currentTitle).font(appFont(18)).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(height: 34)
        .overlay(alignment: .topTrailing) {
            if isOpen {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.0001)
                        .frame(width: 3000, height: 3000)
                        .contentShape(Rectangle())
                        .onTapGesture { openSection = nil }
                    panel.offset(y: 40)
                }
            }
        }
        .zIndex(isOpen ? 1 : 0)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                    openSection = nil
                } label: {
                    HStack(spacing: 12) {
                        Text(option.title).font(appFont(18)).foregroundStyle(.primary)
                        if option.value == selection {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()   // only as big as the options need
        .popupGlass()
    }
}

// MARK: - Clear interactive glass (toolbar buttons: stretch, no white card)

extension View {
    /// Applies a clear, interactive Liquid Glass effect (iOS 26) — gives the
    /// expand/stretch on press with no visible white capsule. No-op on older OS.
    @ViewBuilder
    func clearGlassButton(_ shape: some Shape = Circle()) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: shape)
        } else {
            self
        }
    }
}

// MARK: - Shared popup glass (heavy blur, translucent)

/// UIKit blur so blur strength and tint opacity are independent (SwiftUI
/// materials couple them). A translucent style = heavy blur, low opacity.
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = UIBlurEffect(style: style)
    }
}

extension View {
    func popupGlass(cornerRadius: CGFloat = 16) -> some View {
        self
            .background {
                ZStack {
                    BlurView(style: .systemThickMaterial)
                    BlurView(style: .systemThickMaterial)   // stacked = heavier blur
                }
                .opacity(0.5)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
    }
}

// MARK: - Confirmation popup (custom, so it uses the chosen app font)

struct ConfirmPopup: View {
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // No dim — fully clear tap-catcher just dismisses on outside tap.
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(spacing: 20) {
                Text(message)
                    .font(appFont(20)).foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("Cancel").font(appFont(18)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    Button(action: onConfirm) {
                        Text(confirmTitle).font(appFont(18)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 300)
            .popupGlass(cornerRadius: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - Time field — value-only tap opens the wheel

struct TimeFieldRow: View {
    let id: String
    let label: String
    @Binding var minutesOfDay: Int
    @Binding var openSection: String?

    private var isOpen: Bool { openSection == id }
    private var hour: Int { minutesOfDay / 60 }
    private var minute: Int { minutesOfDay % 60 }
    private var timeString: String { String(format: "%02d:%02d", hour, minute) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DSText(label).dsTextStyle(.title3)
                Spacer()
                Button { withAnimation { openSection = isOpen ? nil : id } } label: {
                    Text(timeString).font(appFont(18)).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 34)

            if isOpen {
                WheelHourMinute(minutesOfDay: $minutesOfDay)
                    .transition(.opacity)
            }
        }
    }
}

/// Narrow, centered hour:minute wheel. Scrolls normally (drags scroll the
/// wheel). A tap opens a single numpad for the whole time (HHMM, HH first).
struct WheelHourMinute: View {
    @Binding var minutesOfDay: Int

    @State private var typed = ""
    @FocusState private var keypadFocused: Bool

    private var hourBinding: Binding<Int> {
        Binding(get: { minutesOfDay / 60 }, set: { minutesOfDay = $0 * 60 + (minutesOfDay % 60) })
    }
    private var minuteBinding: Binding<Int> {
        Binding(get: { minutesOfDay % 60 }, set: { minutesOfDay = (minutesOfDay / 60) * 60 + $0 })
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: hourBinding) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)

            Text(":").font(.system(size: 20, weight: .semibold))

            Picker("", selection: minuteBinding) {
                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
        }
        .frame(width: 210, height: 140)
        .frame(maxWidth: .infinity)
        // Tap (not drag) opens the numpad; drags still scroll the wheel.
        .simultaneousGesture(TapGesture().onEnded {
            typed = ""
            keypadFocused = true
        })
        .overlay(
            TextField("", text: $typed)
                .keyboardType(.numberPad)
                .focused($keypadFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onChange(of: typed) { _, _ in applyTyped() }
        )
    }

    private func applyTyped() {
        let s = String(typed.filter(\.isNumber).prefix(4))
        guard !s.isEmpty else { return }
        var hh = 0, mm = 0
        hh = Int(String(s.prefix(2))) ?? 0
        if s.count >= 3 { mm = Int(String(s.dropFirst(2))) ?? 0 }
        minutesOfDay = min(23, hh) * 60 + min(59, mm)
        if s.count >= 4 { keypadFocused = false }
    }
}

// MARK: - Interval field ("Every N min/hr"), value-only tap

struct IntervalFieldRow: View {
    let id: String
    let label: String
    @Binding var amount: Int
    @Binding var unitIsHours: Bool
    @Binding var openSection: String?

    private var isOpen: Bool { openSection == id }
    private var unitLabel: String { unitIsHours ? (amount == 1 ? "hour" : "hours") : "min" }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                DSText(label).dsTextStyle(.title3)
                Spacer(minLength: 8)
                Button { withAnimation { openSection = isOpen ? nil : id } } label: {
                    Text("\(amount) \(unitLabel)").font(appFont(18)).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 34)

            if isOpen {
                HStack(spacing: 0) {
                    Picker("", selection: $amount) {
                        ForEach(1...(unitIsHours ? 10 : 59), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("", selection: $unitIsHours) {
                        Text("min").tag(false)
                        Text("hr").tag(true)
                    }
                    .pickerStyle(.wheel)
                }
                .frame(width: 210, height: 140)
                .frame(maxWidth: .infinity)
                .onChange(of: unitIsHours) { _, hours in
                    if hours { amount = min(amount, 10) }
                    if amount < 1 { amount = 1 }
                }
            }
        }
    }
}
