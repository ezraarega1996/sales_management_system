# Inventory Management System (Multi-tenant)

An inventory and sales management system that serves many businesses from one deployment. Each **business** (tenant) can run several **shops**. Owners manage stock and staff, and salesmen record sales. A platform **admin** oversees all businesses.

```
┌──────────────────────┐   HTTPS / JSON (JWT)   ┌──────────────────────┐      ┌────────────┐
│  inventory_frontend  │ ─────────────────────▶ │  inventory_backend   │ ───▶ │ PostgreSQL │
│  Flutter app         │      /api/*            │  Node.js + Express   │      │            │
│  (Android/iOS/Web/…) │                        │  Sequelize ORM       │      └────────────┘
└──────────────────────┘                        │  Stripe (payments)   │
                                                └──────────────────────┘
```

## Repository layout

```
projects/
├── inventory_backend/    # REST API (Node.js, Express, Sequelize, PostgreSQL)
│   ├── config/           # Subscription plan definitions
│   ├── controllers/      # Request handlers per resource
│   ├── middleware/       # JWT auth / role checks
│   ├── models/           # Sequelize models + associations (schema synced on startup)
│   ├── routes/           # Express routers mounted under /api
│   ├── server.js         # App entry point
│   ├── seed.js           # Sample data (npm run seed)
│   ├── Dockerfile, docker-compose.yaml, render.yaml
│   └── .env.example
└── inventory_frontend/   # Flutter client
    ├── lib/
    │   ├── models/       # Dart data models
    │   ├── providers/    # State management (provider package)
    │   ├── screens/      # admin/, owner/, salesman/, auth/
    │   ├── services/     # Business API, offline sales queue
    │   ├── utils/        # API client, offline cache, connection status, storage
    │   └── widgets/      # Reusable UI components
    ├── assets/           # images
    └── test/             # unit tests
```

## User roles and features

| Role | What they can do |
|------|------------------|
| **Admin** | Platform dashboard. View and manage all businesses and users. |
| **Owner** | Register a business, manage shops, users (salesmen), categories, items and fractions (sellable units and prices), record purchases ("boughts"), view sales, transactions, summaries and charts, and manage the subscription. |
| **Salesman** | View available items in their shop, sell items, view own sales and transactions, see a sales summary. |

Other features:
- Authentication with JWT, password change and reset
- Per-shop stock ("available items") that purchases add to and sales take from
- Sales summaries with date filters and charts (`fl_chart`)
- Works on weak or no connection: salesmen keep selling offline (sales are queued on the phone and synced automatically), and screens show the last saved data
- English and Amharic localization
- Subscription plans with Stripe payments and webhooks

## Tech stack

**Backend:** Node.js (ES modules), Express 4, Sequelize 6, PostgreSQL (`pg`), JWT (`jsonwebtoken`), bcrypt, Stripe, dotenv, nodemon.

**Backend extras:** gzip `compression`.

**Frontend:** Flutter (Dart SDK ^3.7.2), provider, http, shared_preferences (session, offline cache, sales queue), uuid, fl_chart, intl, url_launcher, flutter_localizations.

## API overview

All routes are mounted in [inventory_backend/server.js](inventory_backend/server.js):

| Prefix | Resource |
|--------|----------|
| `/api/auth` | Login, change password |
| `/api/users` | Users (owners, salesmen) |
| `/api/businesses` | Businesses (tenants) |
| `/api/shops` | Shops in a business |
| `/api/categories` | Item categories |
| `/api/items` | Items |
| `/api/fractions` | Sellable units/fractions of an item and their prices |
| `/api/boughts` | Purchases (stock in) |
| `/api/available-items` | Current stock per shop; `/:id/transactions` for one item's purchase/sale history |
| `/api/sales` | Sales (stock out). `POST` is idempotent via a client-generated `clientId` |
| `/api/payments` | Stripe subscription payments (`/webhook` uses the raw request body) |

## Data model

Defined in [inventory_backend/models/](inventory_backend/models/):

- **Business**: the tenant
- **Shop**: belongs to a business
- **User**: role `admin` | `owner` | `salesman`, linked to a business and optionally to a shop
- **Category**, **Item**, **Fraction**: the product catalog
- **ItemBought**: purchase records
- **AvailableItem**: stock on hand
- **SoldItem**: sales records
- **Subscription**: a business's plan

## Subscription plans

Defined in [inventory_backend/config/subscriptionPlans.js](inventory_backend/config/subscriptionPlans.js):

| Plan | Price (USD/mo) | Users | Items | Data retention |
|------|---------------|-------|-------|----------------|
| Free | 0 | 3 | 50 | 7 days |
| Basic | 9.99 | 6 | 200 | 30 days |
| Premium | 29.99 | 18 | 1000 | 90 days |
| Enterprise | 99.99 | 10 owners + unlimited salesmen | Unlimited | Unlimited |

## Getting started

### Backend

```bash
cd inventory_backend
cp .env.example .env        # fill in DATABASE_URL, JWT_SECRET, Stripe keys
npm install
npm run dev                 # nodemon server.js on http://localhost:5000
```

Load sample data (2 businesses, 3 shops, all roles, catalog, purchases and ~200 sales over the last 14 days):

```bash
npm run seed              # adds sample data next to existing data
npm run seed -- --reset   # WIPES all tables first, then seeds
```

| Role | Username | Password |
|------|----------|----------|
| Admin | `admin` | `admin123` |
| Owner (Addis Mini Market) | `owner1` | `owner123` |
| Salesman (Bole Branch) | `sales1`, `sales2` | `sales123` |
| Salesman (Piassa Branch) | `sales3` | `sales123` |
| Owner (Hawassa Pharmacy) | `owner2` | `owner123` |
| Salesman (Hawassa Main Shop) | `sales4` | `sales123` |

Or with Docker (starts Postgres and the API together):

```bash
cd inventory_backend
docker compose up --build   # API on :5000, Postgres on host port 5433
```

Environment variables (see [inventory_backend/.env.example](inventory_backend/.env.example)): `DATABASE_URL`, `JWT_SECRET`, `JWT_EXPIRES_IN`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `FRONTEND_URL`.

### Frontend

```bash
cd inventory_frontend
flutter pub get
flutter run                                               # uses the default backend URL in lib/config.dart
flutter run --dart-define=API_URL=https://api.example.com/api   # or point a build at another backend
```

Run the tests with `flutter test`.

## Working offline / weak connections

- **Requests time out** (15 s reads, 20 s writes) instead of hanging; reads retry twice with backoff.
- **Saved data:** every list the app loads is cached on the phone per user, so screens still show the last known data with an "Offline" banner.
- **Sales queue** ([lib/services/sale_outbox.dart](inventory_frontend/lib/services/sale_outbox.dart)): a sale is saved on the phone first and stock on screen is reduced immediately. It is sent in the background right away, every 30 s while waiting, when the app is reopened, and when the connection returns. Each sale carries a `clientId`, so a retry after a lost response is never recorded twice. Sales the server rejects (e.g. not enough stock) are shown in Sales History with Retry/Discard.
- **Smaller downloads:** the server gzips responses and `/available-items` no longer embeds the full history (about 66x smaller on the wire with the sample data).

## Known notes

- The server listens on `PORT` (default 5000). If `JWT_SECRET` is missing it falls back to an insecure development default.
- In production (`NODE_ENV=production`) the server only creates missing tables; schema changes such as the new `SoldItems.clientId` column must be applied to an existing production database manually.
- The frontend's backend address is `baseUrl` in [lib/config.dart](inventory_frontend/lib/config.dart), overridable with `--dart-define=API_URL=...`. The default is a LAN IP, which only works on the same Wi-Fi.
- The subscription screen calls `subscription/plans` and `subscription/checkout`, which the backend does not serve (it has `/payments/plans` and `/payments/create-checkout-session` with a different response shape).
- The Render deploy ([render.yaml](inventory_backend/render.yaml)) deploys the `development` branch.
- `inventory_backend/.env` is git-ignored. Copy it from `.env.example`.
