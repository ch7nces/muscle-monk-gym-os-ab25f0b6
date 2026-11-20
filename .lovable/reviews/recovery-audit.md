# Recovery audit

## Verified implemented
- TanStack Start with React, TypeScript, Tailwind v4 and existing shadcn controls.
- Lovable Cloud is connected and running.
- Saved black/red theme and temporary generated gym image.
- Bearer middleware registered in the target runtime.
- Import-status home page was checked on desktop and phone; routing test passed.

## Partially implemented
- Source schema reference describes gym content, tenant roles, members, finance, leads, trial bookings and attendance. It has not been applied here.
- Generated Cloud authentication clients are present; no application sign-in flow exists yet.
- QR security rules appear in the inactive SQL reference, not in the live database.

## Not implemented
- Live public application tables, RLS policies and gym functions: none found.
- Live auth users: zero; storage buckets: zero; saved migration entries: zero.
- Public gym pages, forms, dashboards, member/trainer portals and attendance interfaces.
- Payments provider, workflows, reporting, renewal messaging and workout assignments.

## Limitations and security review
- Previous account data is inaccessible; no recovered records are claimed.
- Hosted signup/provider configuration was not available through the read-only audit tools; it remains unverified until configured/tested.
- Do not activate the source's unrestricted first-owner claim. Use a designated verified owner instead.
- Do not link imported members by an ambiguous first email match.
- Do not publish unconfirmed facilities, prices, staff, reviews or statistics.

## Current delivery
Rebuild and verify the public foundation using existing compatible files, then continue the management platform in independently verified phases. No production data will be reset or deleted.