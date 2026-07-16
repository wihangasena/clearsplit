
# ClearSplit — Product & Technical Requirements

> **Document type:** Combined BA + Developer Reference  
> **App name:** ClearSplit (repository: `buddysplit_flutter`)  
> **Product direction:** Splitwise-style shared-expense tracker  
> **Last updated:** 2026-06-12  

---

## Table of Contents

1. [Product Overview](#1-product-overview)  
2. [Functional Requirements](#2-functional-requirements)  
3. [Non-Functional Requirements](#3-non-functional-requirements)  
4. [Data Models](#4-data-models)  
5. [Tech Stack](#5-tech-stack)  
6. [Architecture](#6-architecture)  
7. [API Contract](#7-api-contract)  
8. [Screens & Navigation](#8-screens--navigation)  
9. [State Management](#9-state-management)  
10. [Persistence & Sync](#10-persistence--sync)  
11. [Balance & Settlement Algorithm](#11-balance--settlement-algorithm)  
12. [Demo / Seed Data](#12-demo--seed-data)  
13. [Testing](#13-testing)  
14. [Dev Setup & Scripts](#14-dev-setup--scripts)  
15. [Environment Variables](#15-environment-variables)  
16. [Known Limitations & Future Work](#16-known-limitations--future-work)  

---

## 1. Product Overview

**ClearSplit** is a Splitwise-style shared-expense tracking application. Friends and groups record costs, split them by configurable rules, and track who owes whom until every debt is settled.

| Attribute | Value |
|-----------|-------|
| Platform | Flutter (mobile + web) |
| Target OS | Android, iOS, Chrome/Web |
| Backend | Dart (Shelf HTTP server) |
| Storage | Local JSON file (default) + MongoDB (optional cloud) |
| Authentication | Demo-account based (no real identity provider) |
| Design System | Material Design 3 (Material3) |

### Core Value Propositions

- **Frictionless splitting** — add an expense in seconds; choose equal, exact-amount, or percentage splits.  
- **Friends & groups** — track balances one-on-one with friends or inside groups (trips, households, etc.), each group with its own expense ledger.  
- **Live balances** — see exactly who owes you and who you owe, overall and per friend/group.  
- **Simplify debts** — minimise the number of payments needed to clear a group.  
- **Settle up with one tap** — record a payment to a friend or settle an entire group at once.  
- **Cross-device sync** — optional MongoDB backend syncs state across all demo users.

---

## 2. Functional Requirements

### 2.1 Authentication

| ID | Requirement |
|----|-------------|
| AUTH-01 | User must be able to sign in with an email and password. |
| AUTH-02 | System must provide 4 pre-configured demo accounts with password `demo123`. |
| AUTH-03 | Login screen must display quick-tap demo account tiles that auto-submit. |
| AUTH-04 | On sign-in the backend returns the account's persisted state (or seeds a fresh one). |
| AUTH-05 | User must be able to sign out; local state is cleared on sign-out. |

### 2.2 Profile Management

| ID | Requirement |
|----|-------------|
| PROF-01 | User must be able to edit their display name. |
| PROF-02 | User must be able to choose an avatar (emoji). |
| PROF-03 | User must be able to choose a profile color from a predefined palette. |
| PROF-04 | Profile changes must be persisted to the backend and reflected to all group members. |

### 2.3 Friends

| ID | Requirement |
|----|-------------|
| FRND-01 | Friends screen must list every contact the user shares at least one expense or group with. |
| FRND-02 | Each friend row must show the net balance with that friend ("owes you $X" / "you owe $X" / "settled up"). |
| FRND-03 | Friends screen header must show the user's overall balance ("Overall, you are owed $X"). |
| FRND-04 | Tapping a friend opens a friend detail view listing all shared expenses and settlements with that friend. |
| FRND-05 | User must be able to add an expense with a friend directly (no group required). |
| FRND-06 | User must be able to settle up with a friend directly from the friend detail view. |

### 2.4 Groups

| ID | Requirement |
|----|-------------|
| GRP-01 | User must be able to create a group with a name and emoji. |
| GRP-02 | User must be able to add existing contacts as members of a group. |
| GRP-03 | Group detail screen must show all members, total tracked spend, and per-member balances. |
| GRP-04 | Each group maintains its own expense ledger. |

### 2.5 Expenses

| ID | Requirement |
|----|-------------|
| EXP-01 | User must be able to add a shared expense with: title, amount, category, group (optional), payer, participants, split method, date, and optional note. |
| EXP-02 | User must be able to add a non-group expense shared with one or more friends. |
| EXP-03 | System must support three split methods: **equal**, **exact amount**, **percentage**. |
| EXP-04 | Expenses must be viewable by group (group detail) or by friend (friend detail). |
| EXP-05 | User must be able to mark an individual expense as settled. |
| EXP-06 | Expenses show the payer's avatar, title, amount, category emoji, and date in list views. |

### 2.6 Balances

| ID | Requirement |
|----|-------------|
| BAL-01 | System must calculate net balance for each person relative to the signed-in user. |
| BAL-02 | System must display total "You are owed" and "You owe" aggregates. |
| BAL-03 | Balances must update in real time when expenses or settlements are added/changed. |
| BAL-04 | Group detail must show each member's net position within the group. |

### 2.7 Settle Up & Simplify Debts

| ID | Requirement |
|----|-------------|
| SET-01 | System must compute the minimum set of payments needed to clear a group's debts (greedy creditor–debtor matching, "simplify debts"). |
| SET-02 | User must be able to record a payment ("I paid Alex $30") that reduces the outstanding balance. |
| SET-03 | User must be able to settle all outstanding debts in a group with one action. |
| SET-04 | Settlement actions must fan out to all group members' persisted states simultaneously. |
| SET-05 | System must reject settlements with a non-positive amount. |

### 2.8 Activity Feed

| ID | Requirement |
|----|-------------|
| ACT-01 | Activity screen shows all shared expenses and settlements ordered by date (TODAY / EARLIER sections). |
| ACT-02 | Each entry shows the actor's avatar, a description ("Alex added 'Groceries'", "You paid Maya $20"), the amount, and its effect on your balance. |

---

## 3. Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-01 | Performance | Balance computations must complete in < 50 ms for up to 50 expenses. |
| NFR-02 | Responsiveness | UI must be usable on phones (360 dp+) and Chrome desktop. |
| NFR-03 | Offline | App must display last-known state when backend is unreachable. |
| NFR-04 | Security | CORS headers are open (`*`) for demo; restrict to frontend origin in production. |
| NFR-05 | Maintainability | Each screen is a distinct widget class; business logic lives in `AppController`, not widgets. |
| NFR-06 | Testability | `AppController` must be constructable in tests without a running server (via fake backend). |
| NFR-07 | Extensibility | MongoDB integration is optional; app works fully with local JSON storage. |

---

## 4. Data Models

All models are defined in `lib/app_state.dart` and are JSON-serializable.

### 4.1 Person

```dart
class Person {
  String id;
  String name;
  String avatar;   // emoji, e.g. "🙂"
  String color;    // hex color, e.g. "#2563EB"
}
```

### 4.2 Group

```dart
class Group {
  String id;
  String name;
  String emoji;
  List<String> members;  // list of Person.id
}
```

### 4.3 Expense

```dart
class Expense {
  String id;
  String title;
  double amount;
  String paidBy;               // Person.id
  List<String> participants;   // Person.id list
  String? groupId;             // null = non-group (friend) expense
  String category;             // e.g. "food", "transport"
  DateTime date;
  String? note;
  String splitMethod;          // 'equal' | 'amount' | 'percentage'
  Map<String, double> splits;  // personId → share
  bool settled;
}
```

`getParticipantShare(personId)` → resolves share based on `splitMethod`:
- `equal`: `amount / participants.length`
- `amount`: `splits[personId]`
- `percentage`: `amount * splits[personId] / 100`

### 4.4 Settlement

```dart
class Settlement {
  String id;
  String? groupId;  // null = direct friend settlement
  String from;      // Person.id (debtor)
  String to;        // Person.id (creditor)
  double amount;
  DateTime date;
}
```

### 4.5 AppData (Root State)

```dart
class AppData {
  String me;                    // current user's Person.id
  List<Person> people;
  List<Group> groups;
  List<Expense> expenses;
  List<Settlement> settlements;
}
```

`AppData.seedForAccount(account)` generates a full starting state for any demo account, including groups and shared expenses.

### 4.6 BalanceSummary

```dart
class BalanceSummary {
  double owed;    // total others owe me
  double owe;     // total I owe others
  double net;     // owed - owe
  Map<String, double> perPerson;  // personId → net balance (positive = they owe me)
}
```

### 4.7 DemoAccount

```dart
class DemoAccount {
  String id;
  String displayName;
  String email;
  String password;
  String avatar;
  String color;
}
```

---

## 5. Tech Stack

### Frontend

| Technology | Version | Role |
|-----------|---------|------|
| **Flutter** | SDK ≥ 3.x | UI framework (Material3) |
| **Dart** | ^3.11.5 | Language |
| `http` | ^1.2.2 | HTTP client (calls backend REST API) |
| `cupertino_icons` | ^1.0.8 | iOS-style icon set |
| `flutter_lints` | ^6.0.0 | Static analysis |

**State management:** Flutter built-in `ChangeNotifier` + `ListenableBuilder` — no external state library.

### Backend

| Technology | Version | Role |
|-----------|---------|------|
| **Dart** | ^3.11.5 | Language |
| `shelf` | ^1.4.2 | HTTP server framework |
| `shelf_router` | ^1.1.4 | Route definitions |
| `mongo_dart` | ^0.10.8 | MongoDB driver (optional cloud sync) |

### Storage

| Layer | Technology | When used |
|-------|-----------|-----------|
| Local | JSON flat file (`backend/data/state_store.json`) | Always (default) |
| Remote | MongoDB Atlas (or local `mongod`) | When `MONGO_URI` env var is set |

### Tooling

| Tool | Purpose |
|------|---------|
| PowerShell (`tool/dev.ps1`) | Full-stack dev launcher (Windows) |
| `package.json` npm scripts | Shortcuts for `backend`, `dev`, `build`, `test` |
| `analysis_options.yaml` | Dart lint rules |

---

## 6. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App (Web / Mobile)               │
│                                                                   │
│  ┌───────────────┐    ┌────────────────┐   ┌────────────────┐   │
│  │  UI Widgets   │───▶│  AppController │───▶│ BackendClient  │   │
│  │  (app_shell)  │    │  (app_state)   │   │  (http calls)  │   │
│  └───────────────┘    └────────────────┘   └───────┬────────┘   │
│         ▲                     │                     │            │
│         └──── notifyListeners ┘                     │            │
└─────────────────────────────────────────────────────┼───────────┘
                                                       │ HTTP :8081
┌──────────────────────────────────────────────────────▼──────────┐
│                      Dart Shelf Backend                          │
│                                                                   │
│  ┌───────────────┐    ┌────────────────┐   ┌────────────────┐   │
│  │  HTTP Routes  │───▶│  BackendStore  │───▶│   MongoDB      │   │
│  │  (shelf_router│    │  (state_store  │   │  (optional)    │   │
│  │  + CORS mw)   │    │  .json)        │   │                │   │
│  └───────────────┘    └────────────────┘   └────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| ChangeNotifier over Riverpod/BLoC | Zero extra dependencies, sufficient for demo scale |
| Dart Shelf backend instead of Node/Go | Single language across full stack, easier to share models |
| Fan-out writes on settlement | Ensures all group members see consistent state without a pub/sub system |
| Local JSON as primary storage | Works with zero infrastructure; MongoDB is opt-in for multi-device testing |
| Hardcoded demo accounts | Eliminates auth infrastructure complexity for demo/prototype phase |

---

## 7. API Contract

**Base URL:** `http://127.0.0.1:8081` (web/desktop) or `http://10.0.2.2:8081` (Android emulator)  
**Content-Type:** `application/json`  
**CORS:** Open (`*`) — all methods allowed

### Endpoints

#### `GET /health`
Health check. Returns `{"status": "ok"}`.

---

#### `GET /accounts`
Returns the list of demo accounts (passwords included for demo purposes).

**Response:**
```json
{ "accounts": [{ "id": "...", "email": "...", "displayName": "...", "avatar": "...", "color": "..." }] }
```

---

#### `POST /auth/login`
Authenticate a user and retrieve their state.

**Request body:**
```json
{ "email": "you@clearsplit.app", "password": "demo123" }
```

**Response:**
```json
{ "account": { "id": "...", "displayName": "...", "avatar": "...", "color": "..." },
  "state": { "me": "...", "people": [...], "groups": [...], "expenses": [...], "settlements": [...] } }
```

**Error (401):** `{ "message": "Invalid credentials" }`

---

#### `GET /state/<userId>`
Fetch the current persisted state for a user.

**Response:** `{ "state": { ...AppData... } }`  
**Error (404):** `{ "message": "State not found" }`

---

#### `PUT /state/<userId>`
Overwrite the persisted state for a user.

**Request body:** `{ "state": { ...AppData... } }`  
**Response:** `{ "state": { ...AppData... } }`

---

#### `POST /groups/<groupId>/settlements`
Record a settlement payment and fan out to all group members' states.

**Request body:**
```json
{ "requesterId": "user-id", "settlement": { "id": "...", "from": "...", "to": "...", "amount": 30.0, "date": "..." } }
```

**Response:** `{ "state": { ...AppData for requester... } }`

---

#### `POST /groups/<groupId>/expenses/<expenseId>/settle`
Mark an expense as settled and fan out to all group members.

**Request body:** `{ "requesterId": "user-id" }`  
**Response:** `{ "state": { ...AppData for requester... } }`

---

#### `PATCH /profile/<userId>`
Update profile fields (name, avatar, color).

**Request body:**
```json
{ "displayName": "New Name", "avatar": "😎", "color": "#FF5733" }
```

**Response:** `{ "state": { ...AppData... } }`

---

#### `POST /auth/logout`
No-op logout endpoint.

**Response:** `{ "status": "ok" }`

---

## 8. Screens & Navigation

Navigation uses Flutter's `Navigator.push` with `MaterialPageRoute` (no Go Router or AutoRoute). The tab layout mirrors Splitwise: **Friends · Groups · Activity · Account**, with a center-docked "Add expense" button.

### Navigation Flow

```
SessionGate
├── [not signed in] → LoginScreen
└── [signed in]     → AppBootstrap → ClearSplitHome (bottom nav)
                                          ├── Tab 0: FriendsScreen
                                          ├── Tab 1: GroupsScreen
                                          ├── Tab 2: ActivityScreen
                                          └── Tab 3: AccountScreen

Modal sheets (showModalBottomSheet):
  - showCreateGroupSheet()
  - showAddExpenseSheet()
  - showManageMembersSheet()
  - showSettleUpSheet()

Pushed routes (Navigator.push):
  - FriendDetailScreen  (from FriendsScreen)
  - GroupDetailScreen   (from GroupsScreen)
  - EditProfileScreen   (from AccountScreen)
```

### Screen Descriptions

| Screen | File | Description |
|--------|------|-------------|
| **LoginScreen** | `lib/screens/login_screen.dart` | Email/password form; quick-tap demo account tiles |
| **ClearSplitHome** | `lib/app_shell.dart` | Shell with 4-tab bottom nav and center "Add expense" FAB |
| **FriendsScreen** | `lib/app_shell.dart` | Overall balance header; per-friend balance list |
| **GroupsScreen** | `lib/app_shell.dart` | List of all groups with per-group balance; create group button |
| **ActivityScreen** | `lib/app_shell.dart` | Chronological feed of expenses and settlements |
| **AccountScreen** | `lib/app_shell.dart` | User hero, settings stubs, reset & sign-out |
| **FriendDetailScreen** | `lib/app_shell.dart` | Friend balance, shared expense history, settle-up action |
| **GroupDetailScreen** | `lib/app_shell.dart` | Group hero, member balances, simplify-debts/settle-up section, expense list |
| **EditProfileScreen** | `lib/screens/edit_profile_screen.dart` | Name, avatar emoji, color picker |

### FAB Behavior

The center-docked FAB in `ClearSplitHome` opens the add-expense sheet (`showAddExpenseSheet()`) on tap. It is always visible regardless of active tab.

---

## 9. State Management

**Class:** `AppController` (extends `ChangeNotifier`)  
**Location:** `lib/app_state.dart`  
**Injected via:** `ListenableBuilder` at the widget tree root

### State Fields

| Field | Type | Description |
|-------|------|-------------|
| `_state` | `AppData?` | Full application state; null when signed out |
| `_activeAccount` | `DemoAccount?` | Signed-in account metadata |

### Key Methods

| Method | Description |
|--------|-------------|
| `signIn(email, password)` | Calls backend, sets `_state` + `_activeAccount`, notifies |
| `signOut()` | Clears state, calls backend logout |
| `addExpense(Expense)` | Appends expense, saves state |
| `createGroup(name, emoji)` | Creates group with current user as first member |
| `addMemberToGroup(groupId, personId)` | Adds member, saves state |
| `computeBalances()` | Returns `BalanceSummary` (pure calculation, no side effects) |
| `computeGroupSettlements(groupId)` | Returns minimum payment map (simplify debts) |
| `markSettled(expenseId)` | Marks expense settled via backend fan-out |
| `recordSettlement(groupId, settlement)` | Records payment via backend fan-out |
| `settleAllForGroup(groupId)` | Calls `recordSettlement` for every pending debt in group |
| `updateProfile(name, avatar, color)` | Patches profile via backend |
| `resetCurrentAccount()` | Re-seeds state to initial demo data |

### Data Flow

```
User action (tap button)
  → Widget calls AppController method
    → Method mutates _state
    → Method calls BackendClient (HTTP PUT or POST)
      → Backend persists + fans out
      → Backend returns updated state
    → AppController replaces _state with response
    → notifyListeners()
      → Dependent widgets rebuild
```

---

## 10. Persistence & Sync

### Local Storage

- File: `backend/data/state_store.json`
- Format: `{ "userId1": { ...AppData... }, "userId2": { ... } }`
- Loaded lazily on first access (`_ensureLoaded`)
- Written synchronously after every mutation

### MongoDB (Optional)

- Enabled when `MONGO_URI` environment variable is set
- Collection: `MONGO_COLLECTION` env var (default: `app_states`)
- Document schema: `{ "_id": userId, "state": { ...AppData... } }`
- Upsert semantics: create if absent, update if present
- BSON type normalisation: `ObjectId` → hex string, `Int64` → `int`, `DateTime` → milliseconds since epoch

### Sync Strategy

| Event | Local JSON | MongoDB |
|-------|-----------|---------|
| Login | Read (or seed if absent) | Read and merge into local (if available) |
| Save state | Write | Write (best-effort) |
| Settlement / settle expense | Fan-out write to all members | Fan-out write to all members |

### Fan-out Logic

When a settlement or expense-settle action is triggered:

1. Identify all members of the affected group from `state_store.json`.
2. For each member, load their state, apply the mutation, save locally (and remotely if MongoDB is available).
3. Return the **requester's** updated state to the caller.

This ensures multi-user demo consistency without a real-time connection.

---

## 11. Balance & Settlement Algorithm

### `computeBalances()` — Personal Ledger

```
balances = {} (personId → net)

for each unsettled expense:
  payer gets credited: balances[paidBy] += amount
  each participant pays their share: balances[participantId] -= share

for each recorded settlement:
  from-person reduces debt: balances[from] += amount
  to-person reduces credit: balances[to] -= amount

relative to "me":
  BalanceSummary.perPerson[id] = balances[id] - balances[me]
    (positive → they owe me, negative → I owe them)
```

### `computeGroupSettlements(groupId)` — Simplify Debts (Greedy)

```
1. Build group-scoped balances (same as above but filtered to groupId)
2. Separate into:
   creditors = [(personId, amount)] sorted by amount desc
   debtors   = [(personId, amount)] sorted by amount desc (absolute)
3. While both lists non-empty:
   debtor pays min(debtorAmount, creditorAmount) to creditor
   add (debtor → creditor, amount) to payments
   reduce both by amount; remove zeroed entries
4. Return: { debtorId: [{ to: creditorId, amount: float }, ...] }
```

This produces the minimum number of transactions to clear all group debts.

---

## 12. Demo / Seed Data

Seeding is triggered by `AppData.seedForAccount(account)` when a user logs in for the first time (no existing state in the store).

### Demo Accounts

| Email | Display Name | Avatar | Color |
|-------|-------------|--------|-------|
| chenuri@gmail.com | Chenuri | 🙂 | #2563EB |
| ushani@gmail.com | Ushani | 🧑 | #10B981 |
| nimsara@gmail.com | Nimsara | 👩 | #8B5CF6 |
| janidu@gmail.com | Janidu | 🧔 | #EF4444 |

Password for all: **demo123**

### Seeded Groups

| Name | Emoji | Members |
|------|-------|---------|
| Beach House | 🏖️ | you, alex, maya, jordan |
| Apartment Crew | 🏠 | you, alex, jordan |
| Road Trip 2026 | 🚗 | you, maya, jordan |

### Seeded Expenses

- 10 shared expenses across the seeded groups and direct friend splits

---

## 13. Testing

All tests live in `test/`.

### Test Files

| File | What it tests |
|------|--------------|
| `test/backend_client_test.dart` | `BackendClient` throws `BackendClientException` when backend is unreachable |
| `test/settlement_test.dart` | Settlement calculation correctness (see below) |
| `test/widget_test.dart` | Default Flutter widget smoke test |

### Settlement Test Coverage (`test/settlement_test.dart`)

Uses `_FakeBackend` (in-memory stub) so no running server is required.

| Test | Assertion |
|------|-----------|
| JSON round-trip | Settlement serialises and deserialises without data loss |
| Missing settlements default | Empty list when `settlements` key absent from JSON |
| Partial settlement reduces balance | Balance decreases; progress bar advances |
| Full settlement clears group | All balances zero after full payment |
| `settleAllForGroup()` | Clears all debts in one call |
| Non-positive amount rejected | `recordSettlement` throws for amount ≤ 0 |
| `markSettled()` | Expense.settled becomes true |

### Running Tests

```bash
flutter test
```

---

## 14. Dev Setup & Scripts

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | ≥ 3.x (with Dart ^3.11.5) |
| Node.js + npm | For `npm run` script aliases (optional) |
| MongoDB | Optional; only needed for multi-device sync |

### Quick Start (Windows — Recommended)

```powershell
# Launches backend (new terminal) + frontend (Chrome)
powershell -ExecutionPolicy Bypass -File tool/dev.ps1
```

#### `dev.ps1` Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Target` | `chrome` | Flutter device target (`chrome` or `web-server`) |
| `-WebPort` | `8080` | Frontend port |
| `-Clean` | `false` | Run `flutter clean` before starting |

#### `dev.ps1` Steps

1. Checks `MONGO_URI` env var; starts local `mongod` if not set and MongoDB is installed.
2. Starts backend: `dart run bin/server.dart` in a new PowerShell window; polls `/health` until ready.
3. Starts frontend: `flutter run -d <Target>`.
4. Ctrl+C stops all processes.

### Manual Start (3 Terminals)

```bash
# Terminal 1 — Backend
cd backend
dart run bin/server.dart

# Terminal 2 — Frontend (Chrome)
flutter run -d chrome

# Terminal 3 — (Optional) Local MongoDB
mongod --dbpath .mongo-data --port 27017
```

### npm Script Aliases

```bash
npm run backend   # cd backend && dart run bin/server.dart
npm run dev       # runs dev.ps1 via powershell
npm run build     # flutter build web
npm run test      # flutter test
```

---

## 15. Environment Variables

### Frontend (`.env` at project root)

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_BASE_URL` | auto-detected | Override backend URL (useful for remote server or CI) |

Auto-detection logic in `BackendClient`:
- Android emulator → `http://10.0.2.2:8081`
- Web / other → `http://127.0.0.1:8081`

### Backend (`backend/.env` or shell environment)

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_PORT` | `8081` | Port the Shelf server listens on |
| `BACKEND_HOST` | `0.0.0.0` | Bind address |
| `MONGO_URI` | _(not set)_ | MongoDB connection string; enables remote sync when set |
| `MONGO_COLLECTION` | `app_states` | MongoDB collection name |

> `.env.example` in the repo root shows all variables for reference. Copy to `.env` to override.

---

## 16. Known Limitations & Future Work

| Area | Current State | Suggested Improvement |
|------|--------------|----------------------|
| **Authentication** | Hardcoded demo accounts only | Integrate a real auth provider (Supabase, Firebase Auth, or custom JWT) |
| **Real-time sync** | Pull-on-action only (no push) | Add WebSocket or SSE channel for live multi-user updates |
| **CORS** | Open (`*`) for all origins | Restrict to frontend origin in production |
| **Notifications** | Settings stub (no logic) | Push notifications via FCM when someone adds an expense |
| **Currency** | USD hard-coded | Multi-currency support with exchange rate API |
| **Split methods** | Equal, exact amount, percentage | Add shares-based and adjustment splits (Splitwise parity) |
| **Comments** | Note field only | Threaded comments on expenses |
| **Recurring expenses** | Not supported | Monthly/weekly recurring expense templates (rent, subscriptions) |
| **Receipt capture** | Not supported | Attach a receipt photo to an expense; OCR auto-fill |
| **Offline mode** | Displays last-known state; writes fail silently | Queue writes locally and sync when back online |
| **User management** | Fixed contacts per seed | Allow inviting real users by email or link |
| **Payment methods** | Settings stub | Deep link to Venmo / PayPal / bank transfer |
| **Deployment** | Local dev only | Containerise backend (Dockerfile); deploy to Cloud Run or Fly.io |
