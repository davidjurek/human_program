import SwiftUI
import SwiftData
import DSKit

// Routines menu — a grid of squares (2 across), each showing the routine's emoji
// centered with the name below. + opens a full editor page (no popup). Pushed from
// the hub; back arrow returns there.
struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.title) private var routines: [Routine]
    @State private var pushNew = false

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ZStack {
            SettingsBackground()
            ScrollView {
                if routines.isEmpty {
                    DSText("No routines yet — tap + to add one")
                        .dsTextStyle(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(routines, id: \.id) { routine in
                            NavigationLink {
                                RoutineEditorView(routine: routine)
                            } label: {
                                RoutineTile(emoji: routine.emoji, name: routine.title)
                            }.buttonStyle(.plain)
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
        .navigationDestination(isPresented: $pushNew) {
            RoutineEditorView(routine: nil)
        }
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
                .onTapGesture { dismiss() }
            Spacer()
            Button { pushNew = true } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary).frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
    }
}

private struct RoutineTile: View {
    let emoji: String
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Text(emoji.isEmpty ? "📋" : emoji).font(.system(size: 40))
            DSText(name.isEmpty ? "Untitled" : name).dsTextStyle(.headline).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .popupGlass(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
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
                .opacity(0.02)
                .onChange(of: emoji) { _, v in
                    // Keep only the last grapheme (one emoji).
                    if let last = v.last { emoji = String(last) } else { emoji = "" }
                }
        }
        .frame(width: 70, height: 44)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}
