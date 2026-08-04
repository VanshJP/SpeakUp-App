import Foundation
import Observation
import StoreKit

/// StoreKit 2 front-door for the single non-consumable Lifetime purchase.
///
/// Responsibilities, in the order the App Store exercises them: load the
/// product, purchase it, verify the signed transaction, keep `EntitlementStore`
/// in step with `Transaction.currentEntitlements`, listen for out-of-band
/// updates (Ask to Buy approvals, purchases made on another device, refunds and
/// revocations), and restore on a fresh install.
@MainActor
@Observable
final class PurchaseService {
    static let shared = PurchaseService()

    // MARK: - State

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PurchasePhase: Equatable {
        case idle
        case purchasing
        case restoring
        /// Ask to Buy or SCA — the transaction may land minutes later via
        /// `Transaction.updates`.
        case pendingApproval
        case purchased
        case restored
        case cancelled
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var loadState: LoadState = .idle
    private(set) var phase: PurchasePhase = .idle

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {}

    // MARK: - Display

    /// Localized price from StoreKit, or the planned price while loading so the
    /// paywall never renders a blank button.
    var displayPrice: String {
        product?.displayPrice ?? LifetimeProduct.fallbackDisplayPrice
    }

    var isBusy: Bool {
        phase == .purchasing || phase == .restoring
    }

    var errorMessage: String? {
        switch phase {
        case .failed(let message): return message
        default:
            if case .failed(let message) = loadState { return message }
            return nil
        }
    }

    // MARK: - Lifecycle

    /// Call once at launch. Starts the transaction listener before any product
    /// load so a transaction that completes during startup is never dropped.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handle(update, finishing: true)
            }
        }

        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        loadState = .loading
        do {
            let products = try await Product.products(for: [LifetimeProduct.identifier])
            guard let match = products.first(where: { $0.id == LifetimeProduct.identifier }) else {
                loadState = .failed(PurchaseError.productUnavailable.localizedDescription)
                return
            }
            product = match
            loadState = .loaded
        } catch {
            loadState = .failed(PurchaseError.loadFailed(error).localizedDescription)
        }
    }

    /// Re-reads the App Store's answer for what this Apple Account owns. Cheap,
    /// offline-tolerant (StoreKit serves a cached receipt), and safe to call on
    /// every foreground.
    func refreshEntitlement() async {
        var owned = false
        var purchasedAt: Date?

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == LifetimeProduct.identifier else { continue }
            guard transaction.revocationDate == nil else { continue }
            owned = true
            purchasedAt = transaction.purchaseDate
        }

        EntitlementStore.shared.apply(isLifetime: owned, purchasedAt: purchasedAt)
    }

    // MARK: - Purchase

    @discardableResult
    func purchase() async -> Bool {
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            phase = .failed(PurchaseError.productUnavailable.localizedDescription)
            return false
        }

        phase = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let granted = await handle(verification, finishing: true)
                phase = granted ? .purchased : .failed(PurchaseError.unverified.localizedDescription)
                return granted

            case .userCancelled:
                phase = .cancelled
                return false

            case .pending:
                // Ask to Buy / Strong Customer Authentication. The transaction
                // arrives later on `Transaction.updates`.
                phase = .pendingApproval
                return false

            @unknown default:
                phase = .failed(PurchaseError.unknownResult.localizedDescription)
                return false
            }
        } catch {
            phase = .failed(PurchaseError.purchaseFailed(error).localizedDescription)
            return false
        }
    }

    /// Restore for a reinstall or a second device. `AppStore.sync()` forces a
    /// receipt refresh (and may prompt for the Apple Account password), then the
    /// entitlement re-read decides the answer.
    @discardableResult
    func restore() async -> Bool {
        phase = .restoring
        do {
            try await AppStore.sync()
        } catch {
            // A cancelled password prompt is not an error worth shouting about,
            // but the entitlement re-read below still runs.
            await refreshEntitlement()
            if EntitlementStore.shared.isLifetime {
                phase = .restored
                return true
            }
            phase = .failed(PurchaseError.restoreFailed(error).localizedDescription)
            return false
        }

        await refreshEntitlement()
        let owned = EntitlementStore.shared.isLifetime
        phase = owned ? .restored : .failed(PurchaseError.nothingToRestore.localizedDescription)
        return owned
    }

    func clearPhase() {
        phase = .idle
    }

    // MARK: - Transaction handling

    /// Applies one signed transaction. Returns whether it granted entitlement.
    ///
    /// Unverified transactions are finished but never granted — leaving them
    /// unfinished would have StoreKit redeliver them on every launch forever.
    @discardableResult
    private func handle(
        _ result: VerificationResult<StoreKit.Transaction>,
        finishing: Bool
    ) async -> Bool {
        switch result {
        case .verified(let transaction):
            guard transaction.productID == LifetimeProduct.identifier else {
                if finishing { await transaction.finish() }
                return false
            }
            // Refund or family-sharing revocation.
            if transaction.revocationDate != nil {
                if finishing { await transaction.finish() }
                await refreshEntitlement()
                return false
            }
            EntitlementStore.shared.apply(isLifetime: true, purchasedAt: transaction.purchaseDate)
            if finishing { await transaction.finish() }
            return true

        case .unverified(let transaction, _):
            if finishing {
                await transaction.finish()
            }
            return false
        }
    }
}

// MARK: - Errors

enum PurchaseError: LocalizedError {
    case productUnavailable
    case loadFailed(Error)
    case purchaseFailed(Error)
    case restoreFailed(Error)
    case nothingToRestore
    case unverified
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "Big Talk Lifetime isn't available from the App Store right now. Try again in a moment."
        case .loadFailed:
            return "Couldn't reach the App Store. Check your connection and try again."
        case .purchaseFailed(let error):
            return "The purchase didn't go through. \(error.localizedDescription)"
        case .restoreFailed:
            return "Couldn't restore your purchase. Check your connection and try again."
        case .nothingToRestore:
            return "No previous purchase found for this Apple Account."
        case .unverified:
            return "The App Store couldn't verify that purchase. Nothing was unlocked and you have not been charged twice."
        case .unknownResult:
            return "The App Store returned an unexpected result. Try again."
        }
    }
}
