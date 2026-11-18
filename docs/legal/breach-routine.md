# Personal data breach routine

GDPR Art. 33 and 34. Version 1, 18 November 2026.

A breach is any event where personal data in Paeonia is lost, changed, or seen by someone who should not see it, such as a break-in on the server, a leaked key or backup, or a bug that shows one couple's content to someone else.

## Who assesses

Hjalmar Karlsen, the controller, assesses every suspected breach himself. The 72 hours start when he becomes aware of it. He hears of one in three ways:

- The watchdog on the server emails him when `api.paeonia.no` fails, the backend is unhealthy or a backup is too old (`/srv/backup/watchdog.sh`, described in `backend/AGENTS.md` under "Hosted deployment"). It reports outages, not intrusions.
- A user writes to contact@paeonia.no or support@paeonia.no, or files a report in the app, which sends him a push.
- A processor notifies him under its agreement.

## What to do

1. Stop it. Take the server off the network or replace the leaked key (`npx convex env set`, and `npx wrangler secret put` for the relay).
2. Save the backend logs before a restart clears them (`sudo -n docker logs convex-backend-1`).
3. Find out whose data, which data, for how long, and whether it left the server.
4. Decide the risk to the people. Intimate content, a location or a report reaching the wrong person is a high risk. An outage with no data lost or seen is logged only.
5. Write it in the register.

## Telling Datatilsynet

Notify within 72 hours unless the breach is unlikely to put anyone at risk. File the form "Melding om brudd på personopplysningssikkerheten" in Altinn, linked from datatilsynet.no under "Avvik". The form expects an organisation. If it does not accept a private person, send the same content to postkasse@datatilsynet.no.

The notice says what happened, how many people and which kinds of data, the likely consequences and what has been done. Send what is known within the deadline and say that more follows. A late notice must give the reason for the delay.

## Telling the people

Tell them without delay when the risk to them is high. Use both channels, so the notice reaches people who turned notifications off, were banned or deleted the app.

- Push. `admin:operator_send_breach_notice` sends one push to every phone of every account, in English and Norwegian. The push opens the app, which has no screen for it, so the body says where to read more. It shows on a lock screen, so it names no detail of anyone's data.
- Email. `admin:operator_list_account_emails` lists every account's address from Clerk. Send the notice by hand from contact@paeonia.no with the addresses in Bcc. Apple's hidden addresses accept mail from it.

`backend/AGENTS.md` under "Breach notice" has the exact commands and limits. Where one partner's safety is at stake, write to that person alone instead.

## The register

Art. 33(5) requires a register. Keep it outside the repository, with one entry per event, including those not notified. Each entry has the time of discovery, what happened, the data and people affected, the risk decision and its reason, when Datatilsynet and the people were told, and what changed afterwards.
