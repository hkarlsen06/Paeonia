import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Join Paeonia',
  description: 'Paeonia invite links will open the app later.',
};

export default function JoinPage() {
  return (
    <main className="page-shell narrow">
      <h1>Paeonia is not ready yet.</h1>
      <p className="lede">
        This invite link will open Paeonia later. For now, the app is still being built.
      </p>
      <div className="actions">
        <Link className="button" href="/en/">
          Back to Paeonia
        </Link>
      </div>
    </main>
  );
}
