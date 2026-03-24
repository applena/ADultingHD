import SwiftUI

struct SuppliesView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var searchText = ""

    private var sortedSupplies: [(String, [HouseholdTask])] {
        let all = dataStore.allSupplies
        let filtered: [(String, [HouseholdTask])]
        if searchText.isEmpty {
            filtered = all.map { ($0.key, $0.value) }
        } else {
            filtered = all.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
                .map { ($0.key, $0.value) }
        }
        return filtered.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "cart.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("\(sortedSupplies.count) supplies")
                            .font(.headline)
                        Text("across \(dataStore.activeTasks.count) active tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(sortedSupplies, id: \.0) { supply, tasks in
                DisclosureGroup {
                    ForEach(tasks) { task in
                        HStack(spacing: 8) {
                            Image(systemName: task.category.icon)
                                .foregroundStyle(Theme.categoryColor(task.category))
                                .frame(width: 20)
                            Text(task.name)
                                .font(.subheadline)
                            Spacer()
                            Text(task.frequency.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    HStack {
                        Text(supply)
                            .font(.body)
                        Spacer()
                        Text("\(tasks.count) tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search supplies...")
        .navigationTitle("Supplies")
    }
}
