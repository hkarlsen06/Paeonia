import { localeNames, locales, type Locale } from '@/lib/i18n/config';
import { buildLocalizedPath } from '@/lib/paths';

interface LocaleToggleProps {
  locale: Locale;
  path?: string;
}

export function LocaleToggle({ locale, path }: LocaleToggleProps) {
  return (
    <nav
      aria-label="Language"
      className="inline-flex shrink-0 items-center rounded-full border border-white/8 bg-white/[0.02] p-[0.2rem] text-sm font-medium text-text-muted backdrop-blur-sm"
    >
      {locales.map((item) => (
        <a
          key={item}
          href={buildLocalizedPath(item, path)}
          hrefLang={item}
          lang={item}
          aria-current={item === locale ? 'page' : undefined}
          className={`inline-flex items-center rounded-full px-3.5 py-1.5 transition-colors hover:text-text-primary ${
            item === locale ? 'bg-white/[0.07] text-text-primary' : ''
          }`}
        >
          {localeNames[item]}
        </a>
      ))}
    </nav>
  );
}
