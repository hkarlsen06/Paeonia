import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Join Paeonia',
  description: 'Paeonia partner invite links will open the shared space for a couple.',
};

export default function JoinPage() {
  return (
    <main className="page-shell narrow">
      <h1>Partner invites will open Paeonia.</h1>
      <p className="lede">
        When Paeonia launches, this link will connect you with your partner inside your shared space.
        There are no public profiles, people search, or suggested matches in the app.
      </p>
      <div className="actions">
        <Link className="button" href="/en/">
          Back to Paeonia
        </Link>
      </div>
    </main>
  );
}
