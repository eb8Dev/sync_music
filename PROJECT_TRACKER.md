# Sync Music — Project Tracker

Living checklist so nothing gets lost. Status: ✅ done · 🚧 in progress · ⬜ todo · ⏸️ blocked/needs-you

**Positioning (agreed):** "The instant, no-account, mobile way to play YouTube music together — just send a link." Compete on zero friction + fun, never on catalog. Movie mode = YouTube only (real Netflix sync is impossible for a 3rd-party mobile app due to DRM).

**Repos:** Flutter app (`FlutterProjects/sync_music`) · Node server (`web/sync-music-server`, Render auto-deploys on push to `main`) · React landing (`web/sync-music`).

---

## Agreed roadmap (in order)
1. 🚧 **State management** — fix correctness + stop drift
2. ⬜ **UI fix** — design system, kill the "vibe-coded" feel
3. ⬜ **App persona / branding** — name, tone, visual identity, store presence
4. ⬜ **End-to-end testing** — 2–3 emulators, Android + iPhone
5. ⬜ **Analytics** — funnel/activation/retention/share instrumentation (prereq for any marketing)

---

## 1. State management 🚧
- ✅ Host identity bug fixed (creator = permanent host, resolved by persistent `userId`, never socket id). Server + client. **Deployed to Render.**
- ✅ Single source of truth for role (`party_state_provider` defers to `partyProvider.isHost`).
- ✅ Detailed store self-seeds from server `PARTY_STATE` + re-seeds on reconnect (no drift).
- ⬜ Decide if the two providers (`party_provider` + `party_state_provider`) need fuller unification, or if current split + single-sourcing is sufficient.
- ⬜ Resilience UX: "reconnecting…" + "host is away" banners (server already emits `HOST_PRESENCE`), graceful rejoin.
- ⬜ Audit remaining `widget.party["..."]` raw-map usage vs reading from providers.

## 2. UI fix ⬜
- ⬜ Design tokens (color/space/type scale) to replace ad-hoc hex (`0xFF151922`, `0xFF0B0E14`) scattered across files.
- ⬜ Consistent component library (buttons, cards, sheets, loaders).
- ⬜ Screen-by-screen polish pass (home, waiting, party, movie, settings, onboarding).

## 3. App persona / branding ⬜
- ⬜ Define persona/voice + visual identity aligned to positioning.
- ⬜ App name/icon/splash review, store listing copy + screenshots.

## 4. End-to-end testing ⬜
- ⬜ Host disconnect/reconnect on throttled network → stays host (verify the fix live).
- ⬜ 2–3 clients: create/join, queue, playback sync, chat, reactions, vote-skip (now ≥3), kick, theme, settings.
- ⬜ Android + iPhone, cross-platform party.
- ⬜ Movie mode parity.

## 5. Analytics ⬜ (do before marketing)
- ⬜ Growth loop: `invite_shared` → `join_link_opened` → `party_joined` (share tap is currently UNtracked).
- ⬜ Activation: `party_reached_2_people`, `first_song_added`, `playback_started`, `party_duration`.
- ⬜ Engagement: songs added, reactions, chat, session length.
- ⬜ Failure: `connect_failed`, `connect_timeout`.
- ⬜ Wire the already-defined-but-unused `song_added` / `trigger_campaign`.
- ⬜ Install attribution (note: Firebase Dynamic Links is shut down — need an alternative).

---

## ⏸️ Needs YOU (manual)
- ⏸️ **Keep-warm pinger**: set up UptimeRobot or cron-job.org hitting `https://sync-music-server.onrender.com/healthz` every ~10 min (only thing that stops Render free-tier cold starts). Or upgrade Render to paid always-on.

## ✅ Done (earlier this session)
- ✅ Removed stray `lib/index.js` + dead `socket_service.dart`; de-duped a `pubspec.yaml` asset.
- ✅ Cold-start fixes: `/healthz` endpoint, launch warm-up ping, `ConnectingServerOverlay`. (Confirmed cold start was 22.5s → 0.3s warm.)
- ✅ Vote-skip threshold 5 → 3.
- ✅ Server deployed + verified live via `/healthz`.

## Known deferred / notes
- `onReorder` deprecation at `playlist_detail_screen.dart:173` — left as-is (switching to `onReorderItem` would double-adjust the index since `reorderSong` already adjusts).
- Migrate YouTube **search** off `youtube_explode_dart` (scraping, ToS-gray, fragile) to official YouTube Data API. Playback via IFrame is fine.
