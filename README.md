# soundway

`soundway` is a small Swift package for building a macOS audio bridge that can route input from an interface like the Audient iD14 into BlackHole 2ch.

Current version: `0.6.0`

## Current state

- `soundway`: executable CLI entrypoint
- `SoundwayCore`: reusable package module for bridge configuration and control logic
- `SoundwayCoreTests`: basic package tests
- Live foreground bridge and daemon mode both work
- `soundway status` reports channel counts, routing, frame counts, peaks, callback counts, and render statuses
- Device names and output channel routing can now be overridden from the command line
- The last chosen configuration is saved locally so the daemon and status stay in sync

## Commands

- `make build`
- `make test`
- `make release`
- `make install`
- `swift run soundway --version`
- `swift run soundway devices`
- `swift run soundway status`
- `swift run soundway run`
- `swift run soundway serve`
- `swift run soundway start`
- `swift run soundway stop`

## Install

`make install` builds the release binary and installs it to `$(PREFIX)/bin`, which defaults to `/usr/local/bin`.

## Next parts

- Expand routing into more advanced per-channel mixing or remapping options
- Wrap the daemon in a launch agent for native background startup
- Trim the remaining debug-oriented telemetry once the bridge settles
