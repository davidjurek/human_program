import SwiftUI
import DSKit

// Shared backlog row + popups. The row supports swipe-left-to-reveal-trash (read
// mode) and whole-row selection (select mode, where tapping the title never
// opens it). Content + trash slide together and are clipped, so the red trash
// slides in from the trailing edge.
struct BacklogRow<Destination: View>: View {
    let title: String
    var subtitle: String?
    let selecting: Bool
    let isSelected: Bool
    let swipeOpen: Bool
    let onTapSelect: () -> Void
    let onOpenSwipe: () -> Void
    let onCloseSwipe: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let destination: () -> Destination

    @State private var dragX: CGFloat = 0
    private let rowHeight: CGFloat = 48   // [#43] tighter row (was 60)
    private let trashW: CGFloat = 68

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                face
                    .frame(width: geo.size.width, height: rowHeight)
                Button(action: onDelete) {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 38, height: 38)
                        Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(.white)
                    }
                    .frame(width: trashW, height: rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(Circle())
            }
            .offset(x: offset)
            .frame(width: geo.size.width, height: rowHeight, alignment: .leading)
            .clipped()
            .gesture(selecting ? nil : swipe)
        }
        .frame(height: rowHeight)
    }

    private var offset: CGFloat {
        let base: CGFloat = swipeOpen ? -trashW : 0
        return min(0, base + dragX)
    }

    @ViewBuilder
    private var face: some View {
        if selecting {
            Button(action: onTapSelect) { faceContent }.buttonStyle(.plain)
                .a11yTapBorder(Rectangle())
        } else {
            NavigationLink(destination: destination) { faceContent }.buttonStyle(.plain)
                .a11yTapBorder(Rectangle())
        }
    }

    private var faceContent: some View {
        HStack(spacing: 12) {
            if selecting {
                SelectionCircle(isOn: isSelected)
            }
            VStack(alignment: .leading, spacing: 2) {
                DSText(title).dsTextStyle(.title3).longTitle()
                if let subtitle { DSText(subtitle).dsTextStyle(.subheadline) }
            }
            Spacer(minLength: 8)
        }
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                dragX = min(0, v.translation.width)
            }
            .onEnded { v in
                let total = (swipeOpen ? -trashW : 0) + v.translation.width
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    if total < -trashW / 2 { onOpenSwipe() } else { onCloseSwipe() }
                    dragX = 0
                }
            }
    }
}

// ── Shared backlog task row + top-bar buttons (used by Task view AND folders) ────

/// One backlog task row: `BacklogRow` wired for a task — whole-row selection toggle,
/// swipe state, delete, and a push to the task detail. Kept as a single row (callers
/// keep their own `ForEach`) so each screen's row spacing is preserved.
struct BacklogTaskRow: View {
    let item: BacklogItem
    let subtitle: String?
    @Binding var selecting: Bool
    @Binding var selected: Set<String>
    @Binding var swipeOpen: String?
    let onDelete: () -> Void

    var body: some View {
        BacklogRow(
            title: item.title,
            subtitle: subtitle,
            selecting: selecting,
            isSelected: selected.contains(item.id),
            swipeOpen: swipeOpen == item.id,
            onTapSelect: {
                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
            },
            onOpenSwipe: { swipeOpen = item.id },
            onCloseSwipe: { if swipeOpen == item.id { swipeOpen = nil } },
            onDelete: onDelete,
            destination: { BacklogTaskDetailView(item: item, startInEdit: false) }
        )
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

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(spacing: 0) {
                DSText("Move to…").dsTextStyle(.headline).padding(.vertical, 14)
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        pickRow("Unorganized") { onPick(nil) }
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
