-- Keep private daily challenge implementations private. App clients call the
-- `public.*` security-definer wrappers, which enforce auth and reach `internal.*`
-- as the function owner.

revoke execute on function internal.update_daily_answer_text(uuid, text, uuid, uuid, bigint, timestamptz)
  from public, anon, authenticated;

revoke execute on function internal.update_daily_answer_partner_choice(uuid, uuid, uuid, uuid, bigint, timestamptz)
  from public, anon, authenticated;

revoke execute on function internal.get_daily_questions_history()
  from public, anon, authenticated;

revoke execute on function internal.get_daily_answer_history_details()
  from public, anon, authenticated;
