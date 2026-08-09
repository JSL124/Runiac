# Runiac

**A beginner-focused running app.** Runiac turns "I want to start running" into a concrete weekly
plan, tracks each run with GPS, and keeps the runner going with levels, streaks, a social feed,
friends, challenges and a regional leaderboard.

Final Year Project — CSIT321, group **FYP-26-S2-38**.

This repository is the complete source code for the system: the Flutter mobile app, the Firebase
backend (Cloud Functions and security rules), and the public website with its administration
console.

---

## Contents

1. [System overview](#1-system-overview)
2. [Repository structure](#2-repository-structure)
3. [Prerequisites](#3-prerequisites)
4. [Downloading and installing the app](#4-downloading-and-installing-the-app)
5. [Running from source](#5-running-from-source)
6. [Configuration reference](#6-configuration-reference)
7. [Running the tests](#7-running-the-tests)
8. [User manual](#8-user-manual)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. System overview

Runiac has three components sharing one Firebase project.

| Component | Technology | Role |
| --- | --- | --- |
| Mobile app | Flutter 3.44 / Dart 3.12 | What the runner uses. Plans, GPS run tracking, feed, friends, challenges, leaderboard. |
| Backend | Firebase Cloud Functions (Node 22, TypeScript) + Firestore + Cloud Storage | Owns everything that must not be client-controlled: XP, levels, streaks, leaderboard scores, moderation, notifications. |
| Website | Next.js 16 (App Router) / React 19 | Public marketing site, APK download, account sign-up — and the Platform Administrator console. |

There are three kinds of user:

- **Basic** — every registered runner. Full access to running, plans, feed, friends, challenges
  and the leaderboard.
- **Premium** — a subscription status, not a role. Adds coaching, post-run analysis and
  presentation features. It never changes how XP, level, rank, streak or leaderboard score are
  calculated; those are owned by the server and identical for both tiers.
- **Platform Administrator** — a separate governance role that works in the web console, not the
  mobile app.

**A design rule worth knowing before reading the code:** the client never writes progression state.
`firestore.rules` (1,258 lines) enumerates the backend-owned fields — `xp`, `totalXp`, level, rank,
streak, leaderboard score — and rejects any client write to them. All of it moves through callable
Cloud Functions.

### Size

| Area | Files | Lines |
| --- | ---: | ---: |
| `mobile/lib` (Flutter app) | 629 | 116,902 |
| `mobile/test` | 284 | 99,949 |
| `functions/src` (Cloud Functions) | 184 | 28,326 |
| `functions/test` | 91 | 26,713 |
| `website/src` | 165 | 38,498 |
| Native (Swift 11, Kotlin 9) | 20 | ~2,600 |
| Security rules | 2 | 1,388 |

---

## 2. Repository structure

```
Runiac/
├── mobile/                 Flutter application (Dart package `runiac_app`)
│   ├── lib/
│   │   ├── main.dart           entry point
│   │   ├── app.dart            composition root
│   │   ├── core/               theme, widgets, Firebase bootstrap, formatting, haptics, share
│   │   └── features/           19 features, each split data/ · domain/ · presentation/
│   │                           auth, challenge, feed, friends, home, leaderboard, maps,
│   │                           moderation, notifications, onboarding, paywall, plan, profile,
│   │                           run, settings, shell, splash, tutorial, you
│   ├── test/                   unit and widget tests
│   ├── integration_test/       device tests against the Firebase emulator
│   ├── android/  ios/          native hosts (incl. an iOS Live Activity extension)
│   ├── assets/                 images, Lottie animations, Singapore planning-area GeoJSON
│   └── dart_define.example.json
│
├── functions/              Firebase Cloud Functions (37 exported entry points)
│   ├── src/
│   │   ├── index.ts            function exports
│   │   ├── run/                run completion, summaries
│   │   ├── progression/        XP, levels, streaks — the server-owned formulas
│   │   ├── leaderboard/        period aggregation and ranking
│   │   ├── feed/  friends/  challenge/  notifications/  moderation/
│   │   ├── plan/  paywall config/  profile/  account/  newsletter/  feedback/
│   │   ├── agent/              LLM coaching: home guide, activity feedback, workout briefing
│   │   └── security/  errors/
│   └── test/                   emulator-driven test suites
│
├── website/                Next.js site and admin console
│   ├── src/app/                App Router — public pages, /login, /signup, /admin/*, /api/*
│   ├── src/components/         UI, including components/admin/
│   ├── src/lib/                server actions, Firebase Admin SDK wiring, admin logic
│   ├── scripts/                seed-emulator, set-admin-role, backfill helpers
│   ├── public/                 images and fonts
│   └── .env.local.example
│
├── tests/
│   ├── firebase-rules/         Firestore and Storage rules tests (emulator)
│   └── cross-system/           contract-drift checks between app, backend and website
│
├── firebase.json               emulator ports, functions runtime, rules wiring
├── firestore.rules             1,258 lines of access control
├── firestore.indexes.json      22 composite indexes
├── storage.rules
└── .firebaserc.example
```

---

## 3. Prerequisites

| Tool | Version | Check |
| --- | --- | --- |
| Flutter SDK | 3.44.0 stable (Dart 3.12) | `flutter --version` |
| Node.js | 22.x | `node -v` |
| JDK | 17 | `java -version` |
| Android SDK | compile SDK 36 | Android Studio → SDK Manager |
| Xcode | 16 or later (iOS builds only, macOS only) | `xcodebuild -version` |
| Firebase CLI | 14.x | `firebase --version` |

Run `flutter doctor` once and resolve anything it flags before building.

Only Flutter and Node are needed to run the app and the website. The Android SDK, Xcode and the
Firebase CLI are needed for device builds and for the local emulator suite respectively.

---

## 4. Downloading and installing the app

Runiac is distributed for **Android** as a direct APK from the Runiac website. iOS distribution is
not yet available to the public — build from source with Xcode instead (section 5).

1. Open the Runiac download page:
   **https://fyp-website-v2.vercel.app/download**
2. Under **Android**, press **Download APK**. The page lists the requirements —
   **Android 8.0 (API 26) or newer** — and notes that you may need to allow installs from your
   browser. The file is about 155 MB.
3. Open the downloaded file. Because the APK is installed directly rather than from an app store,
   Android asks for permission to install from an unknown source the first time. This is expected —
   allow it, then confirm the install.
4. Runiac appears in your app list. Continue at [section 8](#8-user-manual).

---

## 5. Running from source

```bash
git clone https://github.com/JSL124/Runiac.git
cd Runiac
```

### 5.1 Mobile app — offline mode (no configuration at all)

**This is the quickest way to see the app running, and needs no credentials of any kind.**

```bash
cd mobile
flutter pub get
flutter run                      # pick a connected device or simulator
```

With no `--dart-define` flags, the app starts on its built-in static repositories and a
non-production auth path. Every screen is reachable and the whole UI is exercisable; the data is
local and nothing is written to a server. The Android build detects that no `google-services.json`
is present and skips the Google Services plugin automatically, so the build succeeds with an empty
configuration.

To produce an installable APK:

```bash
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

### 5.2 Backend — local Firebase emulator

Start the emulator suite from the repository root:

```bash
cp .firebaserc.example .firebaserc     # then set your own project id, or keep the placeholder
cd functions && npm ci && npm run build && cd ..
firebase emulators:start
```

This brings up Auth (`127.0.0.1:9099`), Firestore (`:8080`), Functions (`:5001`) and Storage
(`:9199`) with the rules and indexes in this repository.

### 5.3 Mobile app — against the emulator

With the emulators running:

```bash
cd mobile
flutter run \
  --dart-define=RUNIAC_FIREBASE_EMULATOR=true \
  --dart-define=RUNIAC_FIREBASE_EMULATOR_HOST=127.0.0.1
```

Sign-up, login, password reset, session persistence, sign-out and run completion now go through
the local emulator. Use `10.0.2.2` instead of `127.0.0.1` on an Android emulator, and the Mac's LAN
IP on a physical device (the emulators must then bind to `0.0.0.0`).

### 5.4 Mobile app — against a real Firebase project

Create a Firebase project, register an Android and/or iOS app, then:

```bash
cd mobile
cp dart_define.example.json dart_define.local.json   # fill in your values (gitignored)
flutter run --dart-define-from-file=dart_define.local.json
```

The values needed are listed in [section 6](#6-configuration-reference). Deploy the backend the
project expects with `firebase deploy --only functions,firestore,storage` from the repository root.

### 5.5 Website and admin console

```bash
cd website
npm ci
cp .env.local.example .env.local
npm run dev                      # http://localhost:3000
```

`.env.local.example` defaults to **emulator mode**, so no service account and no API key are
required — start the emulators (5.2) and the console talks to them. Seed some demo data and give
yourself an administrator account:

```bash
node scripts/seed-emulator.mjs
# sign in at /login with the address in FIREBASE_ADMIN_EMAILS, then:
node scripts/set-admin-role.mjs <email>
```

The console is at **http://localhost:3000/admin**. An account whose `userRole` is not
`platformAdmin` is redirected back to the public site.

For a production build: `npm run build && npm start`.

---

## 6. Configuration reference

**No credentials are committed to this repository.** Every configuration file is shipped as a
redacted `.example`. Copy it, fill in your own values, and the copy stays gitignored.

### Mobile — compile-time values (`--dart-define`)

All optional. Omit them all for offline mode (5.1).

| Key | Purpose |
| --- | --- |
| `RUNIAC_FIREBASE_EMULATOR` | `true` to route Firebase through the local emulator suite |
| `RUNIAC_FIREBASE_EMULATOR_HOST` | Emulator host — `127.0.0.1`, or `10.0.2.2` on an Android emulator |
| `RUNIAC_FIREBASE_PRODUCTION` | `true` to enable real Firebase |
| `RUNIAC_FIREBASE_API_KEY` | Firebase Web API key (Project settings → General) |
| `RUNIAC_FIREBASE_APP_ID` | Platform app id for the registered Android/iOS app |
| `RUNIAC_FIREBASE_MESSAGING_SENDER_ID` | Cloud Messaging sender id |
| `RUNIAC_FIREBASE_PROJECT_ID` | Firebase project id |
| `RUNIAC_FIREBASE_STORAGE_BUCKET` | `<project-id>.firebasestorage.app` |
| `RUNIAC_APPCHECK_DEBUG_TOKEN` | A **registered** App Check debug token — required for the coaching callables on a debug build |
| `MAPBOX_PUBLIC_ACCESS_TOKEN` | Mapbox public token; without it the run screen shows a placeholder map |

Native Firebase config files (`google-services.json`, `GoogleService-Info.plist`,
`firebase_options.dart`) are deliberately absent: the app is configured entirely at launch time so
no keys ever live in the source tree.

### Website (`website/.env.local`)

| Key | Purpose |
| --- | --- |
| `FIREBASE_PROJECT_ID` | Firebase project id |
| `FIRESTORE_EMULATOR_HOST` · `FIREBASE_AUTH_EMULATOR_HOST` | Set **both** for emulator mode — no credentials needed |
| `FIREBASE_SERVICE_ACCOUNT_KEY` *or* `GOOGLE_APPLICATION_CREDENTIALS` | Live mode: inline service-account JSON, or a path to it |
| `NEXT_PUBLIC_FIREBASE_API_KEY` | Live mode: required for email/password sign-in |
| `FIREBASE_STORAGE_BUCKET` | Optional; defaults to `<project-id>.firebasestorage.app` |
| `FIREBASE_ADMIN_EMAILS` | Comma-separated bootstrap administrator addresses |

### Cloud Functions

| Secret | Purpose |
| --- | --- |
| `OPENAI_API_KEY` | Backs the LLM coaching features. Set with `firebase functions:secrets:set OPENAI_API_KEY`. The tests stub the provider, so it is not needed to run them. |

---

## 7. Running the tests

```bash
# Flutter — 2,683 unit and widget tests
cd mobile && flutter analyze && flutter test

# Cloud Functions — emulator-driven suites (Java 17 and the Firebase CLI required)
cd functions && npm ci && npm test

# Website — Vitest
cd website && npm ci && npm test

# Firestore and Storage security rules
cd tests/firebase-rules && npm ci && npm test

# Cross-system contract drift (app ↔ backend ↔ website)
node tests/cross-system/config-contract-drift.mjs
node tests/cross-system/avatar-path-contract-drift.mjs
node tests/cross-system/paywall-config-drift.mjs
node tests/cross-system/account-deletion-index-drift.mjs
```

The Cloud Functions tests run the coaching agents against a deterministic fake provider
(`RUNIAC_HOME_GUIDE_FAKE_PROVIDER=deterministic`), so no OpenAI key is needed.

---

## 8. User manual

### 8.1 Getting started

1. **Install** — download and install the APK (section 4), or run from source (section 5.1).
2. **Create an account** — press **Sign up**, enter an email address and password. You can also
   sign up on the website.
3. **First-run setup** — Runiac asks a 16-step questionnaire: your goal, how consistently you run
   now, how far you can comfortably run, how many days a week you can train, which days and what
   time of day you prefer, session length, where you run, what support motivates you, and two
   health and safety questions. Every answer can be changed later.
4. **Your plan** — the last step previews the generated beginner plan. Press **Continue with this
   plan**, or **Edit answers** to go back.
5. **The tour** — a twelve-step tour introduces the app the first time you reach Home. Press
   **Skip tour** to leave it; replay it any time from **Menu → App tour**.

### 8.2 Getting around

Five tabs along the bottom, plus a **Menu** on the Home screen.

| Tab | What it is |
| --- | --- |
| **Home** | An illustrated stage map of your week — each stepping stone is one day, your running buddy stands on today and gives a short message about today's session. |
| **Feed** | Posts from runners you follow. Like, comment, and share your own runs. |
| **Run** | Where you start a run. |
| **Leaderboard** | Your rank, by region and by league tier. |
| **You** | Your progress: level, XP, streak, activity history and plan. |

**Menu** (top right of Home) opens Profile, Notifications, Friends, Challenge, Settings and the app
tour.

### 8.3 Going for a run

1. Press the **Run** tab. The map centres on your location; the pill at the top shows GPS status,
   and the sheet below shows today's planned session and a **Start run** button.
2. *(Optional, once)* Press the **gear** icon to configure spoken updates — language, distance
   interval, time interval, and what each announcement includes. **Preview voices** plays a sample.
3. Press **Start run**. The first time, the phone asks for **location** access — this must be
   allowed, as Runiac cannot track a run without it. It then asks for **Motion & Fitness** access,
   used to detect stops and step rate.
4. While running, the map follows you and the sheet shows distance, elapsed time and current pace.
   **Pause** stops the timer.
5. To finish, pause and then **press and hold** *Hold to end run* for about a second and a half.
   The hold is deliberate so a run cannot be ended by accident.
6. Runiac offers a guided cool-down — a slow walk followed by stretches — before the summary. You
   can skip straight to the summary.
7. The summary shows distance, pace, time, splits, a pace graph, and the XP you earned.

### 8.4 Everything else

- **Progress and plan** (You tab) — level, XP toward the next level, current streak, weekly
  distance, full activity history, and the remaining sessions in your plan.
- **Feed** — share a run, then like and comment on other runners' posts.
- **Leaderboard** — ranked by score within your region and league tier. Scores are calculated by
  the server; there is no way for a client to influence them.
- **Friends** — search for runners, send and accept requests, and see friends' activity.
- **Challenges** — invite friends to a distance challenge, track it live, and see the result and
  any badge you earned. Invitations arrive in **Notifications**.
- **Profile and settings** — display name, avatar, region, units, notification preferences,
  privacy, and legal documents.
- **Deleting your account** — Settings → Delete account. This removes your data; it cannot be
  undone.

### 8.5 What Premium adds

Premium keeps everything above and adds coaching, analysis and presentation. A **PREMIUM** chip
appears beside your name. **XP, level, rank, streak and leaderboard score are identical for both
tiers** — Premium confers no competitive advantage.

- **Post-run analysis** — Coaching Summary and Next Focus cards, plus an Advanced Analysis screen
  with fastest/slowest pace, pace stability and pace over distance.
- **AI activity feedback** — press the sparkle icon on a run summary for a four-step review of the
  run, ending in a next focus.
- **AI workout briefing** — press the sparkle icon on a planned session to have it explained
  before you run it.
- **Sharing** — richer share cards.
- **Challenges and characters** — additional running buddies and challenge options.
- **Plans** — more plan styles and adjustments.

Basic users see these surfaces in a locked state rather than hidden, so it is always clear what
Premium offers.

### 8.6 The administration console

Platform Administrators work on the website, not in the app. Sign in at `/login` with an account
whose `userRole` is `platformAdmin`; any other account is returned to the public site.

| Page | Purpose |
| --- | --- |
| **Overview** | Unresolved reports, pending exception cases, users by tier, runs recorded, app errors, failed backend jobs, active-user trend, system health. |
| **Exception Queue** | Reported posts, users, routes and plans, plus suspicious XP flagged by anomaly detection. Filter by type, severity and status; resolve or dismiss. |
| **Users & Roles** | Search the directory; change role, suspend an account, set subscription, issue a moderation action, clear an avatar. Every action requires a reason and is audited. |
| **XP & Gamification Rules** | Tune the progression configuration the server applies. |
| **Leaderboard Oversight** | Inspect and correct leaderboard periods. |
| **App Paywall** | Configure what Premium gates, without redeploying the app. |
| **Website Content** · **Project Documents** | Manage public content and the document library. |
| **Feedback & Complaints** · **App Errors** | Triage what users and the app report. |
| **Newsletter** | Manage email subscribers. |
| **Automation & Policy Settings** | Scheduled jobs and policy toggles. |
| **Governance & Audit Log** | Every administrative action, with its reason and actor. |

---

## 9. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| The run map shows a plain placeholder instead of a real map | No `MAPBOX_PUBLIC_ACCESS_TOKEN` was supplied. This is expected and does not affect run tracking. |
| The app cannot reach the emulator from an Android emulator | Use `--dart-define=RUNIAC_FIREBASE_EMULATOR_HOST=10.0.2.2`. From a physical device, use the host machine's LAN IP and bind the emulators to `0.0.0.0`. |
| Coaching features fail on a debug build against production | The App Check debug token must be **registered** in the Firebase console, and the same token reused on every launch. Pin one UUID in `dart_define.local.json`. |
| Gradle fails with a Java version error | Use JDK 17. `flutter doctor --android-licenses` may also need to be accepted once. |
| `firebase emulators:start` fails to launch Firestore | The emulator needs Java. Install JDK 17 and make sure `java` is on `PATH`. |
| Website admin pages return you to the public site | Your account's `userRole` is not `platformAdmin`. Add your address to `FIREBASE_ADMIN_EMAILS`, sign in, then run `node scripts/set-admin-role.mjs <email>`. |
| `npm test` in `functions/` hangs or fails to start | The suites drive the Firebase emulator; make sure port 8080, 9099, 5001 and 9199 are free. |
