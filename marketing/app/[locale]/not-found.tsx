import Link from 'next/link';

export default function LocaleNotFound() {
  return (
    <main className="page-shell narrow">
      <h1>Page not found</h1>
      <p>The page you opened does not exist yet.</p>
      <Link className="text-link" href="/en/">
        Go to Paeonia
      </Link>
    </main>
  );
}
