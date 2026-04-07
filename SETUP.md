# Spicking Setup

## 1. Cloudflare Worker
- Create a Worker using [CloudflareWorker.example.js](/Users/rundo/Desktop/Dev/Spicking/Spicking/CloudflareWorker.example.js).
- Add these environment variables in Cloudflare:
  - `OPENAI_API_KEY`
  - `APP_SHARED_SECRET`
- Publish the Worker.
- Your Worker route should end with `/realtime/session`.

## 2. iOS app config
- Open [SpickingConfig.plist](/Users/rundo/Desktop/Dev/Spicking/Spicking/Spicking/SpickingConfig.plist).
- Replace:
  - `WORKER_URL`
  - `APP_SHARED_SECRET`
- Keep `MODEL` as `gpt-realtime` unless you intentionally change it.
- Keep `VOICE` as `marin` unless you want a different default voice.

## 3. Run
- Build and run the `Spicking` scheme in Xcode.
- Start a conversation from the Home tab.
- When you end a session, the app asks the same Realtime session for JSON review suggestions and saves selected phrases locally with SwiftData.
