revoke all on function internal.get_or_create_app_account_token(uuid)
from public, anon, authenticated;

grant execute on function internal.get_or_create_app_account_token(uuid)
to service_role;
