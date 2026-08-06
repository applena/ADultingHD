import SwiftUI

enum SupplySortMode: String, CaseIterable {
    case byStatus = "By Status"
    case byName = "A-Z"
    case byCategory = "By Room"
}

struct SuppliesView: View {
    @Environment(DataStore.self) private var dataStore
    @State private var searchText = ""
    @State private var sortMode: SupplySortMode = .byStatus

    private typealias SupplyEntry = (name: String, tasks: [HouseholdTask], stock: SupplyStock)

    private var allEntries: [SupplyEntry] {
        let stockMap = dataStore.supplyStock
        let all = dataStore.allSupplies
        let entries: [SupplyEntry]
        if searchText.isEmpty {
            entries = all.map { (name: $0.key, tasks: $0.value, stock: stockMap[$0.key] ?? .inStock) }
        } else {
            entries = all
                .filter { $0.key.localizedCaseInsensitiveContains(searchText) }
                .map { (name: $0.key, tasks: $0.value, stock: stockMap[$0.key] ?? .inStock) }
        }
        return entries.sorted { $0.name < $1.name }
    }

    private var partitionedByStatus: (attention: [SupplyEntry], inStock: [SupplyEntry]) {
        var attention: [SupplyEntry] = []
        var inStock: [SupplyEntry] = []
        for entry in allEntries {
            if entry.stock == .inStock {
                inStock.append(entry)
            } else {
                attention.append(entry)
            }
        }
        attention.sort { $0.stock.sortOrder < $1.stock.sortOrder }
        return (attention, inStock)
    }

    private var suppliesByCategory: [(TaskCategory, [SupplyEntry])] {
        var grouped: [TaskCategory: [SupplyEntry]] = [:]
        for entry in allEntries {
            let cat = entry.tasks.first?.category ?? .general
            grouped[cat, default: []].append(entry)
        }
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    var body: some View {
        List {
            Section {
                LandingHeader(
                    eyebrow: dataStore.activeHousehold.name,
                    title: "Keep the quest kit stocked",
                    subtitle: "\(allEntries.count) supplies across \(dataStore.activeTasks.count) active tasks.",
                    icon: "basket.fill",
                    color: Theme.coral
                )
                .accessibilityIdentifier("supplies-root-header")
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        MetricPill(
                            title: "Low",
                            value: "\(dataStore.lowSupplyCount)",
                            icon: "exclamationmark.triangle.fill",
                            color: Theme.streakOrange
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        MetricPill(
                            title: "Out",
                            value: "\(dataStore.outOfStockSupplyCount)",
                            icon: "xmark.circle.fill",
                            color: Theme.warningRed
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text("Group supplies")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Sort supplies", selection: $sortMode) {
                            ForEach(SupplySortMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if !dataStore.shoppingList.isEmpty {
                        NavigationLink {
                            ShoppingListView()
                        } label: {
                            HStack {
                                Label("Open Shopping List", systemImage: "list.bullet.clipboard.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(dataStore.shoppingList.count)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.warningRed.opacity(0.15), in: Capsule())
                            }
                            .foregroundStyle(Theme.warningRed)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("supplies-shopping-list-button")
                        .accessibilityLabel("Shopping list")
                        .accessibilityValue("\(dataStore.lowSupplyCount) low, \(dataStore.outOfStockSupplyCount) out of stock")
                    }
                }
            }

            switch sortMode {
            case .byStatus:
                statusGroupedContent
            case .byName:
                alphabeticalContent
            case .byCategory:
                categoryGroupedContent
            }
        }
        .rootTabScrollClearance()
        #if os(macOS)
        .listStyle(.inset)
        .searchable(text: $searchText, prompt: "Search supplies...")
        .navigationTitle("Supplies")
        #else
        .scrollContentBackground(.hidden)
        .background { ScreenBackground() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search supplies...", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search supplies")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 280)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        #endif
        .rootTabNavigation("Supplies")
    }

    // MARK: - By Status

    @ViewBuilder
    private var statusGroupedContent: some View {
        let partitioned = partitionedByStatus
        if !partitioned.attention.isEmpty {
            Section {
                ForEach(partitioned.attention, id: \.name) { entry in
                    SupplyRow(supply: entry.name, tasks: entry.tasks, stock: entry.stock, showStock: true)
                }
            } header: {
                HStack {
                    Text("Needs Attention")
                    Spacer()
                    Text("\(partitioned.attention.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            ForEach(partitioned.inStock, id: \.name) { entry in
                SupplyRow(supply: entry.name, tasks: entry.tasks, stock: entry.stock, showStock: false)
            }
        } header: {
            HStack {
                Text("In Stock")
                Spacer()
                Text("\(partitioned.inStock.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Alphabetical

    private var alphabeticalContent: some View {
        ForEach(allEntries, id: \.name) { entry in
            SupplyRow(supply: entry.name, tasks: entry.tasks, stock: entry.stock, showStock: entry.stock != .inStock)
        }
    }

    // MARK: - By Category

    @ViewBuilder
    private var categoryGroupedContent: some View {
        ForEach(suppliesByCategory, id: \.0) { category, supplies in
            Section {
                ForEach(supplies, id: \.name) { entry in
                    SupplyRow(supply: entry.name, tasks: entry.tasks, stock: entry.stock, showStock: entry.stock != .inStock)
                }
            } header: {
                HStack {
                    Label(category.rawValue, systemImage: category.icon)
                        .foregroundStyle(Theme.categoryColor(category))
                    Spacer()
                    Text("\(supplies.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Supply Row

struct SupplyRow: View {
    @Environment(DataStore.self) private var dataStore
    let supply: String
    let tasks: [HouseholdTask]
    let stock: SupplyStock
    let showStock: Bool

    var body: some View {
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
            HStack(spacing: 8) {
                Text(supply)
                    .font(.body)

                if showStock {
                    Text(stock.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.supplyStockColor(stock).opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.supplyStockColor(stock))
                }

                Spacer()

                Menu {
                    ForEach(SupplyStock.allCases, id: \.rawValue) { s in
                        Button {
                            Task { await dataStore.setSupplyStock(supply, stock: s) }
                        } label: {
                            Label(s.rawValue, systemImage: s.icon)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)

                Text("\(tasks.count) tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Supply Stock Sort Order

extension SupplyStock {
    var sortOrder: Int {
        switch self {
        case .out: 0
        case .low: 1
        case .inStock: 2
        }
    }
}

// MARK: - Shopping List

struct ShoppingListView: View {
    @Environment(DataStore.self) private var dataStore
    @Environment(StoreManager.self) private var storeManager

    var body: some View {
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
            if !dataStore.shoppingList.isEmpty && storeManager.isPro {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText)
                }
            }
        }
    }

    private var shareText: String {
        "Shopping List:\n" + dataStore.shoppingList.map { "- \($0)" }.joined(separator: "\n")
    }
}
