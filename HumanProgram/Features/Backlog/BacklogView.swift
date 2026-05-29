import SwiftUI
import SwiftData

struct BacklogView: View {
    @Environment(\.modelContext) private var context
    // Fetch all items; filter to .backlog in memory.
    // SwiftData #Predicate enum comparisons can be unreliable — filtering in
    // memory is safe and correct for a list this size.
    @Query(sort: \BacklogItem.createdAt, order: .reverse)
    private var allItems: [BacklogItem]
    private var items: [BacklogItem] { allItems.filter { $0.status == .backlog } }

    @State private var showAddAlert = false
    @State private var newTitle = ""

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            if items.isEmpty {
                Text("No items in backlog")
                    .foregroundStyle(AppColors.textTertiary)
                    .font(AppTypography.caption())
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            BacklogRowView(item: item, context: context)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .navigationTitle("Backlog")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddAlert = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Task", isPresented: $showAddAlert) {
            TextField("Title", text: $newTitle)
            Button("Add") {
                guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let item = BacklogItem(title: newTitle)
                context.insert(item)
                newTitle = ""
            }
            Button("Cancel", role: .cancel) { newTitle = "" }
        }
    }
}

struct BacklogRowView: View {
    let item: BacklogItem
    let context: ModelContext

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AppTypography.taskTitle())
                    .foregroundStyle(AppColors.textPrimary)
                if let date = item.assignedDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(AppTypography.taskMeta())
                        .foregroundStyle(AppColors.accent)
                }
            }
            Spacer()
            Button {
                item.status = .done
                item.updatedAt = Date()
                try? context.save()
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
