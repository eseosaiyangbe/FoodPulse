import { startTransition, useEffect, useState } from 'react';

const initialState = {
  venues: [],
  stats: null,
  health: null,
};

function formatVotes(value) {
  return new Intl.NumberFormat('en-US').format(value ?? 0);
}

function App() {
  const [data, setData] = useState(initialState);
  const [isLoading, setIsLoading] = useState(true);
  const [submittingSlug, setSubmittingSlug] = useState('');
  const [message, setMessage] = useState('');

  useEffect(() => {
    let ignore = false;

    async function bootstrap() {
      try {
        await fetch('/api/pageviews', { method: 'POST' });
      } catch (error) {
        console.error('pageview bootstrap failed', error);
      }

      try {
        const [venuesResponse, statsResponse, healthResponse] = await Promise.all([
          fetch('/api/venues'),
          fetch('/api/getstats'),
          fetch('/api/health'),
        ]);

        const [venuesPayload, statsPayload, healthPayload] = await Promise.all([
          venuesResponse.json(),
          statsResponse.json(),
          healthResponse.json(),
        ]);

        if (!ignore) {
          startTransition(() => {
            setData({
              venues: venuesPayload.venues ?? [],
              stats: statsPayload,
              health: healthPayload,
            });
            setIsLoading(false);
          });
        }
      } catch (error) {
        console.error('foodpulse bootstrap failed', error);
        if (!ignore) {
          setMessage('FoodPulse could not load live data. Check the API and HA proxies, then refresh.');
          setIsLoading(false);
        }
      }
    }

    bootstrap();
    const interval = setInterval(bootstrap, 15000);

    return () => {
      ignore = true;
      clearInterval(interval);
    };
  }, []);

  async function voteForVenue(venueSlug) {
    setSubmittingSlug(venueSlug);
    setMessage('');

    try {
      const response = await fetch('/api/vote', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ venueSlug }),
      });

      if (!response.ok) {
        throw new Error('Vote request failed');
      }

      const payload = await response.json();
      setMessage(`${payload.venue?.name ?? 'Venue'} just picked up another vote.`);

      startTransition(() => {
        setData((current) => ({
          ...current,
          venues: current.venues.map((venue) =>
            venue.slug === payload.venue?.slug
              ? { ...venue, votes: payload.venue.votes }
              : venue,
          ).sort((left, right) => right.votes - left.votes || left.name.localeCompare(right.name)),
          stats: payload.stats,
        }));
      });
    } catch (error) {
      console.error('vote failed', error);
      setMessage('Vote failed. The app is still running, but the request did not commit.');
    } finally {
      setSubmittingSlug('');
    }
  }

  const leader = data.venues[0];
  const maxVotes = Math.max(...data.venues.map((venue) => venue.votes), 1);

  return (
    <div className="page-shell">
      <div className="backdrop backdrop-left" />
      <div className="backdrop backdrop-right" />

      <main className="app-frame">
        <section className="hero-panel">
          <div className="eyebrow">FoodPulse Control Surface</div>
          <div className="hero-grid">
            <div>
              <h1>We rebuilt FoodPulse as a modern app we actually own.</h1>
              <p className="hero-copy">
                Live dining signals, resilient data paths, and a front end that feels like a product
                instead of a relic. The experience is now backed by a workspace-owned React and Node
                stack, with Redis and Postgres still running the HA drills underneath.
              </p>
              <div className="hero-actions">
                <a className="ghost-button" href="/api/health" target="_blank" rel="noreferrer">
                  API Health
                </a>
                <a className="ghost-button" href="/metrics" target="_blank" rel="noreferrer">
                  Metrics
                </a>
              </div>
            </div>

            <div className="hero-status">
              <div className="status-pill">
                <span className={`status-dot ${data.health?.status === 'healthy' ? 'good' : 'warn'}`} />
                <span>{data.health?.status === 'healthy' ? 'Healthy' : 'Needs attention'}</span>
              </div>
              <div className="metric-grid">
                <article className="metric-card">
                  <span className="metric-label">Page views</span>
                  <strong>{formatVotes(data.stats?.pageviews)}</strong>
                </article>
                <article className="metric-card">
                  <span className="metric-label">Votes cast</span>
                  <strong>{formatVotes(data.stats?.totalVotes)}</strong>
                </article>
                <article className="metric-card">
                  <span className="metric-label">Top pick</span>
                  <strong>{data.stats?.topVenue?.name ?? 'Waiting for data'}</strong>
                </article>
                <article className="metric-card">
                  <span className="metric-label">App host</span>
                  <strong>{data.stats?.hostname ?? 'Unknown'}</strong>
                </article>
              </div>
            </div>
          </div>
        </section>

        <section className="content-grid">
          <div className="venues-panel">
            <div className="section-heading">
              <div>
                <p className="section-label">Venue Ranking</p>
                <h2>Vote for the most compelling menu moment.</h2>
              </div>
              {leader ? (
                <div className="leader-badge">
                  <span>Current leader</span>
                  <strong>{leader.name}</strong>
                </div>
              ) : null}
            </div>

            {message ? <div className="inline-message">{message}</div> : null}

            <div className="venue-list">
              {data.venues.map((venue) => (
                <article className="venue-card" key={venue.slug}>
                  <div className="venue-accent" style={{ background: venue.accent_color }} />
                  <div className="venue-copy">
                    <div className="venue-header">
                      <div>
                        <p className="venue-neighborhood">{venue.neighborhood}</p>
                        <h3>{venue.name}</h3>
                      </div>
                      <span className="energy-badge">{venue.energy_score}/100</span>
                    </div>

                    <p className="venue-spotlight">{venue.spotlight}</p>

                    <div className="venue-meta">
                      <span>{venue.category}</span>
                      <span>{venue.signature_item}</span>
                      <span>{venue.price_band}</span>
                    </div>

                    <div className="vote-row">
                      <div className="vote-bar-shell">
                        <div
                          className="vote-bar-fill"
                          style={{
                            width: `${Math.max((venue.votes / maxVotes) * 100, 6)}%`,
                            background: venue.accent_color,
                          }}
                        />
                      </div>
                      <strong>{formatVotes(venue.votes)} votes</strong>
                    </div>

                    <button
                      className="vote-button"
                      type="button"
                      disabled={submittingSlug === venue.slug}
                      onClick={() => voteForVenue(venue.slug)}
                    >
                      {submittingSlug === venue.slug ? 'Casting vote...' : `Vote for ${venue.name}`}
                    </button>
                  </div>
                </article>
              ))}
            </div>
          </div>

          <aside className="side-panel">
            <section className="insight-panel">
              <p className="section-label">Operator Notes</p>
              <h2>Built for the Kubernetes move.</h2>
              <ul className="insight-list">
                <li>Dedicated UI and API images with environment-driven runtime contracts.</li>
                <li>Health and metrics endpoints are now first-class instead of accidental.</li>
                <li>HAProxy still fronts Redis and Postgres, so failover drills stay meaningful.</li>
                <li>Observability remains centralized in the workspace control plane.</li>
              </ul>
            </section>

            <section className="pulse-panel">
              <p className="section-label">Live pulse</p>
              <h2>Current system state</h2>
              <div className="pulse-items">
                <div>
                  <span>Database</span>
                  <strong>{data.health?.checks?.database ? 'Connected' : 'Waiting'}</strong>
                </div>
                <div>
                  <span>Cache</span>
                  <strong>{data.health?.checks?.cache ? 'Connected' : 'Waiting'}</strong>
                </div>
                <div>
                  <span>Venues loaded</span>
                  <strong>{formatVotes(data.stats?.activeVenueCount)}</strong>
                </div>
                <div>
                  <span>Last refresh</span>
                  <strong>
                    {data.stats?.generatedAt
                      ? new Date(data.stats.generatedAt).toLocaleTimeString()
                      : 'Pending'}
                  </strong>
                </div>
              </div>
            </section>
          </aside>
        </section>

        {isLoading ? <div className="loading-banner">Loading the FoodPulse control surface...</div> : null}
      </main>
    </div>
  );
}

export default App;
