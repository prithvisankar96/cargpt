# CarGPT plan

A voice AI assistant for CarPlay, powered by Claude. The driver opens the app on
the car's screen, talks, and hears the answer through the car's speakers.

## What Apple allows

Since iOS 26.4, CarPlay has a **voice-based conversational app** category. From
Apple's [CarPlay Developer Guide](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf)
(October 2026 edition):

- **Entitlement:** `com.apple.developer.carplay-voice-based-conversation`, iOS 26.4
  or later. You request it through the
  [CarPlay entitlement form](https://developer.apple.com/contact/carplay/), and Apple
  reviews each app. An app can only be in one CarPlay category.
- **Voice only in the car:** the app must open in voice mode, and shouldn't show
  text or images in response to questions. Typed chat and transcripts stay on the
  iPhone.
- **Voice control screen:** it must be showing while voice is active. Each state
  (listening, thinking, speaking) has an image and title, plus up to 2 action
  buttons (iOS 26.4). Screens stack at most 3 deep.
- **Microphone:** recording in CarPlay is only allowed while the voice control
  screen is up.
- **Audio:** turn the audio session on only while voice is in use. Turning it on
  stops the car's radio; turning it off lets the radio resume.
- **No wake word:** the steering-wheel button opens Siri, not us. The driver opens
  the app.
- **Locked phone:** CarPlay usually runs with the iPhone locked. Keychain items and
  files must be readable after first unlock.

ChatGPT shipped under this category in March 2026, so the path is proven.

## Architecture

```
Driver speaks → on-device speech-to-text → backend → Claude (streaming)
            → split into sentences → text-to-speech → car speakers
```

| Piece | Choice | Why |
|---|---|---|
| App | Native Swift, iOS 26.4+, XcodeGen project | CarPlay's framework is native; a cross-platform layer would add nothing |
| Speech-to-text | `SFSpeechRecognizer`, on-device | Fast, free, works without signal. Claude's API takes text, not audio |
| End of speech | 1.2 s pause, 8 s no-speech timeout | No button press needed to send |
| Backend | TypeScript, Hono, official Anthropic SDK | Keeps the API key off the phone; Hono also runs on Cloudflare Workers |
| Login | Sign in with Apple, exchanged for a 30-day backend session token | No passwords; one tap |
| Model | Claude Opus 5.5 (`claude-opus-5-5`), effort `low`, streaming | Low effort keeps time to the first word short |
| Refusals | Server-side fallback (`fallbacks: "default"`) | A safety-classifier false positive retries on another model instead of failing |
| Caching | Automatic prompt caching on the conversation | Later turns start faster |
| Text-to-speech | `AVSpeechSynthesizer`, best installed voice | Free and offline; revisit after testing (ElevenLabs is the upgrade path) |
| History | Kept on the phone, sent with each request (last 41 messages) | Backend stays stateless |

Conversation loop (`ios/CarGPT/Voice/VoiceSession.swift`): listen, send, speak
each sentence as it arrives, listen again. It ends when the driver says nothing,
taps Stop, CarPlay disconnects, or a call or Siri interrupts the audio.

## Phases

### 0. Apple setup (you)
- [ ] Paid Apple Developer account and an App ID with Sign in with Apple
- [ ] Request the voice-based conversational CarPlay entitlement (approval takes time; start now).
      Draft answers: [CARPLAY_ENTITLEMENT.md](CARPLAY_ENTITLEMENT.md)
- [ ] Pick the final app name (see open decisions)

### 1. Voice loop on the phone
- [x] Backend: Sign in with Apple exchange, session tokens, rate limiting, streaming chat endpoint, tests
- [x] iOS: speech-to-text, streaming client, sentence-by-sentence speech, phone UI
- [x] Compile against the iOS SDK (CI on a GitHub macOS runner)
- [ ] Run on the simulator and an iPhone
- [ ] Measure the time from the driver going quiet to the first spoken word (target: under 1.5 s)
- [ ] Tune the system prompt for spoken answers

### 2. CarPlay screen
- [x] CarPlay scene with a root grid (Talk, New chat) and the voice control screen
- [x] Listening / thinking / speaking states with Stop and Interrupt buttons
- [ ] Test in the CarPlay simulator
- [ ] Replace SF Symbol placeholders with 150 pt state artwork

### 3. Real conditions
- [ ] CarPlay Simulator in Device Hub (iPhone over USB), then a real car, wired and wireless
- [ ] iPhone locked the whole time
- [ ] Calls, Siri, and navigation prompts cutting in
- [ ] Weak or no cell signal

### 4. Polish and ship
- [ ] Hands-free interrupt (barge-in while speaking), not just the button
- [ ] Persist and sync conversation history to the phone app
- [ ] Decide on TTS (Apple vs ElevenLabs) from real-car testing
- [ ] Deploy the backend (Fly.io, Render, or Cloudflare Workers), with a shared rate-limit store
- [ ] App Store submission

## Open decisions

- **Name.** "CarGPT" uses OpenAI's "GPT", which their brand guidelines discourage,
  and with Claude as the model it could mislead people and draw App Store review
  questions. Rename before submission.
- **What sets it apart.** ChatGPT and Grok are already in CarPlay. Options:
  driving-focused help (trip planning, explaining dashboard warning lights), memory
  across drives, a better voice.
- **Business model.** Free with limits or a subscription. This decides how much
  account and billing work phase 4 needs.
- **Web search.** Live information (opening hours, weather, news) needs Claude's
  web search tool. It's a contained backend change; worth adding after phase 1
  latency is measured, since searching adds delay.

## Unknowns to check

- Whether "Hey Siri, ask CarGPT…" (App Intents) can start a conversation in
  CarPlay. Left out of v1.
- Whether `SpeechAnalyzer` (iOS 26) beats `SFSpeechRecognizer` on latency and
  accuracy in a noisy car. Worth an A/B test in phase 3.
- How the voice control screen behaves when CarPlay switches to Maps and back.
