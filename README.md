# soundway

`soundway` is a small Swift package for building a macOS audio bridge that can route input from an interface like the Audient iD14 MKII into BlackHole 2ch.

## Current shape

- `soundway`: executable CLI entrypoint
- `SoundwayCore`: reusable package module for bridge configuration and control logic
- `SoundwayCoreTests`: basic package tests

## Commands

- `swift run soundway status`
- `swift run soundway start`
- `swift run soundway stop`

## Next step

The next layer will be the real Core Audio bridge implementation and a background launch agent.
