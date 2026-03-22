<p align="center">
  <img src="assets/soundway.png" alt="soundway logo" width="180" />
</p>

# Soundway

A simple macOS audio interface routing utility.

## What it does

- Bridges live audio from your interface into BlackHole
- Lets Discord and similar apps use BlackHole as their input
- Supports configurable device names, channel routing, and saved config
- Includes a deterministic, testable bridge core

## Install

Build and install the release binary with:

```bash
make install
```

That installs `soundway` to `$(PREFIX)/bin`, which defaults to `/usr/local/bin`.

## Quick Start

Start with the defaults:

```bash
soundway run
```

Or start the background daemon:

```bash
soundway start
```

Then point Discord at BlackHole:

```bash
soundway status
```

## Configuration

You can override the device names and routing from the command line:

```bash
soundway run \
  --input-device "Audient iD14" \
  --output-device "BlackHole 2ch" \
  --route 3,4
```

Routing is 1-based and maps output channels in order. For example, `--route 3,4` means:

- BlackHole channel 1 receives input channel 3
- BlackHole channel 2 receives input channel 4

The last chosen configuration is saved to:

```text
~/Library/Application Support/soundway/config.json
```

## Commands

| Command              | Description                          |
| -------------------- | ------------------------------------ |
| `make build`         | Build the debug binary               |
| `make test`          | Run the test suite                   |
| `make release`       | Build an optimized release binary    |
| `make install`       | Build and install the release binary |
| `soundway --version` | Print the current version            |
| `soundway devices`   | List detected audio devices          |
| `soundway status`    | Show bridge state and telemetry      |
| `soundway run`       | Run the bridge in the foreground     |
| `soundway serve`     | Run the daemon mode directly         |
| `soundway start`     | Start the bridge in the background   |
| `soundway stop`      | Stop the running bridge              |

## Current State

- Foreground and background bridge modes both work
- `soundway status` reports routing, frame counts, peaks, callback counts, and render statuses
- The bridge core is covered by deterministic unit tests
- Core Audio remains isolated behind a thin adapter

## Testing

Run the full suite with:

```bash
make test
```

## Roadmap

- More advanced per-channel mixing and remapping
- More daemon lifecycle integration tests
- LaunchAgent packaging for native background startup
- Trim debug-oriented telemetry once the bridge settles
