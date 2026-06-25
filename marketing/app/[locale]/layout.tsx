import type { Metadata, Viewport } from 'next';
import { notFound } from 'next/navigation';
import { locales, type Locale } from '@/lib/i18n/config';
import { marketingPreviewImage, marketingTwitterMetadata } from '@/lib/metadata';
import '../globals.css';

interface LocaleLayoutProps {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}

export const metadata: Metadata = {
  metadataBase: new URL('https://paeonia.no'),
  title: {
    default: 'Paeonia',
    template: '%s - Paeonia',
  },
  description: 'A private place for couples who want to feel close between visits.',
  icons: {
    icon: [{ url: '/favicon.svg', type: 'image/svg+xml' }],
  },
  openGraph: {
    title: 'Paeonia',
    description: 'A private place for couples who want to feel close between visits.',
    url: 'https://paeonia.no',
    siteName: 'Paeonia',
    type: 'website',
    images: [marketingPreviewImage],
  },
  twitter: marketingTwitterMetadata,
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: '#2A0B1E',
  colorScheme: 'dark',
};

export function generateStaticParams() {
  return locales.map((locale) => ({ locale }));
}

export default async function LocaleLayout({ children, params }: LocaleLayoutProps) {
  const { locale } = await params;

  if (!locales.includes(locale as Locale)) {
    notFound();
  }

  return (
    <html lang={locale} className="dark">
      <body className="bg-background text-foreground">{children}</body>
    </html>
  );
}
