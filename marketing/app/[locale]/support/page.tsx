import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { SupportPage } from '@/components/SupportPage';
import { getDictionary } from '@/lib/i18n/dictionaries';
import { locales, type Locale } from '@/lib/i18n/config';

interface PageProps {
  params: Promise<{ locale: string }>;
}

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    return {};
  }

  const dictionary = getDictionary(locale as Locale);

  return {
    title: dictionary.support.title,
    description: dictionary.support.description,
  };
}

export default async function LocaleSupportPage({ params }: PageProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  return <SupportPage locale={locale as Locale} />;
}
