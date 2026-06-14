import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { SupportPage } from '@/components/SupportPage';
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
    title: dictionary.marketing.support.title,
    description: dictionary.marketing.support.description,
  };
}

export default async function LocaleSupportPage({ params }: PageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  return <SupportPage locale={locale as Locale} />;
}
