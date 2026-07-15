import type { Metadata } from 'next';
import { JoinFallback } from '@/components/JoinFallback';

const paeoniaAppStoreURL = 'https://apps.apple.com/us/app/paeonia/id6779833892';

export const metadata: Metadata = {
  title: 'Join Paeonia',
  description: 'Open a Paeonia partner invite on your iPhone.',
  robots: {
    index: false,
    follow: false,
  },
};

export default function JoinPage() {
  const appStoreURL =
    process.env.NEXT_PUBLIC_PAEONIA_APP_STORE_URL?.trim() || paeoniaAppStoreURL;

  return <JoinFallback appStoreURL={appStoreURL} />;
}
