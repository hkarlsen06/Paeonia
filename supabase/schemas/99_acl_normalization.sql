-- Supabase's local bootstrap grants these table-owner privileges to API roles
-- through platform defaults. Paeonia intentionally does not expose them.
--
-- Keep this file last so newly declared public tables and views are normalized
-- after every other declarative schema file has run.

revoke maintain, references, trigger, truncate
on all tables in schema public
from anon, authenticated;
