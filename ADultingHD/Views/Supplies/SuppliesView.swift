import SwiftUI

struct SuppliesView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var searchText = ""
    @State private var showShoppingList = false

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
                    Spacer()
                    if !dataStore.shoppingList.isEmpty {
                        Button {
                            showShoppingList = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.clipboard")
                                Text("\(dataStore.shoppingList.count)")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.warningRed.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.warningRed)
                        }
                        .buttonStyle(.plain)
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

                        let stock = dataStore.supplyStock[supply] ?? .inStock
                        Menu {
                            ForEach(SupplyStock.allCases, id: \.rawValue) { s in
                                Button {
                                    Task { await dataStore.setSupplyStock(supply, stock: s) }
                                } label: {
                                    Label(s.rawValue, systemImage: s.icon)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: stock.icon)
                                    .font(.caption)
                                Text(stock.rawValue)
                                    .font(.caption)
                            }
                            .foregroundStyle(Theme.supplyStockColor(stock))
                        }
                        .buttonStyle(.plain)

                        Text("\(tasks.count) tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search supplies...")
        .navigationTitle("Supplies")
        .sheet(isPresented: $showShoppingList) {
            ShoppingListView()
        }
    }
}

// MARK: - Shopping List

struct ShoppingListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if dataStore.shoppingList.isEmpty {
                    Text("All stocked up!")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dataStore.shoppingList, id: \.self) { supply in
                        let stock = dataStore.supplyStock[supply] ?? .out
                        HStack {
                            Image(systemName: stock == .out ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(stock == .out ? Theme.warningRed : Theme.streakOrange)
                            Text(supply)
                            Spacer()
                            Button {
                                Task { await dataStore.setSupplyStock(supply, stock: .inStock) }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(Theme.successGreen)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Shopping List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !dataStore.shoppingList.isEmpty && storeManager.isPro {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: shareText)
                    }
                }
            }
        }
    }

    private var shareText: String {
        "Shopping List:\n" + dataStore.shoppingList.map { "- \($0)" }.joined(separator: "\n")
    }
}
