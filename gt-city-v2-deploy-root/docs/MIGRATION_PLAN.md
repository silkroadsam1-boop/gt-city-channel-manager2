# Non-destructive migration plan

## Phase 0 — protect production
1. Keep the existing Render service running.
2. Download and securely back up `data.json` before any deployment.
3. Create a separate PostgreSQL **staging** database. Do not point production at it yet.
4. Record current property IDs, owner IDs, reservation IDs, channel connections and iCal URLs.

## Phase 1 — import reference data
1. Create one organization for GT City.
2. Import users and preserve role/owner relationships.
3. Import each current property as a `properties` row.
4. For a separately listed apartment, create one `units` row and map its external listing in `UNIT` mode.
5. For a hotel/building room category, create a `room_types` row and one `units` row per physical room; map the OTA listing in `ROOM_TYPE` mode.
6. Store legacy numeric IDs in a migration cross-reference table or a controlled import manifest; do not assume UUIDs equal old IDs.

## Phase 2 — reservations
1. Import existing reservations with their original check-in/check-out dates as local `DATE` values.
2. Preserve original source/channel label and notes.
3. Attach external booking references only when a real external ID is available.
4. Do not convert an iCal availability block into a named guest booking. Mark it as an availability block with unknown guest fields, or retain it in a separate legacy-block table until the product model is finalized.
5. Compare reservation counts, date ranges, statuses and totals against `data.json`.

## Phase 3 — shadow operation
1. Run the v2 backend in staging with read-only import from the legacy data.
2. Compare calendars and reservation lists for at least one full sync cycle.
3. Test two simultaneous booking events for the same unit; only one may allocate.
4. Test duplicate webhook delivery, modification, cancellation, room-type allocation and timezone/date boundaries.
5. Obtain operator sign-off before enabling outbound availability updates.

## Phase 4 — controlled cutover
1. Freeze writes briefly and take a final backup.
2. Run a final delta import and verify counts.
3. Switch traffic only after rollback steps are tested.
4. Keep the old `data.json` backup immutable for rollback and audit.
