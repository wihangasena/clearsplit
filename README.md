# ClearSplit

A Splitwise-style shared-expense tracker. Friends and groups record costs, split
them (equal / exact / percentage), and track who owes whom until every debt is
settled.

- **Frontend:** Flutter (web + mobile), Material 3, `ChangeNotifier` state.
- **Backend:** Node.js (Express) + the official `mongodb` native driver.
- **Storage:** MongoDB Atlas (single source of truth).

> **Architecture note.** The original spec (`REQUIREMENTS.md`) described a Dart
> Shelf backend. This build implements the **same REST contract** (§7) in
> **Node.js** per the project's database-driver decision, persisting to the
> provided MongoDB Atlas cluster. The Flutter client is backend-agnostic.

---

## Prerequisites

| Tool        | Version            |
|-------------|--------------------|
| Flutter SDK | ≥ 3.x (Dart ^3.11) |
| Node.js     | ≥ 20               |
| MongoDB     | Atlas URI (provided in `backend/.env`) |

---

## Quick start

### Windows (one command)

```powershell
npm run dev
# or: powershell -ExecutionPolicy Bypass -File tool/dev.ps1
```

Starts the backend (new window), waits for `/health`, then launches Flutter on
Chrome.

### Manual (2 terminals)

```bash
# Terminal 1 — backend
cd backend
npm install
npm start          # → http://127.0.0.1:8081

# Terminal 2 — frontend
flutter pub get
flutter run -d chrome
```

### Sign in

Four demo accounts, password **`demo123`** (tap a tile on the login screen):

| Email                | Name   |
|----------------------|--------|
| you@clearsplit.app   | Riley  |
| alex@clearsplit.app  | Alex   |
| maya@clearsplit.app  | Maya   |
| jordan@clearsplit.app| Jordan |

Or **Sign up** to register a real member. Registered members start with an empty
ledger and can be found by anyone via member search when creating a group, adding
a participant to an expense, or managing group members. Adding a member fans the
group out to their account, so they see it on their next sign-in.

---

## Configuration

### Backend — `backend/.env` (gitignored)

| Variable           | Default       | Description                              |
|--------------------|---------------|------------------------------------------|
| `MONGODB_URI`      | _(required)_  | MongoDB Atlas connection string          |
| `MONGO_DB`         | `clearsplit`  | Database name                            |
| `MONGO_COLLECTION` | `app_states`  | Collection holding per-user state        |
| `BACKEND_PORT`     | `8081`        | HTTP port                                |
| `BACKEND_HOST`     | `0.0.0.0`     | Bind address                             |
| `CORS_ORIGIN`      | `*`           | Allowed origin (restrict in production)  |

Copy `backend/.env.example` → `backend/.env` and fill it in.

### Frontend

The backend URL is auto-detected (`10.0.2.2` on Android emulator, `127.0.0.1`
otherwise). Override at run time:

```bash
flutter run -d chrome --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8081
```

---

## API (`http://127.0.0.1:8081`)

| Method | Path                                            | Purpose                          |
|--------|-------------------------------------------------|----------------------------------|
| GET    | `/health`                                       | Health check                     |
| GET    | `/accounts`                                     | Demo accounts                    |
| GET    | `/members?q=&excludeId=`                         | Search member directory          |
| POST   | `/auth/login`                                   | Sign in (+ seed on first login)  |
| POST   | `/auth/register`                                | Register a new member            |
| POST   | `/auth/logout`                                  | No-op logout                     |
| POST   | `/groups/:groupId/sync`                         | Fan out group membership         |
| GET    | `/state/:userId`                                | Fetch persisted state            |
| PUT    | `/state/:userId`                                | Overwrite state                  |
| POST   | `/state/:userId/reset`                          | Re-seed to demo data             |
| POST   | `/groups/:groupId/settlements`                  | Record settlement (fan-out)      |
| POST   | `/groups/:groupId/expenses/:expenseId/settle`   | Settle an expense (fan-out)      |
| PATCH  | `/profile/:userId`                              | Update profile (fan-out)         |

---

## Project layout

```
backend/            Node + Express + MongoDB API
  src/
    config.js       validated env config
    db/             Mongo client + state data-access (fan-out)
    domain/         demo accounts, seed data, balance/settlement algorithms
    routes/         REST endpoints
    middleware/     CORS, validation, error handling
  test/             domain unit tests (node --test)
lib/                Flutter app
  app_state.dart    models + AppController (business logic)
  backend_client.dart  REST client (+ ClearSplitApi interface for tests)
  app_shell.dart    tabs + detail screens
  screens/          login, edit profile, modal sheets
  widgets/          shared UI
test/               Flutter tests
tool/dev.ps1        full-stack launcher
```

---

## Tests

```bash
npm test            # backend (node --test) + flutter test
# or individually:
cd backend && npm test        # backend only
flutter test                  # frontend only
flutter analyze               # static analysis (zero issues)
```

---

## How balances work

- **Per-friend balance** is the *pairwise* net between you and each person
  (positive = they owe you). The sum of all pairwise nets equals your overall
  net, so "you are owed / you owe" always reconciles.
- **Simplify debts** uses greedy creditor↔debtor matching on each group's
  multilateral net to produce the minimum set of payments.

The same algorithm is implemented in both `lib/app_state.dart` and
`backend/src/domain/balances.js` (covered by tests on both sides) so the client
can compute balances offline and the server stays authoritative.
