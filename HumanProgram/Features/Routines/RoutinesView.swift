import SwiftUI
import SwiftData
import DSKit

// Routines menu — a grid of squares (2 across), each showing the routine's emoji
// centered with the name below. + opens a full editor page (no popup). Pushed from
// the hub; back arrow returns there.
/// Shared display fallbacks for a routine's empty title / emoji, so the tile and the
/// editor show the same placeholders and can't drift apart. [#173]
enum RoutineDisplay {
    static let untitled = "Untitled"
    static let emojiFallback = "📋"

    static func title(_ s: String) -> String { s.isEmpty ? untitled : s }
    static func emoji(_ s: String) -> String { s.isEmpty ? emojiFallback : s }
}

/// Lightweight markdown renderer for a routine's body (read mode). Renders inline
/// styling — **bold**, *italic*, `code`, [links](url) — via Apple's native
/// AttributedString, plus hand-styled headings (`#`, `##`, `###`), bullet lines
/// (`-`, `*`), and GitHub-style pipe tables (which Apple's parser can't do). Wide
/// tables shrink uniformly to fit the column width. No third-party renderer. [routines]
struct MarkdownText: View {
    private let text: String
    init(_ text: String) { self.text = text }

    // Seed with the screen width so the FIRST read-mode paint already has a sane width to
    // shrink tables against. A plain 0 default was measured a beat too late on the
    // edit→read switch, so a wide table rendered un-shrunk (overflowing) until you left
    // and came back.
    @State private var width: CGFloat = UIScreen.main.bounds.width

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .line(let s):
                    lineView(s)
                case .table(let header, let rows):
                    MarkdownTable(header: header, rows: rows, available: width)
                }
            }
        }
        // Pin to the parent's width so the measured width is the column width, not the
        // content width (a table-only body would otherwise feed back on itself).
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: MarkdownWidthKey.self, value: g.size.width)
        })
        // Clamp to the screen and ignore 0 so a transient unbounded layout pass during the
        // edit→read switch can't lock the width onto a wide table's full natural width.
        .onPreferenceChange(MarkdownWidthKey.self) { if $0 > 0 { width = min($0, UIScreen.main.bounds.width) } }
    }

    // MARK: - Block parsing

    private enum Block { case line(String), table(header: [String], rows: [[String]]) }

    /// Split the text into line blocks and table blocks. A table is a pipe row
    /// immediately followed by a `|---|---|` delimiter row, then contiguous pipe rows.
    private var blocks: [Block] {
        let lines = text.components(separatedBy: "\n")
        var out: [Block] = []
        var i = 0
        while i < lines.count {
            if i + 1 < lines.count, isPipeRow(lines[i]), isDelimiterRow(lines[i + 1]) {
                let header = cells(lines[i])
                var body: [[String]] = []
                var j = i + 2
                while j < lines.count, isPipeRow(lines[j]), !isDelimiterRow(lines[j]) {
                    body.append(cells(lines[j])); j += 1
                }
                out.append(.table(header: header, rows: body))
                i = j
            } else {
                out.append(.line(lines[i])); i += 1
            }
        }
        return out
    }

    private func isPipeRow(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.contains("|")
    }
    private func isDelimiterRow(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("|"), t.contains("-") else { return false }
        let cs = splitCells(t)
        return !cs.isEmpty && cs.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
    private func cells(_ s: String) -> [String] { splitCells(s).map { $0.trimmingCharacters(in: .whitespaces) } }
    private func splitCells(_ s: String) -> [String] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|")
    }

    // MARK: - Per-line rendering

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 4)
        } else if let (level, rest) = heading(line) {
            Text(mdInline(rest))
                .font(appFont(level == 1 ? 24 : level == 2 ? 20 : 18)).fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let item = bullet(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(appFont(17))
                Text(mdInline(item)).font(appFont(17))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(mdInline(line)).font(appFont(17))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heading(_ s: String) -> (Int, String)? {
        if s.hasPrefix("### ") { return (3, String(s.dropFirst(4))) }
        if s.hasPrefix("## ")  { return (2, String(s.dropFirst(3))) }
        if s.hasPrefix("# ")   { return (1, String(s.dropFirst(2))) }
        return nil
    }
    private func bullet(_ s: String) -> String? {
        if s.hasPrefix("- ") || s.hasPrefix("* ") { return String(s.dropFirst(2)) }
        return nil
    }
}

private struct MarkdownWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Inline markdown → AttributedString (bold/italic/`code`/links). Shared by the line
/// renderer and table cells.
private func mdInline(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

/// GitHub-style pipe table, laid out at its natural width then scaled down uniformly
/// to fit `available` (shrink-to-fit; never enlarged). Column widths and the row
/// height are computed analytically from the cell text using the SAME font as the
/// rendered cells, so there's no layout feedback and `lineLimit(1)` never clips.
private struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]
    let available: CGFloat

    private let base: CGFloat = 15
    private let hPad: CGFloat = 10
    private let border = Color.primary.opacity(0.18)

    private var colCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }
    private func cell(_ row: [String], _ c: Int) -> String { c < row.count ? row[c] : "" }

    private var colWidths: [CGFloat] {
        // appFont(base) applies the user's font scale internally, so measure with the
        // pre-scaled UIFont (same convention as Backlog's sort-popup sizing).
        let font = appUIFont(appScaledSize(base))
        return (0..<colCount).map { c in
            let all = [cell(header, c)] + rows.map { cell($0, c) }
            let w = all.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            return max(40, ceil(w) + 2 * hPad + 2)
        }
    }
    private var rowHeight: CGFloat { ceil(appUIFont(appScaledSize(base)).lineHeight) + 12 }

    var body: some View {
        let cols = colWidths
        let naturalW = cols.reduce(0, +)
        let naturalH = rowHeight * CGFloat(rows.count + 1)
        let scale = (available > 0 && naturalW > available) ? available / naturalW : 1
        VStack(spacing: 0) {
            tableRow(header, cols, bold: true)
            ForEach(rows.indices, id: \.self) { r in tableRow(rows[r], cols, bold: false) }
        }
        .scaleEffect(scale, anchor: .topLeading)
        // Reserve the SCALED footprint so the surrounding stack doesn't leave a gap.
        .frame(width: naturalW * scale, height: naturalH * scale, alignment: .leading)
    }

    private func tableRow(_ row: [String], _ cols: [CGFloat], bold: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(cols.indices, id: \.self) { c in
                Text(mdInline(cell(row, c)))
                    .font(appFont(base)).fontWeight(bold ? .semibold : .regular)
                    .lineLimit(1)
                    .padding(.horizontal, hPad)
                    .frame(width: cols[c], height: rowHeight, alignment: .leading)
                    .overlay(Rectangle().stroke(border, lineWidth: 0.5))
            }
        }
    }
}

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var routines: [Routine]
    @State private var pushNew = false

    // View mode (grid of cards / list of rows) and sort persist across visits, and the
    // sort applies to BOTH layouts. Same @AppStorage pattern as Backlog. [owner]
    @AppStorage(DefaultsKey.routineViewMode) private var layout: Layout = .grid
    @AppStorage(DefaultsKey.routineSort) private var sort: Sort = .az
    @State private var showSort = false
    @State private var anchorFrames: [String: CGRect] = [:]
    private let anchorSpace = "routineAnchorSpace"

    enum Layout: String { case grid, rows }
    enum Sort: String, CaseIterable { case az = "A–Z", created = "Creation date" }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    /// Sort applied to whichever layout is showing. [owner]
    private var sortedRoutines: [Routine] {
        switch sort {
        case .az:      return routines.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .created: return routines.sorted { $0.createdAt < $1.createdAt }
        }
    }

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                if routines.isEmpty {
                    DSText("No routines yet")
                        .dsTextStyle(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 80)
                } else if layout == .grid {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sortedRoutines, id: \.id) { routine in
                            NavigationLink {
                                RoutineEditorView(routine: routine)
                            } label: {
                                RoutineTile(emoji: routine.emoji, name: routine.title)
                            }.buttonStyle(.plain)
                            .a11yTapBorder(RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedRoutines, id: \.id) { routine in
                            NavigationLink {
                                RoutineEditorView(routine: routine)
                            } label: {
                                RoutineRow(emoji: routine.emoji, name: routine.title)
                            }.buttonStyle(.plain)
                            .a11yTapBorder(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
                Color.clear.frame(height: 40)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .overlay { if showSort { sortPopup } }
        .coordinateSpace(.named(anchorSpace))
        .onPreferenceChange(AnchorFrameKey.self) { anchorFrames = $0 }
        .navigationDestination(isPresented: $pushNew) {
            RoutineEditorView(routine: nil)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            // DSKit top-bar glyphs (same pattern as Calendar/Backlog top bars). [#199]
            BackChevronButton { dismiss() }
            Spacer()
            sortButton
            layoutButton
            Button { pushNew = true } label: {
                DSImageView(systemName: "plus", size: 20, tint: .color(.primary))
                    .fontWeight(.medium)
                    .frame(width: 40, height: 44).contentShape(Rectangle())
                    .a11yTapBorder(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .topBarFrost()                                       // [#47]
    }

    private var layoutButton: some View {
        // Shows the icon of the layout you'd switch TO.
        Button { layout = layout == .grid ? .rows : .grid } label: {
            DSImageView(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2",
                        size: 18, tint: .color(.primary))
                .frame(width: 40, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }.buttonStyle(.plain)
    }

    // DSKit anchored sort popup (app font), same as Backlog's. [#199]
    private var sortButton: some View {
        Button { showSort.toggle() } label: {
            DSImageView(systemName: "arrow.up.arrow.down", size: 17, tint: .color(.primary))
                .frame(width: 40, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }
        .buttonStyle(.plain)
        .anchorFrame("routineSort", in: .named(anchorSpace))
    }

    /// Tight popup width: longest option (in the .body font, reg 17) + checkmark column
    /// + gaps + padding. Reserved checkmark column keeps the width stable. [owner]
    private var sortPopupWidth: CGFloat {
        let font = appUIFont(appScaledSize(17))
        let textW = Sort.allCases.map(\.rawValue)
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(textW) + 14 + 12 + 8 + 36 + 4
    }

    @ViewBuilder
    private var sortPopup: some View {
        if let rect = anchorFrames["routineSort"] {
            AnchoredPopup(anchor: rect, width: sortPopupWidth,
                          estimatedHeight: CGFloat(Sort.allCases.count) * 44 + 12,
                          alignment: .leading, space: .named(anchorSpace),
                          onClose: { showSort = false }) {
                VStack(spacing: 0) {
                    ForEach(Sort.allCases, id: \.self) { s in
                        sortOptionRow(title: s.rawValue, selected: sort == s) { sort = s; showSort = false }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func sortOptionRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary).opacity(selected ? 1 : 0).frame(width: 14)
                DSText(title).dsTextStyle(.body)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 18)
            .frame(height: 44).frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).a11yTapBorder(cornerRadius: 4)
    }
}

private struct RoutineTile: View {
    let emoji: String
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Text(RoutineDisplay.emoji(emoji)).font(.system(size: 40))
            DSText(RoutineDisplay.title(name)).dsTextStyle(.headline)
                .multilineTextAlignment(.center)
                .longTitle()
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .popupGlass(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

// Row layout: emoji + name on one line, full-width glass card. Same fallbacks and
// glass as the grid tile so the two layouts can't drift. [owner]
private struct RoutineRow: View {
    let emoji: String
    let name: String

    var body: some View {
        HStack(spacing: 14) {
            Text(RoutineDisplay.emoji(emoji)).font(.system(size: 30))
            DSText(RoutineDisplay.title(name)).dsTextStyle(.headline)
                .longTitle()
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .popupGlass(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

// ── Single-emoji field (system emoji keyboard, keeps last emoji only) ────────────
struct EmojiField: View {
    @Binding var emoji: String
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Text(emoji.isEmpty ? "Select" : emoji)
                .font(emoji.isEmpty ? appFont(16) : .system(size: 30))
                .foregroundStyle(emoji.isEmpty ? .secondary : .primary)
            TextField("", text: $emoji)
                .focused($focused)
                .keyboardType(.default)
                .opacity(0.02)
                .onChange(of: emoji) { _, v in
                    // Keep only the last grapheme, and only if it's an emoji.
                    // Non-emoji characters (letters, digits, punctuation) are rejected.
                    if let last = v.last, last.isEmoji {
                        if String(last) != emoji { emoji = String(last) }
                    } else {
                        emoji = ""
                    }
                }
        }
        .frame(width: 70, height: 44)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .a11yTapBorder(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { focused = true }
    }
}

extension Character {
    /// True for a single emoji grapheme (emoji-presentation scalar, or a
    /// multi-scalar sequence like a ZWJ/flag/variation emoji). Excludes plain
    /// digits/letters that merely have a default-text emoji property.
    var isEmoji: Bool {
        unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji == true)
    }
}
