'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { marketingEn } from '@/lib/i18n/dictionaries/marketing.en';
import { marketingNo } from '@/lib/i18n/dictionaries/marketing.no';

interface JoinFallbackProps {
  appStoreURL: string | null;
}

const copy = {
  en: marketingEn.join,
  nb: marketingNo.join,
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
