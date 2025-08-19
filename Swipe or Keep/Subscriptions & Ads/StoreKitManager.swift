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
        
        Task {
            await requestProducts()
            await listenForTransactions()
            await checkEntitlements()
        }
    }
    
    // MARK: - Fetch Available Products
    @MainActor
    func requestProducts() async {
        do {
            let storeProducts = try await Product.products(for: ProductID.allCases.map { $0.rawValue })
            self.products = storeProducts
            print("✅ Products loaded: \(storeProducts.map { $0.id })")
        } catch {
            print("❌ Failed to fetch products: \(error)")
        }
    }

    // MARK: - Purchase
    @MainActor
    func purchase(_ productID: ProductID) {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            print("❌ Product \(productID.rawValue) not found.")
            return
        }

        Task {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .unverified:
                        print("⚠️ Purchase unverified.")
                    case .verified(let transaction):
                        await transaction.finish()
                        handlePurchased(productID: productID)
                        print("✅ Purchase successful for \(productID.rawValue)")
                    }
                case .userCancelled:
                    print("🛑 Purchase cancelled by user.")
                case .pending:
                    print("⏳ Purchase pending.")
                @unknown default:
                    print("❓ Unknown purchase result.")
                }
            } catch {
                print("❌ Purchase error: \(error)")
            }
        }
    }

    // MARK: - Restore
    func restorePurchases() {
        Task {
            do {
                try await AppStore.sync()
                await checkEntitlements()
            } catch {
                print("❌ Restore failed: \(error)")
            }
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
                NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
            }
        case .extraSwipes:
            SwipeData.shared.addExtraSwipes(200)
            NotificationCenter.default.post(name: .swipeCountChanged, object: nil)
        }
    }
}
