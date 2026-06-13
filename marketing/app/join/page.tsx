import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Join Paeonia',
  description: 'Open a Paeonia invitation.',
};

export default function JoinPage() {
  return (
    <main className="page-shell narrow">
      <p className="kicker">Paeonia invite</p>
      <h1>Open your invitation in the app.</h1>
      <p className="lede">
        This page is reserved for invite links. Once the iOS app is ready, links that start with
        paeonia.no/join will open Paeonia directly.
      </p>
      <div className="actions">
        <Link className="button" href="/en/">
          Back to Paeonia
        </Link>
      </div>
    </main>
  );
}
