import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { LegalPage } from '@/components/LegalPage';
import { getMarketingDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';
import { generateLocaleStaticParams } from '@/lib/i18n/static-params';

interface PageProps {
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return generateLocaleStaticParams();
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getMarketingDictionary(locale as Locale);

  return {
    title: dictionary.legal.privacy.meta.title,
    description: dictionary.legal.privacy.meta.description,
  };
}

export default async function PrivacyPage({ params }: PageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  return <LegalPage locale={locale as Locale} variant="privacy" />;
}
