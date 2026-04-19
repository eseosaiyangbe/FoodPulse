import { startTransition, useEffect, useState } from 'react';

const initialState = {
  venues: [],
  stats: null,
  health: null,
};

function formatVotes(value) {
  return new Intl.NumberFormat('en-US').format(value ?? 0);
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

  return (
    <div className="page-shell">
      <div className="backdrop backdrop-left" />
      <div className="backdrop backdrop-right" />

      <main className="app-frame classic-layout">
        <header className="topbar">
          <div className="branding-mark">
            <span className="branding-orb" />
            <span>FoodPulse</span>
          </div>
          <div className="topbar-actions">
            <span className={`status-pill ${data.health?.status === 'healthy' ? 'is-good' : 'is-warn'}`}>
              {data.health?.status === 'healthy' ? 'Healthy' : 'Needs attention'}
            </span>
          </div>
        </header>

        <section className="welcome-panel">
          <p className="section-label centered">Live Dining Board</p>
          <h1 className="welcome-title">Welcome to FoodPulse.</h1>
          <p className="welcome-copy">
            Pick the restaurant with the strongest menu story, then watch the board update in real
            time. Same familiar layout, cleaner dashboard styling.
          </p>
        </section>

        {message ? <div className="inline-message centered-message">{message}</div> : null}

        <section className="venues-grid">
          {data.venues.map((venue) => (
            <article className="restaurant-card" key={venue.slug}>
              <div className="restaurant-header" style={{ color: venue.accent_color }}>
                <span className="restaurant-badge" style={{ background: `${venue.accent_color}18`, borderColor: `${venue.accent_color}35` }}>
                  {venue.category}
                </span>
                <span className="restaurant-score">{venue.energy_score}/100</span>
              </div>

              <div className="restaurant-name">{venue.name}</div>
              <p className="restaurant-copy">{venue.signature_item}</p>

              <div className="restaurant-labels">
                <span className="restaurant-label">{venue.neighborhood}</span>
                <span className="restaurant-label">{venue.price_band}</span>
              </div>

              <p className="restaurant-spotlight">{venue.spotlight}</p>

              <button
                className="vote-button"
                type="button"
                disabled={submittingSlug === venue.slug}
                onClick={() => voteForVenue(venue.slug)}
              >
                {submittingSlug === venue.slug ? 'Casting vote...' : `Vote for ${venue.name}`}
              </button>
            </article>
          ))}
        </section>

        <section className="chart-center-panel">
          <div className="panel-heading">
            <div>
              <p className="panel-label">Vote Split</p>
              <h2>Live results</h2>
            </div>
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
