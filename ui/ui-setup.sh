#!/usr/bin/env bash
set -euo pipefail

APP_NAME="yelb-ui-ng"

echo "==> Creating Angular app: ${APP_NAME}"

# Create Angular app if it doesn't exist yet
if [ ! -d "${APP_NAME}" ]; then
  ng new "${APP_NAME}" \
    --routing=false \
    --style=css \
    --standalone=false \
    --skip-git \
    --strict
fi

cd "${APP_NAME}"

echo "==> Installing Tailwind and charting dependencies"

npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

npm install chart.js ng2-charts

echo "==> Writing Tailwind config"

cat > tailwind.config.cjs << 'EOF'
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{html,ts}"
  ],
  theme: {
    extend: {
      colors: {
        yelbBg: "#05070a",
        yelbCard: "#111827",
        yelbAccent: "#2563eb",
        yelbAccentSoft: "#1e40af"
      }
    },
  },
  plugins: [],
};
EOF

echo "==> Updating global styles"

cat > src/styles.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  @apply bg-yelbBg text-gray-100;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
EOF

echo "==> Writing environments"

mkdir -p src/environments

cat > src/environments/environment.ts << 'EOF'
export const environment = {
  production: true,
  // When served behind nginx in Docker, this is relative to the UI origin
  apiBaseUrl: '/api'
};
EOF

cat > src/environments/environment.development.ts << 'EOF'
export const environment = {
  production: false,
  apiBaseUrl: '/api'
};
EOF

echo "==> Creating models"

mkdir -p src/app/models

cat > src/app/models/votes.ts << 'EOF'
export interface VotesResponse {
  ihop: number;
  chipotle: number;
  outback: number;
  bucadibeppo: number;
  total: number;
}
EOF

cat > src/app/models/stats.ts << 'EOF'
export interface StatsResponse {
  totalvotes: number;
  pageviews: number;
}
EOF

echo "==> Creating API service"

mkdir -p src/app/services

cat > src/app/services/yelb-api.service.ts << 'EOF'
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '../../environments/environment';
import { Observable, map } from 'rxjs';
import { VotesResponse } from '../models/votes';
import { StatsResponse } from '../models/stats';

@Injectable({
  providedIn: 'root'
})
export class YelbApiService {
  private baseUrl = environment.apiBaseUrl;

  constructor(private http: HttpClient) {}

  getVotes(): Observable<VotesResponse> {
    return this.http.get<any>(`${this.baseUrl}/getvotes`).pipe(
      map(raw => ({
        ihop: raw.ihop,
        chipotle: raw.chipotle,
        outback: raw.outback,
        bucadibeppo: raw.bucadibeppo,
        total: raw.total ?? (raw.ihop + raw.chipotle + raw.outback + raw.bucadibeppo)
      }))
    );
  }

  getStats(): Observable<StatsResponse> {
    return this.http.get<any>(`${this.baseUrl}/getstats`).pipe(
      map(raw => ({
        totalvotes: raw.totalvotes,
        pageviews: raw.pageviews
      }))
    );
  }

  getPageviews(): Observable<number> {
    return this.http.get<any>(`${this.baseUrl}/pageviews`).pipe(
      map(raw => Number(raw.pageviews ?? raw))
    );
  }

  vote(restaurant: 'ihop' | 'chipotle' | 'outback' | 'bucadibeppo'): Observable<any> {
    return this.http.get(`${this.baseUrl}/vote`, {
      params: { restaurant }
    });
  }
}
EOF

echo "==> Creating components: dashboard and votes-chart"

mkdir -p src/app/components/dashboard
mkdir -p src/app/components/votes-chart

cat > src/app/components/votes-chart/votes-chart.component.ts << 'EOF'
import { Component, Input } from '@angular/core';
import { ChartType, ChartConfiguration } from 'chart.js';

@Component({
  selector: 'app-votes-chart',
  templateUrl: './votes-chart.component.html'
})
export class VotesChartComponent {
  public doughnutChartLabels: string[] = [];
  public doughnutChartDatasets: ChartConfiguration<'doughnut'>['data']['datasets'] = [
    { data: [] }
  ];
  public doughnutChartType: ChartType = 'doughnut';

  @Input() set labels(v: string[]) {
    this.doughnutChartLabels = v ?? [];
  }

  @Input() set data(values: number[]) {
    this.doughnutChartDatasets = [
      {
        data: values ?? [],
        backgroundColor: ['#22c55e', '#3b82f6', '#eab308', '#ef4444']
      }
    ];
  }

  public doughnutChartOptions: ChartConfiguration<'doughnut'>['options'] = {
    responsive: true,
    plugins: {
      legend: {
        labels: {
          color: '#e5e7eb'
        }
      }
    }
  };
}
EOF

cat > src/app/components/votes-chart/votes-chart.component.html << 'EOF'
<div class="bg-yelbCard rounded-2xl p-4 shadow-lg flex flex-col items-center h-full">
  <h2 class="text-lg font-semibold mb-2">Vote Distribution</h2>
  <canvas
    baseChart
    [data]="{ datasets: doughnutChartDatasets, labels: doughnutChartLabels }"
    [type]="doughnutChartType"
    [options]="doughnutChartOptions">
  </canvas>
</div>
EOF

cat > src/app/components/votes-chart/votes-chart.component.css << 'EOF'
:host {
  display: block;
}
EOF

cat > src/app/components/dashboard/dashboard.component.ts << 'EOF'
import { Component, OnDestroy, OnInit } from '@angular/core';
import { YelbApiService } from '../../services/yelb-api.service';
import { interval, Subject, switchMap, takeUntil } from 'rxjs';
import { VotesResponse } from '../../models/votes';

@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.component.html'
})
export class DashboardComponent implements OnInit, OnDestroy {
  private destroy$ = new Subject<void>();

  votes?: VotesResponse;
  totalVotes = 0;
  pageviews = 0;

  chartLabels = ['Outback', 'Buca di Beppo', 'IHOP', 'Chipotle'];
  chartData: number[] = [0, 0, 0, 0];

  loadingVote = false;
  errorMessage = '';

  constructor(private api: YelbApiService) {}

  ngOnInit(): void {
    this.refreshAll();

    interval(3000)
      .pipe(
        takeUntil(this.destroy$),
        switchMap(() => this.api.getVotes())
      )
      .subscribe({
        next: v => this.applyVotes(v),
        error: err => console.error('Polling error', err)
      });
  }

  private refreshAll(): void {
    this.api.getVotes().subscribe({
      next: v => this.applyVotes(v),
      error: err => console.error(err)
    });

    this.api.getStats().subscribe({
      next: s => {
        this.totalVotes = s.totalvotes;
        this.pageviews = s.pageviews;
      },
      error: err => console.error(err)
    });
  }

  private applyVotes(v: VotesResponse): void {
    this.votes = v;
    this.chartData = [v.outback, v.bucadibeppo, v.ihop, v.chipotle];
  }

  onVote(restaurant: 'ihop' | 'chipotle' | 'outback' | 'bucadibeppo'): void {
    this.loadingVote = true;
    this.errorMessage = '';

    this.api.vote(restaurant).subscribe({
      next: () => {
        this.loadingVote = false;
        this.refreshAll();
      },
      error: err => {
        this.loadingVote = false;
        this.errorMessage = 'Failed to submit vote';
        console.error(err);
      }
    });
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }
}
EOF

cat > src/app/components/dashboard/dashboard.component.html << 'EOF'
<div class="min-h-screen bg-yelbBg text-gray-100">
  <header class="border-b border-gray-800 px-8 py-4 flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-semibold tracking-tight">
        Yelb – Healthy Food Recommendations
      </h1>
      <p class="text-sm text-gray-400">
        Live voting dashboard backed by Postgres + Redis (HA).
      </p>
    </div>
    <div class="text-xs text-gray-400">
      Total pageviews:
      <span class="font-semibold text-gray-100">{{ pageviews }}</span>
    </div>
  </header>

  <main class="px-8 py-6 space-y-6">
    <!-- Top row: restaurant cards -->
    <section class="grid grid-cols-1 md:grid-cols-4 gap-4">
      <!-- IHOP -->
      <div class="bg-yelbCard rounded-2xl p-4 shadow-lg flex flex-col justify-between hover:border hover:border-yelbAccent transition">
        <div>
          <h2 class="text-lg font-semibold mb-1">IHOP</h2>
          <p class="text-xs text-gray-400 mb-3">
            Pancakes, for a powerful start.
          </p>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-2xl font-bold">
            {{ votes?.ihop ?? 0 }}
          </span>
          <button
            class="px-3 py-1.5 text-xs font-semibold rounded-full bg-yelbAccent hover:bg-yelbAccentSoft transition"
            [disabled]="loadingVote"
            (click)="onVote('ihop')">
            Vote
          </button>
        </div>
      </div>

      <!-- Chipotle -->
      <div class="bg-yelbCard rounded-2xl p-4 shadow-lg flex flex-col justify-between hover:border hover:border-yelbAccent transition">
        <div>
          <h2 class="text-lg font-semibold mb-1">Chipotle</h2>
          <p class="text-xs text-gray-400 mb-3">
            Burritos, for a mid-day break.
          </p>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-2xl font-bold">
            {{ votes?.chipotle ?? 0 }}
          </span>
          <button
            class="px-3 py-1.5 text-xs font-semibold rounded-full bg-yelbAccent hover:bg-yelbAccentSoft transition"
            [disabled]="loadingVote"
            (click)="onVote('chipotle')">
            Vote
          </button>
        </div>
      </div>

      <!-- Outback -->
      <div class="bg-yelbCard rounded-2xl p-4 shadow-lg flex flex-col justify-between hover:border hover:border-yelbAccent transition">
        <div>
          <h2 class="text-lg font-semibold mb-1">Outback</h2>
          <p class="text-xs text-gray-400 mb-3">
            Blooming onion, what else?
          </p>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-2xl font-bold">
            {{ votes?.outback ?? 0 }}
          </span>
          <button
            class="px-3 py-1.5 text-xs font-semibold rounded-full bg-yelbAccent hover:bg-yelbAccentSoft transition"
            [disabled]="loadingVote"
            (click)="onVote('outback')">
            Vote
          </button>
        </div>
      </div>

      <!-- Buca di Beppo -->
      <div class="bg-yelbCard rounded-2xl p-4 shadow-lg flex flex-col justify-between hover:border hover:border-yelbAccent transition">
        <div>
          <h2 class="text-lg font-semibold mb-1">Buca di Beppo</h2>
          <p class="text-xs text-gray-400 mb-3">
            Lasagne, this is heaven.
          </p>
        </div>
        <div class="flex items-center justify-between">
          <span class="text-2xl font-bold">
            {{ votes?.bucadibeppo ?? 0 }}
          </span>
          <button
            class="px-3 py-1.5 text-xs font-semibold rounded-full bg-yelbAccent hover:bg-yelbAccentSoft transition"
            [disabled]="loadingVote"
            (click)="onVote('bucadibeppo')">
            Vote
          </button>
        </div>
      </div>
    </section>

    <!-- Middle row: chart + summary -->
    <section class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <app-votes-chart
        class="md:col-span-2"
        [labels]="chartLabels"
        [data]="chartData">
      </app-votes-chart>

      <div class="bg-yelbCard rounded-2xl p-4 shadow-lg flex flex-col justify-between">
        <div>
          <h2 class="text-lg font-semibold mb-2">Summary</h2>
          <p class="text-xs text-gray-400 mb-4">
            Live snapshot of votes and traffic.
          </p>
          <div class="space-y-2 text-sm">
            <div class="flex justify-between">
              <span>Total votes</span>
              <span class="font-semibold">{{ totalVotes }}</span>
            </div>
            <div class="flex justify-between">
              <span>Page views</span>
              <span class="font-semibold">{{ pageviews }}</span>
            </div>
          </div>
        </div>
        <div *ngIf="errorMessage" class="mt-4 text-xs text-red-400">
          {{ errorMessage }}
        </div>
      </div>
    </section>
  </main>
</div>
EOF

cat > src/app/components/dashboard/dashboard.component.css << 'EOF'
:host {
  display: block;
}
EOF

echo "==> Updating AppModule and root component"

cat > src/app/app.module.ts << 'EOF'
import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';
import { HttpClientModule } from '@angular/common/http';
import { NgChartsModule } from 'ng2-charts';

import { AppComponent } from './app.component';
import { DashboardComponent } from './components/dashboard/dashboard.component';
import { VotesChartComponent } from './components/votes-chart/votes-chart.component';

@NgModule({
  declarations: [
    AppComponent,
    DashboardComponent,
    VotesChartComponent
  ],
  imports: [
    BrowserModule,
    HttpClientModule,
    NgChartsModule
  ],
  providers: [],
  bootstrap: [AppComponent]
})
export class AppModule {}
EOF

cat > src/app/app.component.html << 'EOF'
<app-dashboard></app-dashboard>
EOF

echo "==> Writing Dockerfile and nginx.conf"

cat > Dockerfile << 'EOF'
# Stage 1: build Angular app
FROM node:20-bullseye AS build

WORKDIR /app
COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build -- --configuration production

# Stage 2: nginx to serve static files
FROM nginx:1.27-alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/yelb-ui.conf
COPY --from=build /app/dist/yelb-ui-ng/browser /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

cat > nginx.conf << 'EOF'
server {
    listen       80;
    server_name  _;

    root   /usr/share/nginx/html;
    index  index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Proxy API calls into the yelb-appserver service on the Docker network
    location /api {
        proxy_pass         http://yelb-appserver:4567/api;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
    }
}
EOF

cat > .dockerignore << 'EOF'
node_modules
.git
dist
.gitignore
npm-debug.log
Dockerfile*
EOF

echo "==> Done."
echo "Next steps:"
echo "  1) cd ${APP_NAME}"
echo "  2) npm run serve (for local dev) or build/push Docker image:"
echo "       docker buildx build --platform linux/amd64,linux/arm64 -t <youruser>/yelb-ui-ng:v1 --push ."
echo "  3) Point docker-compose yelb-ui service to that image."

