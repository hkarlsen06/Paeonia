import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Join Paeonia',
  description: 'Open a Paeonia partner invite on your iPhone.',
};

export default function JoinPage() {
  return (
    <main className="page-shell narrow">
      <h1>Open Paeonia on your iPhone.</h1>
      <p className="lede">
        If Paeonia is installed, open this invite link again on your iPhone to join your partner. If
        you do not have the app yet, ask your partner for the current invite instructions.
      </p>
      <div className="actions">
        <Link className="button" href="/en/">
          Back to Paeonia
        </Link>
      </div>
    </main>
  );
}
