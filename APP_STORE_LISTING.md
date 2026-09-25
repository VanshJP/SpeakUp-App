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
| App Name | 30 | `Big Talk: Public Speaking` | 25 |
| Subtitle | 30 | `Practice speeches & interviews` | 30 |

The name carries the category's highest-volume head term. `Big Talk` alone has
no search weight at launch — nobody is looking for it yet — so the twenty
characters after the colon are the most valuable real estate in the listing,
and they go to the phrase people actually type. `Speech Coach` was the previous
occupant and lost on volume; `speech` survives in the keyword field, so nothing
is dropped by the swap.

The subtitle spends its thirty characters on the two use cases that convert
best, rather than restating the name. Both terms are indexed.

### Keywords (100 characters, comma-separated, no spaces)

```
speech,interview,presentation,filler,toastmaster,pronunciation,voice,articulation,toast,pitch,coach
```

99 characters.

`public speaking` moved out of this field and into the app name. Apple indexes
name, subtitle, and keywords together, so a term in the name does not need a
slot here — that freed sixteen characters for `toast`, `pitch`, and `coach`,
all three of which map to shipped behaviour (story practice, the impromptu
sprint drill, the next-step card).

**Constraint that outranks normal ASO advice:** custom product pages can only
be assigned terms that exist in *this* field, not in the name (see
`APP_STORE_PRODUCT_PAGES.md`). Dropping `public speaking` therefore required
reassigning it on three of the four pages before it could leave. Any future
edit to this field has to check those assignments first — a page whose keyword
vanishes silently stops being reachable by search.

`interview` replaced `stutter` for the same reason: interview prep is both one
of the four audience pages and one of the app's five onboarding goals, and
leaving the term out made that page unreachable. `stutter` also pulled against
section 6 — it is a high-volume term whose searchers want a therapy tool,
which is precisely the claim this app must not make.

### Promotional text (170 characters, editable without a new build)

```
Record a minute. Get a real score on your pace, filler words, pauses, and clarity — worked out on your iPhone, never on a server. Everything free for 14 days.
```

158 characters. Promotional text is **not** indexed by App Store search, and
neither is the description. Only the app name, the subtitle, the keyword field,
and in-app purchase display names feed ranking — so everything below this line
is conversion copy, written for a person who has already landed on the page,
and should never be contorted to fit a keyword.

### Description (4000 characters — 3180 as written)

Paste-ready and unwrapped in `screenshots/listing-fields.txt`. The hard wraps
below are for reading this file only; App Store Connect keeps them verbatim, so
copy from the txt.

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
• Hundreds of prompts, from interview questions to impromptu topics, so you
  always know what to say next
• A live filler counter that ticks up while you are still talking, so you hear
  the habit as it happens

BRING YOUR OWN MATERIAL

Write or paste your own scripts — a wedding toast, a stand-up set, a
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
in the app container, and the only network calls are the optional coaching
model download from Hugging Face, iOS's own one-time download of its speech
model, and the user's own iCloud sync when they turn it on.

Finished takes are transcribed by Apple's `SpeechAnalyzer`, which has no server
path. The live recognizers are the enforcement detail: every
`SFSpeech*RecognitionRequest` in the app sets `requiresOnDeviceRecognition =
true` **unconditionally** (`DictationService`, `LiveTranscriptionService`,
`ReadAloudService`). Left unset — or made conditional on
`supportsOnDeviceRecognition`, which reads false while assets install — Apple
Speech is free to stream microphone audio to Apple's servers, and the sentence
above stops being true. An unavailable recognizer must fail loudly instead.

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

Seven slides at iPhone 6.9" (1320 × 2868) — the only iPhone display size App
Store Connect requires. Connect scales that set down for every smaller device,
so the old 6.5" export is gone and there is nothing else to upload. Files are
`screenshots/final/01-…` through `07-…`, numbered in upload order, and the
composer that builds them is `screenshots/compose_creative.py`.

**Treatment: graphite ground, per-slide accent.** The flat teal background in
the original plan was abandoned — it fought the app's own dark canvas instead of
framing it. Each slide now sits on near-black with a colour glow behind the
device, and that colour is the one the captured screen already uses for its
data. The set reads as one system without any slide repeating a backdrop.

Every headline is one line. The composer picks the largest size that keeps it
there (92-100 across this set), so each headline fills the same measure and the
varying sizes read as deliberate. A headline that will not fit gets shortened,
not shrunk — `fit_headline` wraps only as a last resort, and a wrapped headline
means the copy is too long.

| # | Headline | Subhead | Screen |
|---|----------|---------|--------|
| 1 | Practice Public Speaking | Feedback on pace, clarity and fillers | `RecordingDetailView` breakdown — score ring and full sub-score radar |
| 2 | Stop Saying Um and Like | Every filler marked where you said it | Transcript with fillers marked inline |
| 3 | Rehearse Your Speech | Toasts, interviews, pitches, presentations | `StoryDetailView` with linked practice history |
| 4 | 430 Speaking Prompts | Always know what to say next | Prompt library |
| 5 | Practice a Minute a Day | Short sessions that actually add up | Today tab |
| 6 | Watch Your Scores Rise | Every metric charted over time | Progress charts |
| 7 | It Stays On Your iPhone | No account, no upload, no server | Settings > AI Features |

**Slide 4 states a number.** `430` matches `DefaultPrompts.all` as of this edit
and is baked into an image rather than a text field, so it goes stale silently
the moment prompts are added or removed. Re-check it against
`SpeakUp/Data/DefaultPrompts.swift` before every submission
(`grep -c "PromptData(" SpeakUp/Data/DefaultPrompts.swift`), or replace it with
`Hundreds of`.

**Slide 7 no longer claims AI coaching.** The earlier `Private AI Speech
Coaching` headline was the exact framing section 6 rules out; it now reads
`It Stays On Your iPhone`, which is both true and the stronger line.

Known gaps in the shipped set, both needing a capture session:

- **The raw captures predate 84 commits of UI work** (taken 2026-08-14). Slides
  render correctly, but they show an older build. Re-capture before submitting.
- **Slide 2 shows nav-bar bleed-through** — the previous screen's text ghosts
  behind the translucent header. Re-capture with the detail view scrolled so
  nothing sits under the bar.
- **No live-recording slide** — the filler counter ticking mid-sentence, which
  the original plan had at position 2. The simulator has no usable microphone,
  so it needs a physical device. It is the single best frame the app has.

### Capture rules for the whole set

- One appearance throughout. The app is locked to dark mode, so every capture is
  dark by definition — do not mix in a light-mode simulator.
- Clean status bar: `Simulator → Features → Status Bar`, override to 9:41, full
  bars, full battery, no carrier text.
- Capture on iPhone 17 Pro Max. Any other device is the wrong pixel size and the
  composer will refuse it.
- No empty states, no "Untitled", no `Test 1`. Launch with `-seedScreenshotData`
  (`SpeakUp/Debug/ScreenshotSeeder.swift`) on a fresh install — it writes twelve
  sessions climbing 58 → 84 and one story with linked practice, which is what
  makes the progress and story slides worth capturing at all.
- No DEBUG-only UI in frame. Usage Diagnostics renders a "Force Lifetime" toggle
  and trial overrides in a debug build; use `PrivacyDataView` instead.
- Slide 1 does the most work. If only one screenshot is retaken, retake that one.

### Building the slides

```bash
python3 screenshots/compose_creative.py
```

Reads raw captures from `simulator-screenshots/`, writes finished slides to
`screenshots/final/`. Needs a Mac: SF Pro Display Black and Medium at
`/Library/Fonts/`, and Pillow. Headlines, subheads, accents, and source captures
all live in the `SLIDES` table at the bottom of that file — edit copy there, not
in an image editor.

Captures must be 1320 × 2868 (an iPhone 17 Pro Max / 16 Pro Max simulator). The
composer refuses anything else rather than scaling it — the old `shot_offset`
crop silently squashed slide 2's UI, and that is the failure mode this guard
exists to stop. A screen that needs to be scrolled gets captured scrolled.

The `aso-appstore-screenshots` skill's own `compose.py` produced the earlier
flat-background scaffolds and still works, but its device frame deliberately
bleeds off-canvas, which is why the current composer draws its own.

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
