'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';

interface JoinFallbackProps {
  appStoreURL: string | null;
}

const copy = {
  en: {
    title: "You've been invited to Paeonia",
    message: 'Open Paeonia to see who invited you and choose whether to join.',
    invalidTitle: "This invite link doesn't look right",
    invalidMessage: 'Ask your partner to share a new Paeonia invite.',
    missingMessage: 'Open the full invite link your partner shared with you.',
    code: 'Invite code',
    open: 'Open Paeonia',
    install: 'Get Paeonia on the App Store',
    beta: 'Don’t have Paeonia yet? Install it from the beta invitation you received, then open this link again. Keep this link until you’re connected.',
    help: 'Need help?',
    opening: 'Opening your invite…',
  },
  nb: {
    title: 'Du er invitert til Paeonia',
    message: 'Åpne Paeonia for å se hvem som inviterte deg, og velg om du vil bli med.',
    invalidTitle: 'Denne invitasjonslenken ser ikke riktig ut',
    invalidMessage: 'Be partneren din dele en ny invitasjon fra Paeonia.',
    missingMessage: 'Åpne hele invitasjonslenken partneren din delte med deg.',
    code: 'Invitasjonskode',
    open: 'Åpne Paeonia',
    install: 'Last ned Paeonia fra App Store',
    beta: 'Har du ikke Paeonia ennå? Installer appen fra betainvitasjonen du fikk, og åpne denne lenken på nytt. Behold lenken til dere er koblet sammen.',
    help: 'Trenger du hjelp?',
    opening: 'Åpner invitasjonen din …',
  },
} as const;

type Language = keyof typeof copy;

function normalizedInviteCode(pathname: string): string | null {
  const match = pathname.match(/^\/join\/([^/]+)\/?$/i);
  if (!match) return null;

  let candidate: string;
  try {
    candidate = decodeURIComponent(match[1]);
  } catch {
    return null;
  }

  const normalized = candidate
    .toUpperCase()
    .replace(/[\s_-]/g, '')
    .replace(/[IL]/g, '1')
    .replace(/O/g, '0');

  return /^[0123456789ABCDEFGHJKMNPQRSTVWXYZ]{6}$/.test(normalized) ? normalized : null;
}

export function JoinFallback({ appStoreURL }: JoinFallbackProps) {
  const [inviteCode, setInviteCode] = useState<string | null>();
  const [hasInvitePath, setHasInvitePath] = useState(false);
  const [language, setLanguage] = useState<Language>('en');

  useEffect(() => {
    setInviteCode(normalizedInviteCode(window.location.pathname));
    setHasInvitePath(/^\/join\/[^/]+\/?$/i.test(window.location.pathname));
    const browserLanguage = navigator.language.toLowerCase();
    setLanguage(/^(nb|no|nn)(-|$)/.test(browserLanguage) ? 'nb' : 'en');
  }, []);

  const text = copy[language];

  if (inviteCode === undefined) {
    return (
      <main className="join-page">
        <Link className="join-brand" href="/en/">
          <img src="/brand/paeonia-mark-tight.svg" alt="" width="36" height="36" />
          <span>Paeonia</span>
        </Link>
        <section className="join-content" aria-busy="true">
          <p className="join-opening">{text.opening}</p>
        </section>
      </main>
    );
  }

  const appURL = inviteCode ? `paeonia://join/${inviteCode}` : null;
  const title = inviteCode ? text.title : text.invalidTitle;
  const message = inviteCode
    ? text.message
    : hasInvitePath
      ? text.invalidMessage
      : text.missingMessage;

  return (
    <main className="join-page">
      <Link className="join-brand" href={language === 'nb' ? '/no/' : '/en/'}>
        <img src="/brand/paeonia-mark-tight.svg" alt="" width="36" height="36" />
        <span>Paeonia</span>
      </Link>

      <section className="join-content" aria-labelledby="join-title">
        <h1 id="join-title">{title}</h1>
        <p>{message}</p>

        {inviteCode ? (
          <div className="join-code" aria-label={`${text.code}: ${inviteCode}`}>
            <span>{text.code}</span>
            <strong>{inviteCode}</strong>
          </div>
        ) : null}

        <div className="join-actions">
          {appURL ? (
            <a className="join-primary" href={appURL}>
              {text.open}
            </a>
          ) : null}
          {appStoreURL ? (
            <a className="join-secondary" href={appStoreURL}>
              {text.install}
            </a>
          ) : null}
        </div>

        {!appStoreURL && inviteCode ? <p className="join-install-note">{text.beta}</p> : null}

        <Link className="join-help" href={language === 'nb' ? '/no/support/' : '/en/support/'}>
          {text.help}
        </Link>
      </section>
    </main>
  );
}
