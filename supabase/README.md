# Paeonia Supabase

Supabase backend placeholder.

Do not create schema migrations until the core relationship, entitlement, memory, media, widget drawing, and sync model has been reviewed.

Current backend decisions:

- Use Supabase.
- Use Supabase Auth with Sign in with Apple, Google Sign-In, and passkeys.
- Do not support email/password or email magic-link auth for MVP.
- Enable RLS by default.
- Use the database as the source of truth for couple membership and shared subscription entitlement.
- Use service-role flows only for privileged work such as cron cleanup, admin deletion, and notification fanout internals.
