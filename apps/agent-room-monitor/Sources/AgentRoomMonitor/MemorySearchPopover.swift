import SwiftUI
import RoomKit

struct MemorySearchPopover: View {
    @Environment(AppModel.self) private var app
    @Bindable var board: BoardModel
    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var results: [RoomMemorySearchResult] = []
    @State private var isSearching: Bool = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView
            searchFieldView
            contentView
        }
        .padding(14)
        .frame(width: 440, height: 380)
        .background(VColor.sea1)
    }

    private var headerView: some View {
        HStack {
            Text(app.L(.memorySearchTitle))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var searchFieldView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)
            TextField(app.L(.memorySearchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { triggerSearch() }
                .onChange(of: query) { _, _ in triggerSearch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var contentView: some View {
        if results.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching {
            emptyStateView
        } else {
            resultsListView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Color.secondary)
            Text(app.L(.memorySearchEmpty))
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(results) { item in
                    resultRow(item)
                }
            }
        }
    }

    private func resultRow(_ item: RoomMemorySearchResult) -> some View {
        Button {
            selectResult(item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.roomID)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(VColor.accent)
                    Text(item.fileName)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Text(String(format: app.L(.memorySearchScore), Int64(item.score)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VColor.exec)
                }
                Text(item.matchedText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.8, green: 0.85, blue: 0.9))
                    .lineLimit(2)
            }
            .padding(8)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func selectResult(_ item: RoomMemorySearchResult) {
        board.selectTenant(item.tenant)
        if let node = board.world.find(item.roomID) {
            board.selected = node
        }
        isPresented = false
    }

    private func triggerSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let tenant = board.selectedTenantID ?? "personal"
        searchTask = Task.detached(priority: .userInitiated) {
            let indexer = RoomMemoryIndexer()
            let found = indexer.search(query: q, tenant: tenant)
            await MainActor.run {
                self.results = found
                self.isSearching = false
            }
        }
    }
}
