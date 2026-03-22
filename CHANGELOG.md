# Changelog

## 0.5.0

- Made the Audient iD14 -> BlackHole bridge actually move audio end to end.
- Fixed AUHAL render failures by matching the callback contract more closely and giving the HAL a larger frame budget.
- Added live telemetry for captured/rendered frames, peaks, callback counts, and render status codes.
- Kept device discovery channel-aware so the bridge reflects the real hardware layout instead of assuming stereo.
- Cleaned up the bridge defaults so the current repo state matches the working setup.

## 0.4.0

- Added a local bridge daemon protocol.
- Wired `soundway start`, `soundway stop`, and `soundway status` to a shared control surface.
- Added a `serve` mode for the background daemon.

## 0.3.0

- Added a first-pass Core Audio bridge engine.
- Added `soundway run` for foreground bridge execution.
- Kept device discovery and CLI status reporting in place.

## 0.2.0

- Added Core Audio device discovery for installed audio hardware.
- Added `soundway devices` and improved `soundway status` to resolve the Audient and BlackHole endpoints.

## 0.1.0

- Initial Swift package scaffold.
- Added the basic CLI shell, bridge configuration, and tests.
