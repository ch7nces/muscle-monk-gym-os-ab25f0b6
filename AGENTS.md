<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.

## What Lovable manages

Rules outside this block are the project's own. Change the pieces below in
Lovable, not by hand. With the [Lovable MCP](https://mcp.lovable.dev)
connected, `send_message` asks Lovable to do it; otherwise ask the user to
use the editor.

- **Database.** Do not add or edit `supabase/migrations/` or `drizzle/`.
  Ask Lovable to change the schema.
- **Generated files.** Do not edit a file whose header says it is automatically
  generated.
- **AI gateway.** Keep model calls on Lovable's gateway, and keep
  `LOVABLE_API_KEY` out of browser code.
- **Connectors.** Lovable provides native connectors. `list_connectors` shows
  which are enabled; `add_connector` only returns the dashboard link. When a
  connector is enabled, calls go through the connector gateway and need
  `LOVABLE_API_KEY`. When Lovable does not provide one, users can bring their
  own key and store it in Secrets.
- **Secrets.** Lovable manages them. Do not put secret values in the repo.
<!-- LOVABLE:END -->

## Import boundaries
- Keep the target TanStack runtime and generated Cloud integrations; imported source must not replace project bindings or pinned framework versions.
- Keep the original SQL as reference; new schema uses reviewed tenant policies and no unrestricted owner-claim endpoint, preventing public account takeover.
- Public content is read through anonymous-policy-scoped server functions; public forms use validated, atomic database functions with per-contact rate limits and no public private-record reads.
- Each public content page has its own TanStack route and metadata; reusable public shell and forms remain shared to keep the website consistent.
- Content edits use authenticated, RLS-scoped functions; facility verification and price publication gates also run in database triggers so direct requests cannot bypass them.
- Attendance uses hashed, short-lived database tokens and atomic redemption with membership locks, replay protection, scan limits and audit records; never accept client timestamps or identity as check-in proof.
- Membership account linking uses verified auth emails through a staff-authorized database function, not editable profile metadata.
- Keep trainer uploads in private storage with gym-folder policies; public reads sign only published active trainer photos, because workspace policy blocks public buckets.
