import SwiftUI
import SwiftData

struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Routine.title) private var routines: [Routine]
    @State private var showAddAlert = false
    @State private var newTitle = ""

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            if routines.isEmpty {
                Text("No routines yet")
                    .foregroundStyle(AppColors.textTertiary)
                    .font(AppTypography.caption())
            } else {
                List(routines) { routine in
                    NavigationLink(destination: RoutineDetailView(routine: routine)) {
                        Text(routine.title)
                            .font(AppTypography.taskTitle())
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddAlert = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New Routine", isPresented: $showAddAlert) {
            TextField("Title", text: $newTitle)
            Button("Add") {
                guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let routine = Routine(title: newTitle)
                context.insert(routine)
                newTitle = ""
            }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
    }
}

struct RoutineDetailView: View {
    let routine: Routine
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            if routine.items.isEmpty {
                Text("No items in this routine")
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                List(routine.items.sorted { $0.sortOrder < $1.sortOrder }) { item in
                    Text(item.text).font(AppTypography.taskTitle())
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(routine.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
