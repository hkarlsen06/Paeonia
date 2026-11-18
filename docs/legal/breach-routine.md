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

Tell them without delay when the risk to them is high. Email the address on the account (`users.email`) with what happened, what it means for them, what Paeonia has done and what they can do. Also send a push, which reaches the accounts that have no address. It carries no detail, because a push shows on a lock screen. Where one partner's safety is at stake, write to that person alone.

Neither message has a command yet. A push to many accounts needs a new kind in `NOTIFICATION_PAYLOAD_FIELDS` (`backend/convex/lib/notifications.ts`), and mail to Apple's hidden addresses needs the sender registered with Apple's email relay. Both are needed before launch.

## The register

Art. 33(5) requires a register. Keep it outside the repository, with one entry per event, including those not notified. Each entry has the time of discovery, what happened, the data and people affected, the risk decision and its reason, when Datatilsynet and the people were told, and what changed afterwards.
