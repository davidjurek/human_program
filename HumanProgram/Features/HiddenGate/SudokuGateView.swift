import SwiftUI

// Full-screen hidden gate. Black background, no normal app chrome.
// A 4×4 Latin-square puzzle. Auto-detects correct solution and fades to game.
struct SudokuGateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cells: [[Int?]] = Self.initialCells
    @State private var showGame = false
    @State private var fadeOut = false

    // Given cells (immutable): positions that are pre-filled
    private static let givenPositions: Set<String> = [
        "0,0", "0,2", "1,1", "1,3", "2,0", "2,2", "3,1", "3,3"
    ]

    // Puzzle: valid 4×4 Latin square
    // Solution:  Row 0: 2,1,4,3   Row 1: 4,3,2,1   Row 2: 1,4,3,2   Row 3: 3,2,1,4
    private static let solution: [[Int]] = [
        [2, 1, 4, 3],
        [4, 3, 2, 1],
        [1, 4, 3, 2],
        [3, 2, 1, 4],
    ]
    private static let initialCells: [[Int?]] = {
        var grid: [[Int?]] = Array(repeating: Array(repeating: nil, count: 4), count: 4)
        for (r, row) in solution.enumerated() {
            for (c, val) in row.enumerated() {
                if givenPositions.contains("\(r),\(c)") {
                    grid[r][c] = val
                }
            }
        }
        return grid
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Dismiss button
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(16)
                    }
                    Spacer()
                }

                Spacer()

                // Grid
                VStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { col in
                                CellView(
                                    value: cells[row][col],
                                    isGiven: Self.givenPositions.contains("\(row),\(col)"),
                                    onTap: { cycleCellValue(row: row, col: col) }
                                )
                            }
                        }
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
        }
        .opacity(fadeOut ? 0 : 1)
        .animation(.easeInOut(duration: 0.8), value: fadeOut)
        .fullScreenCover(isPresented: $showGame) {
            GameContainerView()
        }
    }

    private func cycleCellValue(row: Int, col: Int) {
        guard !Self.givenPositions.contains("\(row),\(col)") else { return }
        let current = cells[row][col]
        cells[row][col] = current.map { $0 % 4 + 1 } ?? 1
        checkSolution()
    }

    private func checkSolution() {
        for row in 0..<4 {
            for col in 0..<4 {
                guard cells[row][col] == Self.solution[row][col] else { return }
            }
        }
        // Solved!
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        fadeOut = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            showGame = true
            fadeOut = false
        }
    }
}

struct CellView: View {
    let value: Int?
    let isGiven: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isGiven ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .frame(width: 64, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                if let v = value {
                    Text("\(v)")
                        .font(.system(size: 24, weight: isGiven ? .medium : .light))
                        .foregroundStyle(isGiven ? .white : .white.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isGiven)
    }
}
