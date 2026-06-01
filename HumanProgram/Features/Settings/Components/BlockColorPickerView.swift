import SwiftUI
import DSKit

// Custom color picker (NOT Apple's): a shared preset library (starts with 12,
// add/long-press-delete, max 24 = 6×4) plus three ways to make a custom colour —
// RGB+Hex, HSB, and a hue/spectrum grid. Replaces the system ColorPicker for
// schedule block + Sleep colours. [#14]

/// Shared, app-wide preset swatch library, persisted in UserDefaults.
final class ColorPresetStore: ObservableObject {
    static let shared = ColorPresetStore()
    private let key = "blockColorPresets"
    static let maxPresets = 18   // 6×3 [#14]

    @Published private(set) var presets: [String]

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: key), !saved.isEmpty {
            presets = saved
        } else {
            presets = BlockColors.swatches   // ships with 12
        }
    }

    private func persist() { UserDefaults.standard.set(presets, forKey: key) }

    func add(_ hex: String) {
        let h = hex.uppercased()
        guard !presets.contains(h), presets.count < Self.maxPresets else { return }
        presets.append(h); persist()
    }
    func delete(_ hex: String) {
        presets.removeAll { $0.caseInsensitiveCompare(hex) == .orderedSame }; persist()
    }
    /// Fill the first empty slot with `hex` (no-op if full or already present). [#14]
    func addToEmptySlot(_ hex: String) {
        let h = hex.uppercased()
        guard !presets.contains(h), presets.count < Self.maxPresets else { return }
        presets.append(h); persist()
    }
    /// Overwrite the swatch at `index` with `hex` (double-tap to replace). [#14]
    func replace(at index: Int, with hex: String) {
        guard presets.indices.contains(index) else { return }
        presets[index] = hex.uppercased(); persist()
    }
    /// Restore the shipped default swatches. [#14]
    func reset() { presets = BlockColors.swatches; persist() }
    var isFull: Bool { presets.count >= Self.maxPresets }
}

/// The picker panel. Binds to a block's `colorHex`; tapping a swatch or editing
/// the custom controls updates it live.
struct BlockColorPickerView: View {
    @Binding var colorHex: String?
    let title: String
    let onClose: () -> Void

    @StateObject private var store = ColorPresetStore.shared
    @State private var mode: Mode = .hex
    // Working RGB (0…1) for the custom controls.
    @State private var r: Double = 0.5
    @State private var g: Double = 0.5
    @State private var b: Double = 0.5
    @State private var hexField: String = ""
    @State private var pendingDelete: String? = nil

    enum Mode: String, CaseIterable { case hex = "RGB", hsb = "HSB", spectrum = "Spectrum" }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    private var currentColor: Color { Color(red: r, green: g, blue: b) }
    private var currentHex: String { Color(red: r, green: g, blue: b).hexString }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                DSText(title).dsTextStyle(.headline)
                Spacer()
                Button { onClose() } label: { DSText("Done").dsTextStyle(.headline).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .a11yTapBorder(cornerRadius: 4)
            }

            // 18 fixed slots. Filled: tap to use, double-tap to overwrite with
            // the current colour, long-press to delete. Empty: tap to store the
            // current colour in the first empty slot. No "+". [#14]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(0..<ColorPresetStore.maxPresets, id: \.self) { i in
                    if i < store.presets.count {
                        swatch(store.presets[i], at: i)
                    } else {
                        emptySlot
                    }
                }
            }

            // Preview swatch + Reset on one line (hex is shown in the Hex row). [#14]
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(currentColor)
                    .frame(width: 44, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                Spacer()
                Button { store.reset() } label: { DSText("Reset to presets").dsTextStyle(.subheadline).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .a11yTapBorder(cornerRadius: 4)
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .hex:      hexEditor
            case .hsb:      hsbEditor
            case .spectrum: spectrumEditor
            }
        }
        .padding(20)
        .frame(width: 320)
        .popupGlass(cornerRadius: 22)
        .onAppear {
            syncFromBinding()
            // App font on the RGB/HSB/Spectrum segmented control. [#14]
            let attrs: [NSAttributedString.Key: Any] = [.font: appUIFont(14)]
            UISegmentedControl.appearance().setTitleTextAttributes(attrs, for: .normal)
            UISegmentedControl.appearance().setTitleTextAttributes(attrs, for: .selected)
        }
    }

    /// Empty preset slot — tap to store the current custom colour. [#14]
    private var emptySlot: some View {
        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
            .frame(height: 34)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10)))
            .contentShape(Rectangle())
            .a11yTapBorder(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { store.addToEmptySlot(currentHex) }
    }

    // MARK: - Swatch

    private func swatch(_ hex: String, at index: Int) -> some View {
        let isSel = colorHex?.caseInsensitiveCompare(hex) == .orderedSame
        return (Color(hex: hex) ?? .gray)
            .frame(height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSel ? Color.primary : Color.primary.opacity(0.12),
                              lineWidth: isSel ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if pendingDelete == hex {
                    Button { store.delete(hex); pendingDelete = nil } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(.red)
                            .background(Circle().fill(.white))
                            .contentShape(Circle())
                    }.buttonStyle(.plain).a11yTapBorder(Circle()).offset(x: 5, y: -5)
                }
            }
            .contentShape(Rectangle())
            .a11yTapBorder(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(count: 2) {
                pendingDelete = nil
                store.replace(at: index, with: currentHex)
                colorHex = currentHex
            }
            .onTapGesture {
                if pendingDelete != nil { pendingDelete = nil; return }
                colorHex = hex; setWorking(toHex: hex)
            }
            .onLongPressGesture { pendingDelete = (pendingDelete == hex ? nil : hex) }
    }

    // MARK: - Editors

    private var hexEditor: some View {
        VStack(spacing: 12) {
            HStack {
                DSText("Hex").dsTextStyle(.body)
                Spacer()
                TextField("RRGGBB", text: $hexField)
                    .font(appFont(17)).multilineTextAlignment(.trailing)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .frame(width: 110)
                    .onSubmit { applyHexField() }
                    .onChange(of: hexField) { _, v in if v.count == 6 { applyHexField() } }
            }
            channelSlider("R", $r, .red)
            channelSlider("G", $g, .green)
            channelSlider("B", $b, .blue)
        }
    }

    private var hsbEditor: some View {
        // Derive HSB from current RGB, edit, write back.
        let hsb = rgbToHSB(r, g, b)
        return VStack(spacing: 12) {
            hsbSlider("Hue", hsb.h) { applyHSB(h: $0, s: hsb.s, v: hsb.v) }
            hsbSlider("Sat", hsb.s) { applyHSB(h: hsb.h, s: $0, v: hsb.v) }
            hsbSlider("Bright", hsb.v) { applyHSB(h: hsb.h, s: hsb.s, v: $0) }
        }
    }

    private var spectrumEditor: some View {
        let hsb = rgbToHSB(r, g, b)
        return VStack(spacing: 12) {
            // Saturation (x) × Brightness (y) area for the current hue.
            GeometryReader { geo in
                ZStack {
                    LinearGradient(colors: [.white, Color(hue: hsb.h, saturation: 1, brightness: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 16, height: 16)
                        .background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1).frame(width: 16, height: 16))
                        .offset(x: hsb.s * geo.size.width - 8, y: (1 - hsb.v) * geo.size.height - 8)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                    let s = min(max(0, val.location.x / geo.size.width), 1)
                    let v = 1 - min(max(0, val.location.y / geo.size.height), 1)
                    applyHSB(h: hsb.h, s: s, v: v)
                })
            }
            .frame(height: 120)
            // Hue strip.
            hueStrip(hsb.h) { applyHSB(h: $0, s: max(hsb.s, 0.01), v: max(hsb.v, 0.01)) }
        }
    }

    private func channelSlider(_ label: String, _ value: Binding<Double>, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            DSText(label).dsTextStyle(.body).frame(width: 18, alignment: .leading)
            Slider(value: value, in: 0...1).tint(tint)
                .onChange(of: value.wrappedValue) { _, _ in syncHexField() }
        }
    }

    private func hsbSlider(_ label: String, _ value: Double, _ apply: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            DSText(label).dsTextStyle(.body).frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { apply($0) }), in: 0...1)
                .tint(currentColor)
        }
    }

    private func hueStrip(_ hue: Double, _ apply: @escaping (Double) -> Void) -> some View {
        GeometryReader { geo in
            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0/6).map { Color(hue: $0, saturation: 1, brightness: 1) },
                           startPoint: .leading, endPoint: .trailing)
                .clipShape(Capsule())
                .overlay(alignment: .leading) {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 18, height: 18)
                        .offset(x: hue * geo.size.width - 9)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                    apply(min(max(0, val.location.x / geo.size.width), 1))
                })
        }
        .frame(height: 18)
    }

    // MARK: - State sync

    private func syncFromBinding() {
        if let hex = colorHex, Color(hex: hex) != nil { setWorking(toHex: hex) }
        else { setWorking(toHex: BlockColors.defaultHex(forTitle: title)) }
    }
    private func setWorking(toHex hex: String) {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return }
        r = Double((v >> 16) & 0xFF)/255; g = Double((v >> 8) & 0xFF)/255; b = Double(v & 0xFF)/255
        syncHexField()
    }
    private func syncHexField() { hexField = currentHex; colorHex = currentHex }
    private func applyHexField() { setWorking(toHex: hexField) }
    private func applyHSB(h: Double, s: Double, v: Double) {
        let c = Color(hue: h, saturation: s, brightness: v)
        let ui = UIColor(c); var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r = rr; g = gg; b = bb; syncHexField()
    }
}

// HSB helper (UIColor round-trip).
private func rgbToHSB(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
    var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
    UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
    return (Double(h), Double(s), Double(v))
}
