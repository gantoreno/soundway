import Foundation

public struct SoundwayConfigurationResolver<Store: SoundwayConfigurationLoading> {
    public let store: Store

    public init(store: Store) {
        self.store = store
    }

    public func resolve(overrides: SoundwayCLIOptions) -> BridgeConfiguration {
        let loadedConfiguration = (try? store.load()) ?? .default
        return overrides.applying(to: loadedConfiguration)
    }
}
