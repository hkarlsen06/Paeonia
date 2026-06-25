import type { Metadata, Viewport } from 'next';
import { defaultLocale } from '@/lib/i18n/config';
import { marketingPreviewImage, marketingTwitterMetadata } from '@/lib/metadata';
import '../globals.css';

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

export default function StaticLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang={defaultLocale} className="dark">
      <body className="bg-background text-foreground">{children}</body>
    </html>
  );
}
