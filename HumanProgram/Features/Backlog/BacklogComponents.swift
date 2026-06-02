import SwiftUI
import DSKit

// Shared backlog row. Tap / scroll-over / swipe-left-to-reveal-trash all run on the
// SAME shared gesture engine (RowGestureCoordinator) that drives Today, Schedule,
// Exercise and Routines — Backlog just disables hold-to-reorder (it's a sorted list).
// The row grows to fit up to a 3-line title (varying heights). Content + trash slide
// together (clipped) so the red trash slides in from the trailing edge.
enum BacklogRowGlyph { case bullet, folder }

struct BacklogRow: View {
    let coordinator: RowGestureCoordinator<String>
    let id: String
    let glyph: BacklogRowGlyph
    let title: String
    var subtitle: String? = nil
    let selecting: Bool
    let isSelected: Bool
    /// A clean tap (read mode → navigate; select mode → toggle). Caller decides.
    let onTap: () -> Void

    private let rowMinHeight: CGFloat = 48
    private var trashW: CGFloat { coordinator.trashWidth }

    var body: some View {
        // A hidden copy of the content drives the row HEIGHT so a long title can wrap to
        // up to 3 lines and the row grows to fit. The GeometryReader overlay lays out the
        // slide-together content + trash at that measured size. [owner: 3-line rows]
        ZStack {
            faceContent.hidden()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    faceContent
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { if coordinator.consumeTap() { onTap() } }
                    Button { coordinator.tapTrash(id) } label: {
                        ZStack {
                            Circle().fill(Color.red).frame(width: 38, height: 38)
                            Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(.white)
                        }
                        .frame(width: trashW, height: geo.size.height)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(coordinator.swipeOpenId == id)   // only when fully swiped
                    .a11yTapBorder(Circle())
                }
                .offset(x: coordinator.swipeOffset(for: id))
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RowFrameKey<String>.self,
                                       value: [id: proxy.frame(in: .global)])
            }
        )
    }

    private var faceContent: some View {
        HStack(spacing: 12) {
            leadingGlyph
            VStack(alignment: .leading, spacing: 2) {
                DSText(title).dsTextStyle(.title3).longTitle(lineLimit: 3)
                if let subtitle { DSText(subtitle).dsTextStyle(.subheadline) }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
        .frame(minHeight: rowMinHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if selecting {
            SelectionCircle(isOn: isSelected)
        } else {
            switch glyph {
            case .bullet: DSText("•").dsTextStyle(.title3)
            case .folder: DSImageView(systemName: "folder", size: 18, tint: .color(.secondary))
            }
        }
    }
}

/// Top-bar icon button (44pt tall, 40pt wide tap target with the documented
/// contentShape + a11y border). Shared by both backlog top bars.
struct BacklogBarButton: View {
    let icon: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint).frame(width: 40, height: 44).contentShape(Rectangle())
                .a11yTapBorder(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Top-bar text button ("Select" / "Done"). Shared by both backlog top bars.
struct BacklogTextBarButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSText(title).dsTextStyle(.headline).contentShape(Rectangle())
        }.buttonStyle(.plain).a11yTapBorder(cornerRadius: 4).padding(.horizontal, 6)
    }
}

// ── New project popup (DSKit glass, duplicate-title block) ───────────────────────
struct NewProjectPopup: View {
    @Binding var name: String
    @Binding var error: String?
    let onCreate: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(spacing: 16) {
                DSText("New Project").dsTextStyle(.headline)
                TextField("Title", text: $name)
                    .font(appFont(18)).focused($focused)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                if let error {
                    Text(error).font(appFont(13)).foregroundStyle(.red)
                }
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("Cancel").font(appFont(18)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .a11yTapBorder(cornerRadius: 6)
                    Button(action: onCreate) {
                        Text("Add").font(appFont(18)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .a11yTapBorder(cornerRadius: 6)
                }
            }
            .padding(20).frame(width: 300).popupGlass(cornerRadius: 22)
            .offset(y: -80)   // sit slightly above center (clears the keyboard) [#1]
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { focused = true }
    }
}

// ── Move-to-project popup ────────────────────────────────────────────────────────
struct MoveToProjectPopup: View {
    let projects: [ProjectBucket]
    let onPick: (ProjectBucket?) -> Void
    let onCancel: () -> Void
    /// Header + the label for the "no project" choice. Defaults suit the move action;
    /// the task editor reuses this same glass popup as its project picker. [#4]
    var title: String = "Move to…"
    var noneLabel: String = "Unorganized"

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(spacing: 0) {
                DSText(title).dsTextStyle(.headline).padding(.vertical, 14)
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        pickRow(noneLabel) { onPick(nil) }
                        ForEach(projects, id: \.id) { p in
                            pickRow(p.name) { onPick(p) }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 300).popupGlass(cornerRadius: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func pickRow(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSText(name).dsTextStyle(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).frame(height: 48)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .a11yTapBorder(Rectangle())
    }
}
