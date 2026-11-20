# Public foundation delivery

## Implemented and verified
- Ten public gym pages with sticky navigation, mobile menu, temporary-image disclosure, real address/phone, WhatsApp links, FAQ and a Google Maps embed.
- Only published and approved content is displayed; prices, facilities, trainers and testimonials remain explicitly unconfirmed rather than invented.
- Enquiry and trial forms validate input, require contact consent, save atomically and return a receipt reference. Trial requests remain pending until staff confirmation.
- Protected staff workspace reads real enquiries and trial requests, supports handled flags and trial status updates, and paginates records.
- Password sign-in and sign-out verified through the UI with a temporary receptionist account.
- Registered accounts receive no owner/staff permissions automatically.

## Verification
- Five tests passed in `src/test/gym-rules.test.ts` and `src/test/app-routing.test.tsx`.
- Latest observed automatic build: OK.
- Desktop and phone screenshots inspected; no horizontal overflow or browser runtime errors detected.
- Browser submitted enquiry and trial records, restored an authenticated staff session, read both records through the UI, updated both, and confirmed signed-out access redirects to sign-in.
- Separate live database checks confirmed cross-gym denial, anonymous enquiry denial, consent enforcement, duplicate trial prevention, and rejection of a fourth per-contact request within one hour.
- Temporary request and isolation-gym records were removed. The temporary auth account is managed by the session tool and removed at turn end.

## Files and database changes
- Pages: `src/routes/index.tsx`, about/facilities/memberships/trainers/stories/reviews/trial/faq/contact, auth/reset-password, and protected account routes.
- Shared UI: `src/components/gym/` public shell, content, forms and session provider; root shell and global design tokens updated.
- Actions: `src/lib/gym.functions.ts`, `src/lib/account.functions.ts`; validation and metadata in `src/lib/gym.ts`.
- Migrations: `0000_public_gym_foundation.sql`, `0001_public_foundation_hardening.sql`.
- Live schema: gym identity/settings, profiles, separate user roles, approved website content, leads/trials/enquiries and audit log; protected access rules and atomic submissions.

## Still needed
- Designated owner's verified email before assigning owner permission.
- Confirmed photos, hours, facilities, prices, trainers and approved stories/reviews.
- Email confirmation, password recovery email round-trip and Google/Lovable provider round-trips need real user verification; not marked complete.
- Previous-account data and users were not recovered. CSV/JSON exports are needed only if existing records should migrate.
- Owner analytics dashboard, member management, memberships/renewals, actual QR scanning/check-in, invoices/finance, member/trainer portals and growth modules remain for later phases. No attendance or payment success is claimed.
- Razorpay is not yet implemented; credentials are not needed for the completed public foundation.
- Google Maps embed is present; external map interaction has not been independently verified.