import WalletProtocol
import Wallet

struct WalletSDKWrapper: WalletServiceProtocol {
    static let instance = WalletSDKWrapper()
    
    /// Use ``instance`` to obtain a reference.
    private init() {
        // the `WalletSDKWrapper` is meant to represent an instance of the WalletSDK
        // when using its static function. Thus, using a `init` is moot.
    }
    
    func delete() async throws(WalletStoreError) -> [WalletStoreError] {
        try await WalletSDK.delete()
    }
    
    func isEmpty() async -> Bool {
        return await WalletSDK.isEmpty()
    }
}
