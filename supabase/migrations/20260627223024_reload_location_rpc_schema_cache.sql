-- Force PostgREST to rebuild its schema cache after the location RPC wrapper
-- metadata reconciliation in the previous migration.
notify pgrst, 'reload schema';
