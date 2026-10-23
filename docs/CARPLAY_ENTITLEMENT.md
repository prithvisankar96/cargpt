# CarPlay entitlement request: draft answers

Submit at https://developer.apple.com/contact/carplay/ (needs your Apple Developer
login). The form's exact fields aren't visible without signing in, so these answers
cover what Apple's CarPlay Developer Guide says the request needs: information about
the app and the entitlement category. Adjust to fit the fields you see.

Fill in the bracketed parts first. Settle the app name before submitting (the plan
explains why "CarGPT" is risky); the bundle ID must match `PRODUCT_BUNDLE_IDENTIFIER`
in `ios/project.yml`.

## Basics

- **App name:** [App name]
- **Bundle ID:** [com.yourname.app]
- **Team ID:** [Team ID]
- **Entitlement category:** Voice-based conversational app
  (`com.apple.developer.carplay-voice-based-conversation`)
- **App Store status:** In development, not yet released
- **Minimum iOS version:** 26.4

## App description

[App name] is a hands-free voice assistant for drivers, powered by Anthropic's
Claude. The driver asks a question out loud and hears a short spoken answer through
the car's speakers. It's built for things people want to know on the road: general
questions, explanations, planning, and conversation, without picking up the phone.

## How it works in CarPlay

- Opening the app on the CarPlay screen starts listening right away, so voice is the
  primary mode from launch.
- While a conversation runs, the app shows only the voice control template, with
  Listening, Thinking, and Speaking states. The only controls are Stop and, while it
  speaks, Interrupt.
- Answers are spoken, never shown. No text or images appear in response to
  questions. Transcripts are available only in the iPhone app.
- A conversation is hands-free: after each answer the app listens again, and it ends
  when the driver stops talking or taps Stop.
- The root screen has two buttons, Talk and New chat, for starting a conversation.

## How it follows the category guidelines

1. **Voice first on launch.** The app begins listening as soon as it opens in
   CarPlay and responds to questions and requests by voice.
2. **Audio session only while in use.** The audio session is activated when a
   conversation starts and deactivated as soon as it ends, with
   `notifyOthersOnDeactivation`, so the radio or other audio resumes. Phone calls and
   Siri interrupt and end the conversation.
3. **Optimized for driving.** Replies are written for speech: short, no lists or
   links. Speech recognition runs on the iPhone. Recording happens only while the
   voice control template is showing.

## Safety

- The assistant can't control the vehicle or the iPhone, and says so if asked.
- Its instructions tell it never to encourage the driver to look at or touch a
  screen, and to suggest continuing complex topics once parked.
- Sign-in and permission prompts happen only on the iPhone, never in the car.
- The app works with the iPhone locked.

## Markets

[Countries where you plan to launch, e.g. United States]
