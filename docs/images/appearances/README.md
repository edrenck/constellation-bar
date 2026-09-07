# Implementation previews

Generated from the v0.3.0 AppKit views with deterministic fixture data. Each board shows Rail, Islands, Compact and a CPU inspector. The native light/dark boards use the actual opaque accessibility fallback: offscreen bitmaps cannot capture WindowServer Liquid Glass optics. The real native materials were separately checked in the running app on this Mac, including both native styles in light/dark and a live CPU inspector. These are implementation previews; original image-generated design proposals remain in docs/design/appearance-concepts.

Validation: 22 tests passed; all five appearances were switched live; CPU inspector updates and Escape dismissal verified; universal arm64/x86_64 build and ad-hoc code signature verified. The 14/15 vibrancy fallback and macOS 27 runtime have not been run on separate machines in this session.
