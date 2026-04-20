import { startTransition, useEffect, useState } from 'react';

const initialState = {
  venues: [],
  stats: null,
  health: null,
};

function formatVotes(value) {
  return new Intl.NumberFormat('en-US').format(value ?? 0);
}

function formatGeneratedAt(value) {
  if (!value) return 'Syncing live data';

  return new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(value));
}

function VoteChart({ venues }) {
  const width = 420;
  const height = 270;
  const centerX = width / 2;
  const centerY = height / 2;
  const radius = 82;
  const totalVotes = venues.reduce((sum, venue) => sum + venue.votes, 0);

  let runningAngle = -Math.PI / 2;

  return (
    <div className="chart-shell">
      <svg viewBox={`0 0 ${width} ${height}`} className="vote-chart" role="img" aria-label="FoodPulse voting chart">
        {venues.map((venue) => {
          const ratio = totalVotes > 0 ? venue.votes / totalVotes : 1 / Math.max(venues.length, 1);
          const sliceAngle = ratio * Math.PI * 2;
          const endAngle = runningAngle + sliceAngle;

          const x1 = centerX + radius * Math.cos(runningAngle);
          const y1 = centerY + radius * Math.sin(runningAngle);
          const x2 = centerX + radius * Math.cos(endAngle);
          const y2 = centerY + radius * Math.sin(endAngle);
          const largeArcFlag = sliceAngle > Math.PI ? 1 : 0;

          const path = [
            `M ${centerX} ${centerY}`,
            `L ${x1} ${y1}`,
            `A ${radius} ${radius} 0 ${largeArcFlag} 1 ${x2} ${y2}`,
            'Z',
          ].join(' ');

          runningAngle = endAngle;

          return <path key={venue.slug} d={path} fill={venue.accent_color} className="chart-slice" />;
        })}

        <circle cx={centerX} cy={centerY} r="42" fill="rgba(255,255,255,0.95)" />
        <text x={centerX} y={centerY - 4} textAnchor="middle" className="chart-center-label">
          Votes
        </text>
        <text x={centerX} y={centerY + 18} textAnchor="middle" className="chart-center-value">
          {formatVotes(totalVotes)}
        </text>
      </svg>

      <div className="chart-legend">
        {venues.map((venue) => (
          <div className="legend-item" key={venue.slug}>
            <span className="legend-dot" style={{ background: venue.accent_color }} />
            <span className="legend-name">{venue.name}</span>
            <strong>{formatVotes(venue.votes)}</strong>
          </div>
        ))}
      </div>
    </div>
  );
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
          venues: current.venues
            .map((venue) =>
              venue.slug === payload.venue?.slug
                ? { ...venue, votes: payload.venue.votes }
                : venue,
            )
            .sort((left, right) => right.votes - left.votes || left.name.localeCompare(right.name)),
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
  const healthStatus = data.health?.status === 'healthy' ? 'healthy' : 'degraded';
  const databaseOnline = data.health?.checks?.database;
  const cacheOnline = data.health?.checks?.cache;

  return (
    <div className="page-shell">
      <div className="backdrop backdrop-left" />
      <div className="backdrop backdrop-right" />
      <div className="grid-glow" />

      <main className="app-frame">
        <header className="topbar">
          <div className="branding-mark">
            <span className="branding-orb" />
            <span>
              FoodPulse
              <small>Resilient dining signal</small>
            </span>
          </div>
          <div className="topbar-actions">
            <span className="status-pill is-soft">Live board</span>
            <span className={`status-pill ${healthStatus === 'healthy' ? 'is-good' : 'is-warn'}`}>
              {healthStatus === 'healthy' ? 'Healthy' : 'Needs attention'}
            </span>
          </div>
        </header>

        <section className="hero-panel">
          <div className="hero-copy">
            <p className="section-label">Live Dining Board</p>
            <h1 className="welcome-title">A food vote with production-grade resilience.</h1>
            <p className="welcome-copy">
              Pick the restaurant with the strongest menu story while FoodPulse keeps the signal
              flowing through Postgres, Redis, HAProxy, and live observability hooks.
            </p>
            <div className="hero-actions">
              <a className="primary-link" href="#restaurants">Choose a restaurant</a>
              <a className="secondary-link" href="#pulse">View live pulse</a>
            </div>
          </div>

          <aside className="ops-panel" aria-label="FoodPulse platform status">
            <div className="ops-header">
              <span className="ops-kicker">Ops Snapshot</span>
              <span className="ops-time">{formatGeneratedAt(data.stats?.generatedAt)}</span>
            </div>
            <div className="ops-pulse">
              <span>Failover posture</span>
              <strong>{healthStatus === 'healthy' ? 'Ready' : 'Watch'}</strong>
              <p>Traffic stays routed through HAProxy while Redis and Postgres checks keep the board honest.</p>
            </div>
            <div className="ops-stack">
              <div className={`ops-row ${databaseOnline ? 'is-online' : 'is-offline'}`}>
                <span>Postgres route</span>
                <strong>{databaseOnline ? 'Online' : 'Check DB'}</strong>
              </div>
              <div className={`ops-row ${cacheOnline ? 'is-online' : 'is-offline'}`}>
                <span>Redis cache</span>
                <strong>{cacheOnline ? 'Online' : 'Check cache'}</strong>
              </div>
              <div className="ops-row is-online">
                <span>Serving node</span>
                <strong>{data.stats?.hostname ?? 'Pending'}</strong>
              </div>
            </div>
          </aside>
        </section>

        {message ? <div className="inline-message centered-message">{message}</div> : null}

        <section className="section-heading" id="restaurants">
          <div>
            <p className="section-label">Restaurant Labels</p>
            <h2>Choose the signal that wins the room.</h2>
          </div>
          <span className="section-chip">{formatVotes(data.stats?.activeVenueCount)} kitchens online</span>
        </section>

        <section className="venues-grid">
          {data.venues.map((venue) => (
            <article className="restaurant-card" key={venue.slug} style={{ '--venue-accent': venue.accent_color }}>
              <div className="restaurant-header" style={{ color: venue.accent_color }}>
                <span className="restaurant-badge">
                  {venue.category}
                </span>
                <span className="restaurant-score">{venue.energy_score}/100</span>
              </div>

              <div className="restaurant-name">{venue.name}</div>
              <p className="restaurant-copy">{venue.headline}</p>

              <div className="restaurant-labels">
                <span className="restaurant-label">{venue.neighborhood}</span>
                <span className="restaurant-label">{venue.price_band}</span>
                <span className="restaurant-label">{formatVotes(venue.votes)} votes</span>
              </div>

              <p className="restaurant-signature">{venue.signature_item}</p>
              <p className="restaurant-spotlight">{venue.spotlight}</p>

              <div className="restaurant-actions">
                <a
                  className="visit-button"
                  href={venue.website_url}
                  target="_blank"
                  rel="noreferrer"
                >
                  Visit website
                </a>
                <button
                  className="vote-button"
                  type="button"
                  disabled={submittingSlug === venue.slug}
                  onClick={() => voteForVenue(venue.slug)}
                >
                  {submittingSlug === venue.slug ? 'Casting...' : 'Vote'}
                </button>
              </div>
            </article>
          ))}
        </section>

        <section className="chart-center-panel" id="pulse">
          <div className="panel-heading">
            <div>
              <p className="panel-label">Vote Split</p>
              <h2>Live pulse</h2>
            </div>
            <span className="panel-badge">{leader?.name ?? 'Waiting for votes'} leads</span>
          </div>
          <VoteChart venues={data.venues} />
        </section>

        <section className="stats-grid">
          <article className="stats-card">
            <span className="stats-label">Page views</span>
            <strong>{formatVotes(data.stats?.pageviews)}</strong>
          </article>
          <article className="stats-card">
            <span className="stats-label">Serving node</span>
            <strong>{data.stats?.hostname ?? 'Unknown'}</strong>
          </article>
          <article className="stats-card">
            <span className="stats-label">Top pick</span>
            <strong>{leader?.name ?? 'Waiting for data'}</strong>
          </article>
          <article className="stats-card">
            <span className="stats-label">Total votes</span>
            <strong>{formatVotes(data.stats?.totalVotes)}</strong>
          </article>
        </section>

        {isLoading ? <div className="loading-banner">Loading live FoodPulse data...</div> : null}
      </main>
    </div>
  );
}

export default App;
