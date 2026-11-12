type Props = { searchParams: Promise<{ q?: string }> };

export default async function SearchPage({ searchParams }: Props) {
  const { q = "" } = await searchParams;
  return (
    <main>
      <header><div className="brand">7 <span>IMPORTS</span></div><a href="/">Back to home</a></header>
      <section className="hero">
        <div className="eyebrow">CARD SEARCH</div>
        <h1>Search results</h1>
        <p>Search term: <strong>{q || "None entered"}</strong></p>
        <div className="note">
          The search interface is scaffolded. Live results will appear after the Supabase catalog,
          approved inventory views, and MTG catalog import are connected.
        </div>
      </section>
    </main>
  );
}
