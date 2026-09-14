# Local Outlook calendar cache — format notes

The production adapter is in `Sources/ConstellationBar/Widgets/Calendar/OutlookCacheReader.swift`, with a bounded codec and user-selected read-only folder bookmark. It was verified with Outlook 16.112.4 (Gmail) on September 14, 2026. No user cache or extracted record is included in the repository.

## Active storage directory

The file begins with `Nostromo`, version `i`. The 32-bit committed-directory selector is at `0x2c` (0 or 1). Descriptors at `0x58` and `0x78` hold a 64-bit directory file offset and a CRC-32 at descriptor +24. The slot count is the 32-bit value at `0x48`. The observed count is 65,521, but the reader obtains it from the header. Each slot is five bytes: a 32-bit address in 256-byte units, plus an allocation-length byte. An address of zero is unused; bit zero in its address unit marks a deleted slot. The checksum covers exactly `slotCount * 5` bytes, excluding alignment padding. Both directory checksums matched live snapshots.

Only blocks referenced by the committed, checksum-valid directory are eligible. The directory excludes every title-bearing version of the removed integration-test event. Scanning all checksum-valid blocks does not: old versions remain on disk.

The compressed block header uses two CRC-32 checksums and raw LZ4. Type 8 has a 40-byte header; type 16 has a **48-byte** header (its identity occupies 16 bytes). The latter distinction was established by exact decompression and payload CRC matches across all observed type-16 blocks. Type-16 storage metadata is validated but not interpreted as calendar records.

Container research reference: https://github.com/securized/hxstore-reverse-engineering/blob/main/SPEC.md. The independently implemented codec agrees with its type-8 framing. That research's raw recovery/deduplication approach and sidecar directory are not used to select live calendar records.

## Calendar frames

Active object/index pages contain serialized format-5 frames. Their byte length appears before the format marker and again at the start of the record. A fixed-schema-size field and an object-type field further constrain recognition. Only complete supported frames are accepted. Current schema identifiers are 1,175 for AppointmentHeader (type 0x6b) and 977 for CalendarData (type 0x68).

Offsets below are relative to the record's repeated length field and apply only to those schema sizes:

| Offset | Meaning |
|---|---|
| 6 | 16-bit object type |
| 8 | 64-bit occurrence key; zero for standalone events |
| 16 | 64-bit object identity |
| 100 | First variable-pool byte count |
| 220 | Appointment calendar identity |
| 628 / 636 | Appointment start/end, UTC .NET ticks |
| 1084 | Appointment subject string descriptor |
| 1142, bit 3 | Appointment all-day flag |
| 776 | Calendar display-name string descriptor |

Strings use an offset/length pair. The first variable pool begins at `fixedSchemaSize - 4`. The length's high bit selects the second pool, which follows the first pool. Remaining length bits count bytes, including the UTF-16LE terminator. Bounds and encoding are validated before reading. All-day UTC civil dates are converted to local civil dates rather than shifted as timed events.

Identity includes both object ID and occurrence key. Recurring occurrences share their series ID, so deduplicating on object ID alone loses occurrences. Live duplicate frames must agree on title/start/end. No recurrence expansion is guessed from a title or timestamp; Outlook materializes the occurrences used by the reader.

Outlook's installed HxCore headers corroborate the calendar/appointment object types and named fields. Vendor headers or executable code are not redistributed or loaded by the integration. Other schema sizes fail with an unsupported-cache message. Locations, attendees, meeting URLs, and other optional properties remain unimplemented for the cache adapter.

## Verification

The user-authorized temporary event was created, moved by one hour, then deleted in Outlook. Raw recovery retained its original and modified values after deletion. The active-directory reader excludes it. The production decoder returned 32 events in the agenda window and matched the titles and times shown by Outlook. The actual bar displayed the current event, and its calendar panel matched timed and recurring events on multiple days. After restarting the final universal build, the saved folder grant restored automatically and the panel showed the same events with an Open in Outlook action. The full suite passed 93 tests; 18 focused tests passed again after the final UI and disconnect-race fixes. Temporary extracted calendar records and the investigation bookmark were removed after verification.

`OutlookCacheTests` uses only synthetic bytes to cover committed directory selection, stale/deleted records, edits, corruption, unsupported schemas, conflicting duplicates, Unicode, recurring occurrence identities, profile namespacing and all-day dates. Folder bookmarks are scoped to the receiving app's identity and are not copied from the investigation helper into the production app.
