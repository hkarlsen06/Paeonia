# Voice And Copy

Paeonia's copy should feel like a calm private product, not a social network, dating app, or productivity tool.

## Voice

The voice is:

- warm
- direct
- respectful
- emotionally clear
- concise
- trustworthy
- understandable to an ordinary 16-year-old

It is not:

- clingy
- overly cute
- guilt-driven
- corporate
- sarcastic
- performatively romantic

## Core Phrase

> A private place for the two of you.

This is the current primary positioning line.

## Copy Rules

- Use plain language.
- Write every user-facing sentence so an ordinary 16-year-old can understand it without knowing anything about software.
- Avoid fake urgency.
- Avoid public/social words like followers, profile discovery, feed, audience.
- Avoid making streaks feel punitive.
- Explain privacy-sensitive actions clearly.
- Make destructive actions explicit.
- Keep onboarding copy short.
- Hide implementation details. Users do not need to know about sync coordinators, entitlements, jobs, queues, payloads, JWTs, RLS, or database state.
- Use short sentences for errors, paywalls, permissions, privacy, and account deletion.

## Technical Wording

Paeonia should never sound like an internal admin tool.

Technical terms must be translated into human outcomes.

| Avoid | Use |
| --- | --- |
| Pending sync mutation | Saved on this phone. We'll send it when you're online. |
| Upload queued | Your partner will see this when it finishes sending. |
| Entitlement removed | You no longer have access to this relationship. |
| Subscription validation failed | We could not confirm your subscription. Try restoring purchases. |
| Relationship deletion scheduled | This relationship will be deleted after the waiting period. |
| Invalid invite token | This invite link does not work anymore. Ask your partner for a new one. |
| Network request failed | We could not connect. Check your internet and try again. |

If a line is technically accurate but emotionally confusing, rewrite it.

## Preferred Terms

Use:

- partner
- relationship
- private space
- memory
- check-in
- drawing
- milestone
- invite

Avoid:

- match
- follower
- public profile
- post
- viral
- audience
- engagement bait

## Onboarding Tone

Onboarding should say:

- this is private
- pairing requires an invite and accept flow
- the relationship start date powers milestones
- one partner paying unlocks access for both

It should not explain every feature at once.

## Paywall Tone

The paywall can be firm because the product is paid, but it must be transparent.

Good:

```text
One subscription unlocks Paeonia for both of you.
```

Avoid:

```text
Your relationship deserves this.
```

Also avoid technical purchase wording.

Use:

```text
We could not confirm your purchase. Try restoring purchases.
```

Instead of:

```text
Receipt validation failed.
```

## Empty State Tone

Empty states should invite action.

Good:

```text
No memories yet. Save a small moment from today.
```

Avoid:

```text
You have not saved anything yet.
```

## Notification Tone

Notifications should be respectful and useful.

Allowed notification purposes:

- streak/check-in reminder before expiry
- partner sent a drawing
- partner answered a question the user already answered
- partner finished today's questions

Avoid guilt:

```text
Your check-in expires soon
```

Instead of:

```text
Do not lose your streak
```

## Error Copy

Every error should answer two questions:

1. What happened?
2. What can I do now?

Good:

```text
We could not send your drawing. It is saved here, and we'll try again when you're online.
```

Avoid:

```text
Sync failed.
```

## Localization

All app copy must be written with localization in mind.

Rules:

- no string concatenation
- no raw localization keys
- avoid idioms that do not translate
- avoid technical shorthand
- keep Norwegian Bokmal parity from the start
