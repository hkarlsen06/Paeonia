import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="page-shell narrow">
      <p className="kicker">404</p>
      <h1>Page not found</h1>
      <p>The page you opened does not exist yet.</p>
      <Link className="text-link" href="/en/">
        Go to Paeonia
      </Link>
    </main>
  );
}
