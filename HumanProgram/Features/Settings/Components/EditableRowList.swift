import SwiftUI
import UIKit

// ONE shared implementation of the editable-row gesture combo used by every
// list-of-rows screen (Schedule blocks, Exercise items, Today tasks):
//
//   • clean TAP           → the row's own action (edit / open detail)
//   • hold ~0.4s + drag   → reorder (pops, smooth snap)
//   • horizontal swipe    → reveal a trailing trash; tap it to delete
//   • vertical drag       → native scrolling
//
// Before this existed, each screen re-derived the state + geometry + animation
// (offsets, thresholds, snap springs, the rubber-band factor) and they drifted —
// different feel per screen and the same bugs fixed in one place but not another.
// Now the behaviour lives here once; screens supply only their data + row content.
//
// Generic over the row id (`ID: Hashable`): UUID for Schedule/Exercise drafts,
// String for Today's tasks.
//
// ── Tap vs. swipe (the rule the owner asked for) ────────────────────────────────
// Only a TRUE simple tap counts as a tap. If the horizontal swipe recognizer
// engaged at all — the row slid even a little — releasing must NOT fire the row's
// tap or the trash; the row just slides back. We can't rely on UIKit's
// `cancelsTouchesInView` because that cancels touch delivery to the *view*, not to
// SwiftUI's tap *gesture recognizer*. So we suppress deterministically: a flag set
// the moment the swipe pan begins, consumed by every tap path, cleared one run
// loop after the gesture ends (so a tap landing on that same release is still
// suppressed, but the next clean tap is allowed).

@MainActor
@Observable
final class RowGestureCoordinator<ID: Hashable> {
    let rowHeight: CGFloat
    let trashWidth: CGFloat
    /// When false, hold-to-reorder is disabled entirely (e.g. Backlog is a sorted list,
    /// not manually ordered) — only tap / swipe-to-delete / scroll are active.
    let reorderEnabled: Bool

    // Reorder (vertical). dragId/dragDY are observed so rows animate.
    var dragId: ID?
    var dragDY: CGFloat = 0
    // Row window frames, fed to the UIKit recognizers for hit-testing.
    var rowFrames: [ID: CGRect] = [:]

    // Swipe-to-delete (horizontal).
    var swipeOpenId: ID?
    var swipeDragId: ID?
    var swipeDragX: CGFloat = 0

    // A horizontal swipe engaged → the release is not a tap. Not observed (pure
    // gesture bookkeeping, never drives layout), so writes don't invalidate views.
    @ObservationIgnored private var swipeEngaged = false

    // Host hooks. @ObservationIgnored + reassigned from the host's body each render
    // so they always close over the host's CURRENT data (no stale snapshots) without
    // triggering a view-update loop.
    @ObservationIgnored var orderedIds: () -> [ID] = { [] }
    @ObservationIgnored var moveRow: (_ from: Int, _ to: Int) -> Void = { _, _ in }
    @ObservationIgnored var deleteRow: (ID) -> Void = { _ in }
    /// Host-side "a gesture started, close any inline edit" (commit/blur a title).
    @ObservationIgnored var beginEditGesture: () -> Void = {}
    /// Gate for reorder + swipe (e.g. a locked past day disables both).
    @ObservationIgnored var canInteract: () -> Bool = { true }

    init(rowHeight: CGFloat, trashWidth: CGFloat = 72, reorderEnabled: Bool = true) {
        self.rowHeight = rowHeight
        self.trashWidth = trashWidth
        self.reorderEnabled = reorderEnabled
    }

    /// True while a row is being dragged or swiped — the host suspends native
    /// scrolling so the gesture owns the touch.
    var isInteracting: Bool { dragId != nil || swipeDragId != nil }

    // MARK: - Reorder

    func beginReorder(_ id: ID) {
        guard reorderEnabled, canInteract() else { return }
        swipeOpenId = nil
        beginEditGesture()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy(duration: 0.18)) { dragId = id; dragDY = 0 }
    }

    func dragChanged(_ dy: CGFloat) { if dragId != nil { dragDY = dy } }

    func endReorder(_ dy: CGFloat) {
        guard let id = dragId else { return }
        let ids = orderedIds()
        guard let base = ids.firstIndex(of: id) else { dragId = nil; return }
        let proj = projectedIndex(from: base, dy: dy, count: ids.count)
        withAnimation(.snappy(duration: 0.22)) {
            if proj != base { moveRow(base, proj) }
            dragId = nil
        }
    }

    func cancelReorder() { dragId = nil }

    // MARK: - Swipe

    func swipeBegan(_ id: ID) {
        if swipeOpenId != id, swipeOpenId != nil {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
        }
        beginEditGesture()
        swipeEngaged = true
        swipeDragId = id
        swipeDragX = 0
    }

    func swipeChanged(_ tx: CGFloat) { if swipeDragId != nil { swipeDragX = tx } }

    func swipeEnded(_ tx: CGFloat, _ vx: CGFloat) {
        guard let id = swipeDragId else { return }
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let total = base + tx
        let opens = total < -trashWidth / 2
        // Snap open or closed; delete is via the revealed trash, never full-swipe.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            swipeOpenId = opens ? id : nil
            swipeDragId = nil
            swipeDragX = 0
        }
        // Clear suppression AFTER this run loop: a tap landing on this same release
        // is still suppressed, but the next clean tap is allowed.
        DispatchQueue.main.async { [weak self] in self?.swipeEngaged = false }
    }

    func closeSwipe() {
        withAnimation(.snappy(duration: 0.2)) { swipeOpenId = nil }
    }

    func closeSwipeIfOpen() {
        guard swipeOpenId != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { swipeOpenId = nil }
    }

    // MARK: - Tap gating

    /// Call FIRST from a row's tap handler. Returns true only for a clean tap the
    /// caller may act on. Returns false (and absorbs the tap) if the gesture was a
    /// swipe, or if a swiped-open row needs closing first.
    func consumeTap() -> Bool {
        if swipeEngaged { return false }            // was a swipe, not a tap
        if swipeOpenId != nil { closeSwipe(); return false }  // close open row, eat tap
        return true
    }

    /// The revealed trash only deletes on a clean tap of an already-open row — never
    /// as the tail of a swipe (which would make a small pull delete by accident).
    func tapTrash(_ id: ID) {
        guard !swipeEngaged, swipeOpenId == id else { return }
        swipeOpenId = nil
        deleteRow(id)
    }

    // MARK: - Geometry

    func projectedIndex(from base: Int, dy: CGFloat, count: Int) -> Int {
        let shift = Int((dy / rowHeight).rounded())
        return max(0, min(count - 1, base + shift))
    }

    /// Vertical shift that opens a gap for the dragged row by sliding the rows it
    /// has passed over (the data array isn't mutated until the drag ends).
    func shiftOffset(forIndex i: Int) -> CGFloat {
        guard let id = dragId else { return 0 }
        let ids = orderedIds()
        guard let base = ids.firstIndex(of: id), base != i else { return 0 }
        let proj = projectedIndex(from: base, dy: dragDY, count: ids.count)
        if base < proj, (base + 1 ... proj).contains(i) { return -rowHeight }
        if proj < base, (proj ..< base).contains(i) { return rowHeight }
        return 0
    }

    /// Live horizontal offset. Clamps at the open position with a little rubber-band.
    func swipeOffset(for id: ID) -> CGFloat {
        let base: CGFloat = (swipeOpenId == id) ? -trashWidth : 0
        let raw = base + ((swipeDragId == id) ? swipeDragX : 0)
        if raw < -trashWidth { return -trashWidth - (-trashWidth - raw) * 0.2 }
        return min(0, raw)
    }
}

// MARK: - Shared row wrapper

/// One editable row: the content + a trailing trash lane that slide together
/// (clipped, so the red circle slides IN from the edge as you swipe), plus the
/// reorder lift/scale/shadow. Reports its own window frame for hit-testing.
struct EditableRow<ID: Hashable, Content: View>: View {
    let coordinator: RowGestureCoordinator<ID>
    let id: ID
    let index: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        let h = coordinator.rowHeight
        let isDragging = coordinator.dragId == id
        let shiftY = coordinator.shiftOffset(forIndex: index)

        return GeometryReader { geo in
            HStack(spacing: 0) {
                content()
                    .frame(width: geo.size.width, height: h)
                Button { coordinator.tapTrash(id) } label: {
                    ZStack {
                        Circle().fill(Color.red).frame(width: 40, height: 40)
                        Image(systemName: "trash")
                            .font(.system(size: 17)).foregroundStyle(.white)
                    }
                    .frame(width: coordinator.trashWidth, height: h)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .a11yTapBorder(Circle())
            }
            .offset(x: coordinator.swipeOffset(for: id))
            .frame(width: geo.size.width, height: h, alignment: .leading)
            .clipped()
        }
        .frame(height: h)
        .offset(y: isDragging ? coordinator.dragDY : shiftY)
        .animation(.snappy(duration: 0.2), value: isDragging)
        .animation(isDragging ? nil : .snappy(duration: 0.2), value: shiftY)
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 8, y: 4)
        .zIndex(isDragging ? 1 : 0)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: RowFrameKey<ID>.self,
                                       value: [id: proxy.frame(in: .global)])
            }
        )
    }
}

// MARK: - Recognizer wiring

extension View {
    /// Installs the shared reorder (long-press) + swipe (horizontal pan) recognizers
    /// on the enclosing scroll view and feeds row frames into the coordinator. Apply
    /// once to the VStack that holds the `EditableRow`s.
    func rowGestures<ID: Hashable>(_ coordinator: RowGestureCoordinator<ID>) -> some View {
        self
            .onPreferenceChange(RowFrameKey<ID>.self) { coordinator.rowFrames = $0 }
            .background(
                // Reorder recognizer only when the list supports manual ordering.
                Group {
                    if coordinator.reorderEnabled {
                        ReorderRecognizer(
                            rowFrames: coordinator.rowFrames,
                            onBegan: { coordinator.beginReorder($0) },
                            onChanged: { coordinator.dragChanged($0) },
                            onEnded: { coordinator.endReorder($0) },
                            onCancelled: { coordinator.cancelReorder() }
                        )
                    }
                }
            )
            .background(
                SwipePanRecognizer(
                    rowFrames: coordinator.rowFrames,
                    canStart: { coordinator.dragId == nil && coordinator.canInteract() },
                    onBegan: { coordinator.swipeBegan($0) },
                    onChanged: { coordinator.swipeChanged($0) },
                    onEnded: { coordinator.swipeEnded($0, $1) }
                )
            )
    }
}
