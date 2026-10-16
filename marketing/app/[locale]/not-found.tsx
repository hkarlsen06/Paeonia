import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="page-shell narrow">
      <h1>Page not found / Siden finnes ikke</h1>
      <p>This page does not exist. / Denne siden finnes ikke.</p>
      <p>
        <Link className="text-link" href="/en/">
          Go to Paeonia
        </Link>
        {' · '}
        <Link className="text-link" href="/no/">
          Gå til Paeonia
        </Link>
      </p>
    </main>
  );
}
