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
│   ├── config/           # Sequelize config, subscription plan definitions
│   ├── controllers/      # Request handlers per resource
│   ├── middleware/       # JWT auth / role checks
│   ├── migrations/       # Sequelize migrations
│   ├── models/           # Sequelize models + associations
│   ├── routes/           # Express routers mounted under /api
│   ├── server.js         # App entry point
│   ├── Dockerfile, docker-compose.yaml, render.yaml
│   └── .env.example
└── inventory_frontend/   # Flutter client
    ├── lib/
    │   ├── models/       # Dart data models
    │   ├── providers/    # State management (provider package)
    │   ├── screens/      # admin/, owner/, salesman/, auth/, business/
    │   ├── services/     # API services
    │   ├── utils/        # API helper, storage, theme
    │   └── widgets/      # Reusable UI components
    ├── assets/           # images, icons
    └── .env.example
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
- PDF generation and printing, QR codes
- English and Amharic localization
- Subscription plans with Stripe payments and webhooks

## Tech stack

**Backend:** Node.js (ES modules), Express 4, Sequelize 6, PostgreSQL (`pg`), JWT (`jsonwebtoken`), bcrypt, Stripe, dotenv, nodemon.

**Frontend:** Flutter (Dart SDK ^3.7.2), provider, http/dio, shared_preferences, flutter_secure_storage, jwt_decoder, fl_chart, pdf/printing, qr_flutter, image_picker, intl, flutter_dotenv, flutter_localizations.

## API overview

All routes are mounted in [inventory_backend/server.js](inventory_backend/server.js):

| Prefix | Resource |
|--------|----------|
| `/api/auth` | Login, registration, password reset/change |
| `/api/users` | Users (owners, salesmen) |
| `/api/businesses` | Businesses (tenants) |
| `/api/shops` | Shops in a business |
| `/api/categories` | Item categories |
| `/api/items` | Items |
| `/api/fractions` | Sellable units/fractions of an item and their prices |
| `/api/boughts` | Purchases (stock in) |
| `/api/available-items` | Current stock per shop |
| `/api/sales` | Sales (stock out) |
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

Or with Docker (starts Postgres and the API together):

```bash
cd inventory_backend
docker compose up --build   # API on :5000, Postgres on host port 5433
```

Environment variables (see [inventory_backend/.env.example](inventory_backend/.env.example)): `DATABASE_URL`, `JWT_SECRET`, `JWT_EXPIRES_IN`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `FRONTEND_URL`.

### Frontend

```bash
cd inventory_frontend
cp .env.example .env        # required: .env is bundled as an asset
flutter pub get
flutter run
```

## Known notes

- `server.js` always listens on port **5000** and ignores `PORT`.
- If `JWT_SECRET` or `DATABASE_URL` is missing, the server falls back to insecure development defaults.
- The frontend's API base URL is hardcoded in two places: [lib/config.dart](inventory_frontend/lib/config.dart) (`http://localhost:5000/api`) and [lib/main.dart](inventory_frontend/lib/main.dart) (`BusinessService` → `https://54.91.234.164:5000/api`). Change both when you point the app at a different backend.
- The Render deploy ([render.yaml](inventory_backend/render.yaml)) deploys the `development` branch.
- `.env` files are git-ignored. Copy them from the `.env.example` files.
