# GT City v2 API contract (draft)

All endpoints are organization-scoped. Authentication must be enforced server-side. Owner users may only access properties explicitly assigned to them. Never expose provider credentials to the browser.

## Properties and inventory

- `GET /api/v2/properties` — list properties visible to the current user.
- `POST /api/v2/properties` — create property (admin/manager).
- `GET /api/v2/properties/:propertyId/units` — list physical units.
- `POST /api/v2/properties/:propertyId/units` — create apartment/room.
- `GET /api/v2/properties/:propertyId/room-types` — list room types.
- `POST /api/v2/properties/:propertyId/room-types` — create room type.

## Channel mapping

- `GET /api/v2/channel-accounts` — connected provider accounts (secrets omitted).
- `GET /api/v2/channel-listings?accountId=...` — imported external listings.
- `GET /api/v2/channel-mappings` — list mappings and mapping health.
- `POST /api/v2/channel-mappings` — create mapping.
- `PATCH /api/v2/channel-mappings/:id` — change mapping; requires audit event.
- `POST /api/v2/channel-mappings/:id/test` — validate property/unit/room-type compatibility and inventory.

Mapping payload examples:

```json
{
  "listingId": "<uuid>",
  "propertyId": "<uuid>",
  "mappingMode": "UNIT",
  "unitId": "<uuid>"
}
```

```json
{
  "listingId": "<uuid>",
  "propertyId": "<uuid>",
  "mappingMode": "ROOM_TYPE",
  "roomTypeId": "<uuid>"
}
```

## Reservations and events

- `GET /api/v2/reservations` — filters: `propertyId`, `from`, `to`, `status`, `channelId`.
- `GET /api/v2/reservations/:id` — reservation with guest, external references and allocated unit.
- `POST /api/v2/integrations/:channelCode/webhook` — provider webhook receiver.
- `POST /api/v2/integrations/:channelCode/reconcile` — admin-triggered reconciliation.
- `GET /api/v2/integration-events?status=failed` — failed events for admins.

Webhook handlers must verify provider signatures where supported, persist the raw event first, return quickly, and process asynchronously. Event processing must be idempotent using provider event IDs or a stable deduplication key. If a provider supplies no stable event ID, derive a deterministic key from account + booking ID + event type + provider update timestamp.

## Reservation normalization rules

- Keep provider's raw payload in a restricted JSONB field for debugging/audit, with retention and access controls.
- Normalize dates as `DATE` (arrival/departure local dates), not JavaScript timestamps.
- Store money as decimal amount + ISO currency; never use floating-point arithmetic for money.
- Preserve provider status separately in `reservation_external_refs.external_status`.
- Never fabricate guest name, phone, email, guest count or price if a channel does not disclose them. Store null and visibility state.
- Cancellation is a status transition and audit event; do not hard-delete OTA reservations.
- Room-type bookings allocate one available physical unit transactionally. Unit bookings must allocate the mapped unit.
- Availability is `[check_in, check_out)`; checkout day is not occupied.
