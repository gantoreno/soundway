import Foundation

/// Resolves the effective configuration for a run.
public struct SoundwayConfigurationResolver<Store: SoundwayConfigurationLoading> {
    public let store: Store

    public init(store: Store) {
        self.store = store
    }

    public func resolve(overrides: SoundwayCLIOptions) -> BridgeConfiguration {
        // CLI flags win for the current run; saved config is the fallback, then defaults.
        let loadedConfiguration = (try? store.load()) ?? .default
        return overrides.applying(to: loadedConfiguration)
    }
}
