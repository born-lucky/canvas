# Contributing to Canvas

Canvas is an open framework created by born-lucky. Useful contributions include
engine adapters, undo integration, target picking, tests, and accessibility.

Read `INTEGRATE_WITH_AI.md` and `docs/PROTOCOL.md` before building an adapter.
Keep engine-specific code in a distinct adapter directory and the protocol
independent of renderer/provider choices. Preserve unknown fields.

Open an issue with your engine/tool, version, and proposed capabilities. Pull
requests should document installation, include an actual screenshot, and state
tested platforms. Do not advertise untested adapters as compatible.

Run README tests for shared changes. Include input and rendered checks for UI
changes. Do not include private notes, credentials, game assets, or caches.
Retain creator credit and the MIT notice. Be constructive and respectful.
