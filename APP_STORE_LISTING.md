# Big Talk — App Store listing

Everything App Store Connect asks for, written out and ready to paste, plus the
screenshot plan. Copy here is the source of truth: the paywall, the in-app FAQ,
and this file all describe the same purchase, because a scope that reads three
different ways is how refund requests start.

Nothing in this file was invented about the app. Every claim maps to shipped
behaviour, and the "Do not claim" list at the end records the ones that were
tempting and are not true yet.

This is the default page. The four audience-specific pages — interview,
presentation, pitch, and creator — are in `APP_STORE_PRODUCT_PAGES.md`, which
depends on the keyword field and screenshot set defined here.

---

## 1. Text fields

Character limits are Apple's. Counts are for the copy as written.

| Field | Limit | Copy | Count |
|-------|-------|------|-------|
| App Name | 30 | `Big Talk: Speech Coach` | 22 |
| Subtitle | 30 | `Practice speaking out loud` | 26 |

### Keywords (100 characters, comma-separated, no spaces)

```
speech,public speaking,filler,interview,presentation,toastmaster,pronunciation,voice,articulation
```

97 characters. Words already in the app name and subtitle are deliberately
absent — Apple indexes those separately, and repeating them wastes the field.

`interview` replaced `stutter`, for two reasons. Custom product pages can only
be assigned keywords that already exist in this field (see
`APP_STORE_PRODUCT_PAGES.md`), and interview prep is both one of the four
audience pages and one of the app's five onboarding goals — leaving the term
out made that page unreachable by search. `stutter` also pulled against
section 6: it is a high-volume term whose searchers are looking for a therapy
tool, which is precisely the claim this app must not make.

### Promotional text (170 characters, editable without a new build)

```
Record a minute. Get a real score on pace, fillers, pauses, and clarity — worked out on your iPhone, not on a server. Everything free for 14 days.
```

146 characters.

### Description (4000 characters)

```
Big Talk is a speaking gym for your iPhone. Record yourself for a minute, and
get a breakdown of how you actually sounded — pace, filler words, pauses,
clarity, delivery, vocabulary, and structure — with a plain-language reason
behind every number.

All of it runs on your device. Your recordings, your transcripts, and your
scores never leave your iPhone. There is no account to make and nothing to sign
in to.

WHAT YOU GET AFTER EVERY SESSION

• An overall score, plus the sub-scores behind it, so you can see which part of
  your speaking is holding the rest back
• A full transcript with every filler word marked in place
• Pace charted second by second, so you can see where you sped up
• Pause quality — the difference between a deliberate beat and a stall
• One clear next step, aimed at whatever scored lowest

PRACTICE THAT TARGETS THE WEAK SPOT

• Drills — filler elimination, pace control, pause practice, and impromptu
  sprints, each 15 to 60 seconds
• Warm-ups — breathing, tongue twisters, vocal range, and articulation
• Read-aloud passages with word-level pronunciation scoring and a built-in
  dictionary
• A live filler counter that ticks up while you are still talking, so you hear
  the habit as it happens

BRING YOUR OWN MATERIAL

Write or paste your own scripts — a best-man speech, a stand-up set, a
stakeholder update, an interview answer — and Big Talk scores how closely you
delivered what you wrote, not how well you matched a generic prompt. Send a
script straight into a warm-up or a drill.

WATCH IT MOVE

• Then-vs-Now: your first session next to your latest, side by side
• Charts for every metric over time
• Streaks, milestones, and a practice heatmap
• Home Screen and Lock Screen widgets

A COURSE, NOT JUST A TOOL

An eight-week curriculum takes you from your first recorded minute to
structured, unhurried delivery, and advances on what your sessions actually
show rather than on a button you tapped.

PRIVACY, SPECIFICALLY

Transcription and scoring happen on your iPhone using on-device speech models.
Recordings stay in the app's own storage. There is no account, no ad network,
and no analytics service — Big Talk keeps a coarse usage log on the device
itself, which you can read and delete in Settings. Progress cards you choose to
share carry scores and dates only, never a transcript, a prompt, or your audio.

FREE AND LIFETIME

Everything except iCloud sync is free for your first 14 days, starting at your
first score — unlimited scored practice, the eight-week curriculum, and journal
export included. After that you keep three full analyses every 30 days, plus
every drill, warm-up, read-aloud passage, your own scripts, and the progress
cards. Nothing charges by itself: there is no subscription and no card
involved. Big Talk Lifetime is a single payment that removes the analysis limit
and keeps the full curriculum, journal PDF export, and iCloud sync. It covers
everything in the app today and everything added later, at no extra charge:
no subscription, no upgrade fee, no second purchase.

Big Talk requires iOS 26 or later.
```

### What's New — version 1.0

```
First release.

Record a minute, get a breakdown of your pace, filler words, pauses, and
clarity, and a next step aimed at whatever scored lowest. Drills, warm-ups,
read-aloud passages, your own scripts, an eight-week curriculum, and progress
you can actually see.

Everything runs on your iPhone. No account, nothing uploaded.
```

---

## 2. In-app purchase listing

One non-consumable, product id `com.vansh.SpeakUpMore.lifetime`. Must match
`LifetimeProduct.identifier` and `Products.storekit` exactly.

| Field | Limit | Copy |
|-------|-------|------|
| Display Name | 30 | `Big Talk Lifetime` |
| Description | 45 | `One payment. Unlimited scoring, all courses.` |

Review screenshot: the paywall, reached by finishing one analysis and opening a
gated surface. The reviewer needs to see the price, the Restore control, and
the Terms/Privacy footer in one frame.

The App Store Connect price is the only price of record. `FoundingOffer` in the
app changes framing copy only, and ships with its deadline unset so no urgency
claim is made that the store cannot back.

---

## 3. Privacy nutrition labels

With the shipped `LocalAnalyticsSink`, the honest answers are:

- **Data used to track you:** none.
- **Data linked to you:** none.
- **Data not linked to you:** none.

"Collect" in Apple's definition means transmitted off the device. Big Talk
transmits nothing: recordings, transcripts, scores, and the usage log all stay
in the app container, and the only network calls are model downloads from
Hugging Face and the user's own iCloud sync when they turn it on.

Re-answer this section the day a hosted analytics sink is adopted. That is an
`AnalyticsService.use(sink:)` swap, and the labels stop being true the moment
it lands.

**Privacy manifests:** `SpeakUp/PrivacyInfo.xcprivacy` and
`SpeakUpWidget/PrivacyInfo.xcprivacy` declare the required-reason APIs
(UserDefaults, both app-private and app-group; file metadata). Missing or
incomplete declarations fail at upload validation, not at review.

---

## 4. App Review notes

Paste into the Review Notes field. Reviewers reject what they cannot reach.

```
Big Talk is a speech practice app. Transcription and scoring run entirely on
device; there is no server, no account, and no sign-in. Nothing is uploaded.

MICROPHONE AND SPEECH PERMISSIONS
Both are requested during onboarding and are required to record and score a
session. Please allow both.

FIRST RUN
1. Complete onboarding (about two minutes; it ends with a guided baseline
   recording and its score).
2. Tap the record button on the Today tab and speak for 20-60 seconds about
   anything.
3. Stop. The first analysis downloads a small on-device speech model, which can
   take up to a minute on first use only. The score screen follows.

IN-APP PURCHASE
One non-consumable: com.vansh.SpeakUpMore.lifetime.

The free tier is everything except iCloud sync for 14 days, measured from the
first completed analysis rather than from install. This is a time-limited free
tier, not an auto-renewing trial: no payment method is collected, nothing is
charged when it ends, and the app simply falls back to three full analyses per
rolling 30 days. Everything else — drills, warm-ups, read-aloud, user-written
scripts, progress cards — is free and ungated at all times.

Lifetime removes the analysis limit and keeps the eight-week curriculum,
journal PDF export, and iCloud sync after the 14 days.

HOW TO REACH THE PAYWALL DURING REVIEW
Open Settings and tap "Unlock" on the Big Talk Lifetime card at the top. This
works immediately, with no recording required, and during the free 14 days it
is the intended path — the curriculum and journal export are unlocked in that
window, so they will not raise the paywall. Turning on iCloud sync in Settings
raises it too, and is gated from the first launch.

The app does not raise the paywall on its own until the first analysis has
finished, by design — the free result is what earns the right to ask. Buttons
you tap yourself are never suppressed.

Restore is on the paywall and on the plan card at the top of Settings (that
card reads "Free plan" until a purchase is restored, then "Big Talk Lifetime").
Terms of Use and Privacy Policy links are in the paywall footer and in
Settings > About.

NETWORK USE
Two optional downloads, both user-visible and both skippable: the on-device
speech model on first analysis, and an optional local language model in
Settings > AI Model. The app is fully functional offline once the speech model
is present.
```

---

## 5. Screenshot plan

Six slides for iPhone 6.7" (1290 × 2796). App Store Connect rejects anything
that is not an exact match for the display size it is uploaded under.

**Background colour: `#0FB3AE`.** The app's own canvas is near-black navy, so a
dark background would swallow the device screens at thumbnail size. This is the
brand teal (`AppColors.primary`, `#0D8488`) pushed up in saturation and
lightness, which stays recognisably the app's colour while giving the dark
screenshots something to sit against. Same colour on all six.

Headlines are two lines: a big action verb and a smaller descriptor. Both are
short enough to sit inside the centre 70% of the canvas, which is what survives
the crop from 9:16 down to Apple's narrower ratio.

| # | Verb | Descriptor | Screen to capture | Required state |
|---|------|------------|-------------------|----------------|
| 1 | `SCORE` | `HOW YOU ACTUALLY SOUND` | `RecordingDetailView`, Breakdown tab, scrolled to the score ring and sub-score radar | A session scoring 70-85. Not 95 (reads fake) and not 40 (reads discouraging). Every optional sub-score present, so the radar is full. |
| 2 | `CATCH` | `FILLERS AS YOU SAY THEM` | `RecordingView` mid-recording, filler counter overlay visible | Counter showing 3-5, circular waveform active, timer around 0:35. |
| 3 | `DRILL` | `THE WEAK SPOT IT FINDS` | `RecordingDetailView` next-step card, or `DrillSessionView` mid-drill | Next-step card naming a real weak area with its score. If using the drill screen, capture Pace Control with the live WPM band visible. |
| 4 | `REHEARSE` | `YOUR OWN SCRIPT` | `StoryDetailView` for a story with practice history | A real script (a toast, an interview answer), 3+ linked sessions, tags populated. Not "Untitled". |
| 5 | `SEE` | `HOW FAR YOU HAVE COME` | `BeforeAfterReplayView` | At least 8 analysed sessions with a genuine upward trend, so the delta and the four metric rows all read as improvement. |
| 6 | `KEEP` | `EVERY WORD ON DEVICE` | `LifetimeFAQView`, privacy section, or Settings > Usage Diagnostics | The diagnostics screen is the stronger of the two — it shows the actual event log, which makes the claim concrete rather than a promise. |

### Capture rules for the whole set

- One appearance throughout. The app is locked to dark mode, so every capture is
  dark by definition — do not mix in a light-mode simulator.
- Clean status bar: `Simulator → Features → Status Bar`, override to 9:41, full
  bars, full battery, no carrier text.
- No empty states, no "Untitled", no `Test 1`. Seed realistic content first.
- Slide 1 does the most work. If only one screenshot is retaken, retake that one.

### Building the slides

The `aso-appstore-screenshots` skill turns these into finished slides, but it
needs a Mac: `compose.py` wants the SF Pro Display Black font at
`/Library/Fonts/SF-Pro-Display-Black.otf`, the crop step uses `sips`, and the
enhancement pass needs the Gemini MCP server. Run it from the repo root after
capturing the six screenshots above:

```bash
SKILL_DIR=".claude/skills/aso-appstore-screenshots"
python3 "$SKILL_DIR/compose.py" \
  --bg "#0FB3AE" --verb "SCORE" --desc "HOW YOU ACTUALLY SOUND" \
  --screenshot simulator-screenshots/01-breakdown.png \
  --output screenshots/01-score/scaffold.png
```

Then follow the skill's enhance → crop → review loop for each slide. The first
approved slide becomes the style template for the other five.

### App preview video (optional, 15-30s)

Worth doing after the screenshots, not before. The one loop that sells this app
is: tap record → speak → filler counter ticks up → stop → score lands. No
narration, no title cards; the counter moving while someone is mid-sentence is
the whole pitch.

---

## 6. Do not claim

Written down because each of these is a plausible-sounding line that the app
would not survive being held to.

- **"AI speech coach."** The scoring pipeline is signal processing and text
  analysis, not a model. The LLM pass is optional, off by default on devices
  without Apple Intelligence, and only adjusts one sub-score.
- **"Works with any language."** Transcription is English-only in practice, and
  the filler list, power words, and hedge detection are all English.
- **"Real-time coaching."** Live feedback is the filler counter and haptic pace
  cues. Everything else is post-session.
- **"Certified" / "clinically proven" / anything therapeutic.** Big Talk is a
  practice tool, not a speech-therapy device. Health claims move the app into a
  review category it is not built for.
- **A specific accuracy percentage.** Nothing in the repo measures transcription
  accuracy against a reference corpus, so any number would be made up.
- **"Free forever."** The free tier is 14 days of everything but iCloud sync,
  then three analyses per 30 days.
- **"Free trial" framed as a subscription trial.** No payment method is
  collected and nothing renews. Say "free for 14 days", never "trial period",
  "starts your subscription", or anything implying a charge at the end.
