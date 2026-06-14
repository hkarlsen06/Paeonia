import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LandingPage } from '@/components/LandingPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';
import { generateLocaleStaticParams } from '@/lib/i18n/static-params';

interface LocalePageProps {
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return generateLocaleStaticParams();
}

export async function generateMetadata({ params }: LocalePageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getMarketingDictionary(locale as Locale);
  const url = `https://paeonia.no/${locale}`;

  return {
    title: {
      absolute: dictionary.marketing.meta.title,
    },
    description: dictionary.marketing.meta.description,
    alternates: {
      canonical: url,
    },
    openGraph: {
      title: dictionary.marketing.meta.title,
      description: dictionary.marketing.meta.description,
      url,
      type: 'website',
    },
  };
}

export default async function LocaleLandingPage({ params }: LocalePageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  return <LandingPage locale={locale as Locale} dictionary={getMarketingDictionary(locale as Locale)} />;
}
