import StoreKit
import os

private let logger = Logger(subsystem: "net.shadowpuppet.ADultingHD", category: "StoreManager")

@Observable
@MainActor
final class StoreManager {
    static let proProductID = "net.shadowpuppet.ADultingHD.pro"
    static let freeCustomTaskLimit = 5

    static let freeAchievementIDs: Set<String> = [
        "first_task", "ten_tasks", "streak_3", "early_bird", "five_in_day"
    ]

    private(set) var isPro = false
    private(set) var proProduct: Product?
    private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState {
        case idle, purchasing, purchased, failed(String)
    }

    var isPurchasing: Bool {
        if case .purchasing = purchaseState { return true }
        return false
    }

    var failureMessage: String? {
        if case .failed(let msg) = purchaseState { return msg }
        return nil
    }

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
    }

    private var isDemoMode = false

    func canCreateCustomTask(existingCount: Int) -> Bool {
        isPro || existingCount < Self.freeCustomTaskLimit
    }

    #if DEBUG
    func enableDemoMode() {
        isPro = true
        isDemoMode = true
    }
    #endif

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            proProduct = products.first
            logger.info("Loaded product: \(self.proProduct?.displayName ?? "none")")
        } catch {
            logger.error("Failed to load products: \(error)")
        }
        await checkEntitlement()
    }

    func purchase() async {
        guard let product = proProduct else { return }
        purchaseState = .purchasing

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verification.payloadValue
                await transaction.finish()
                isPro = true
                purchaseState = .purchased
                logger.info("🎉 Pro unlocked")
            case .pending:
                purchaseState = .idle
                logger.info("⏳ Purchase pending")
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed("Purchase failed. Please try again.")
            logger.error("Purchase error: \(error)")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            logger.error("Restore failed: \(error)")
        }
        await checkEntitlement()
    }

    private func checkEntitlement() async {
        if isDemoMode { return }
        guard let result = await Transaction.latest(for: Self.proProductID) else {
            isPro = false
            return
        }
        guard let transaction = try? result.payloadValue,
              transaction.revocationDate == nil else {
            isPro = false
            return
        }
        isPro = true
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    await self?.checkEntitlement()
                }
            }
        }
    }
}
