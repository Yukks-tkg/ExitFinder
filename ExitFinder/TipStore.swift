import StoreKit
import Observation

@MainActor
@Observable
class TipStore {
    static let shared = TipStore()

    var products: [Product] = []
    var isPurchasing = false
    var purchaseSuccess = false

    private let productIDs = [
        "com.yuki.ExitFinder.tip.small",
        "com.yuki.ExitFinder.tip.medium",
        "com.yuki.ExitFinder.tip.large"
    ]

    init() {
        Task { await loadProducts() }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            print("製品の読み込み失敗: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    purchaseSuccess = true
                case .unverified:
                    break
                }
            default:
                break
            }
        } catch {
            print("購入失敗: \(error)")
        }
    }
}
