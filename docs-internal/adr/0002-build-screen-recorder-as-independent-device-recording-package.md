# Build Screen Recorder as an Independent Device Recording Package

Flutter Pilot may later consume device video recordings, but the recording
capability itself will be built as an independent `screen_recorder` Dart
package rather than as part of the Flutter Pilot Runtime Adapter.

The package owns device-level recording concepts:

- a Recording Device selected through recording backend discovery
- a Recording Session started with `startRecord`
- explicit `stopRecord` and discard behavior
- a stop result that returns the final saved video path

The core API is programmatic first. A thin CLI may exist for manual smoke tests
and interactive use, but it must call the same library API instead of owning the
recording behavior.

Recording Device discovery follows recording backends rather than Flutter
Runtime Target discovery. The default resolver searches backends in a fixed
order and stops at the first match:

1. Android devices through Android Debug Bridge
2. iOS simulators through `xcrun simctl`
3. physical iOS devices through native AVFoundation/CoreMediaIO screen capture
   discovery

Device selectors support exact id/name matching and case-insensitive name prefix
matching. A platform filter may narrow discovery to one backend family, but the
first version does not expose configurable backend priority.

Each backend uses its native recording format. Android writes `.mp4`; iOS
simulators and physical iOS devices write `.mov`. Callers provide an output
directory and an output name without an extension; the backend chooses the final
extension, and `stopRecord` returns the final path. Existing output files fail
by default unless overwrite is explicitly requested.

Physical iOS recording will use an in-package Swift helper based on the
CMIO/AVFoundation approach already validated in the local `ios_screen`
prototype. The `screen_recorder` package will not shell out to that prototype or
depend on files outside its own package.

This keeps Flutter Pilot's Runtime Target model focused on Flutter app runtime
communication through `mcp_flutter`, while `screen_recorder` remains a
device-level visual capture package that can later be integrated by Flutter
Pilot or other tools.
