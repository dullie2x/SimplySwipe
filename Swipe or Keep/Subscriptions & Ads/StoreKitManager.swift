import Foundation
import StoreKit
import SwiftUI
import Combine

class StoreKitManager: NSObject, ObservableObject {
    static let shared = StoreKitManager()
    
    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    enum ProductID: String, CaseIterable {
        case monthly = "com.simplyswipe.premium.monthly"
        case yearly = "com.simplyswipe.premium.yearly"
        case lifetime = "com.simplyswipe.premium.lifetime"
        case extraSwipes = "com.simplyswipe.swipes.200"
    }

    private override init() {
        super.init()

        // Restore last-known premium status immediately so canSwipe is correct
        // before the async StoreKit entitlement check completes.
        self.isPremium = UserDefaults.standard.bool(forKey: "cachedIsPremium")

        // Verify entitlements on every launch (separate from the infinite listener).
        Task {
            await requestProducts()
            await checkEntitlements()
        }

        // Start the transaction update listener in its own Task so it never
        // blocks checkEntitlements() above (listenForTransactions never returns).
        Task {
            await listenForTransactions()
        }
    }
    
    // MARK: - Fetch Available Products
    @MainActor
    func requestProducts() async {
        do {
            let storeProducts = try await Product.products(for: ProductID.allCases.map { $0.rawValue })
            self.products = storeProducts
        } catch { _ = error }
    }

    // MARK: - Purchase
    @MainActor
    func purchase(_ productID: ProductID) {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            return
        }

        Task {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .unverified:
                        break
                    case .verified(let transaction):
                        await transaction.finish()
                        handlePurchased(productID: productID)
                    }
                case .userCancelled:
                    break
                case .pending:
                    break
                @unknown default:
                    break
                }
            } catch { _ = error }
        }
    }

    // MARK: - Restore
    func restorePurchases() {
        Task {
            do {
                try await AppStore.sync()
                await checkEntitlements()
            } catch { _ = error }
        }
    }

    // MARK: - Listen for Updates
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await checkEntitlements()
        }
    }

    // MARK: - Entitlement Check
    @MainActor
    func checkEntitlements() async {
        var hasActiveSubscription = false
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                switch transaction.productID {
                case ProductID.monthly.rawValue,
                     ProductID.yearly.rawValue,
                     ProductID.lifetime.rawValue:
                    hasActiveSubscription = true
                default:
                    break
                }
            }
        }

        let wasPremium = self.isPremium
        self.isPremium = hasActiveSubscription
        // Persist so the next launch loads the correct value before async check completes
        UserDefaults.standard.set(hasActiveSubscription, forKey: "cachedIsPremium")

        // Notify UI if premium status changed
        if wasPremium != self.isPremium {
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }

    // MARK: - Handle Purchased Products
    private func handlePurchased(productID: ProductID) {
        switch productID {
        case .monthly, .yearly, .lifetime:
            DispatchQueue.main.async {
                self.isPremium = true
                UserDefaults.standard.set(true, forKey: "cachedIsPremium")
                NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
            }
        case .extraSwipes:
            SwipeData.shared.addExtraSwipes(200)
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }
}
