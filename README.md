# CarGPT

A voice AI assistant for Apple CarPlay, powered by Claude. See
[docs/PLAN.md](docs/PLAN.md) for Apple's rules, the architecture, and the roadmap.

> "CarGPT" is a working name. Rename it before App Store submission (reasons in the plan).

## Layout

```
backend/            TypeScript server that holds the Anthropic API key
  src/app.ts        Routes: Sign in with Apple exchange, streaming chat
  src/claude.ts     The Claude request (model, effort, caching, fallback)
  src/prompt.ts     System prompt for spoken answers
ios/
  project.yml       XcodeGen spec (generates CarGPT.xcodeproj)
  CarGPT/           The app: SwiftUI phone UI, CarPlay scene, voice loop
  CarGPTCore/       Swift package with platform-independent logic and its tests
docs/PLAN.md        The plan
```

## Backend

Needs Node 22+.

```sh
cd backend
cp .env.example .env    # then fill in ANTHROPIC_API_KEY and SESSION_SECRET
npm install
npm run dev             # http://localhost:8787
npm test
```

Endpoints:

- `POST /v1/auth/apple` takes `{ "identityToken": "..." }` from Sign in with Apple
  and returns `{ "sessionToken": "...", "expiresIn": 2592000 }`.
- `POST /v1/chat` takes `Authorization: Bearer <sessionToken>` and
  `{ "messages": [{ "role": "user", "content": "..." }] }`, and streams server-sent
  events: `text` (`{ "type": "text", "text": "..." }`), then `done`
  (`{ "type": "done", "stopReason": "end_turn" }`) or `error`.
- `GET /healthz`

## iOS app

Needs a Mac with Xcode 26.4 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and a paid Apple Developer account (for Sign in with Apple and the CarPlay entitlement).

1. In `ios/project.yml`, set `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`.
   Put the same bundle ID in `backend/.env` as `APPLE_BUNDLE_ID`.
2. Generate and open the project:
   ```sh
   cd ios
   xcodegen
   open CarGPT.xcodeproj
   ```
3. Run the backend locally, then run the app in the iOS Simulator. The Debug build
   points at `http://localhost:8787`.
4. To see the CarPlay screen, use the Simulator's CarPlay window (I/O > External
   Displays > CarPlay) or CarPlay Simulator in Xcode's Device Hub with an iPhone
   connected over USB.

On a real iPhone, `localhost` is the phone itself. Point the Debug `BACKEND_URL` at
a deployed backend or a tunnel to your machine instead. Device builds also can't be
signed with the CarPlay entitlement until Apple approves it; until then, remove it
from `CarGPT/CarGPT.entitlements` to test the phone app on a device.

Core logic tests run anywhere Swift does, including Linux:

```sh
cd ios/CarGPTCore
swift test
```

## CI

`.github/workflows/ci.yml` runs on every push: backend typecheck and tests on
Linux, then on a macOS runner the core package tests, `xcodegen`, and a simulator
build of the app (unsigned, so it doesn't need the CarPlay entitlement).

## Status

The backend is tested (unit tests plus a local run), and the app compiles against
the iOS SDK in CI. Nothing has run on a simulator, iPhone, or car yet. The CarPlay
entitlement request is drafted in [docs/CARPLAY_ENTITLEMENT.md](docs/CARPLAY_ENTITLEMENT.md).
