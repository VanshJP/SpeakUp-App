# Onboarding Redesign — Big Talk

**Goal:** a first-time user reaches their first completed baseline recording feeling guided, confident, and excited — never wondering "what am I supposed to do right now?"

**Activation moment:** user completes a baseline recording ≥30s, sees its score, understands why it matters, and knows what the app will do with it. Every screen in this document exists only to reach that moment with the least cognitive effort.

Source of truth: real user feedback ("I'm overwhelmed", "the prompt disappeared immediately", "I got put into a lesson but had no idea what I was supposed to say", "I didn't know if there was a script", "the baseline recording should be the first guided experience", "don't make it feel like a chore", "too much reading makes people turn their brains off").

> **Status: design record, not current state.** This document is the research and
> rationale behind the redesign. `ONBOARDING_VISION.md` is the contract and wins
> on any disagreement. Shipped behaviour has since moved on in four places:
>
> - **Goal is multi-select** (1 to 3 picks) and the picks weight the daily prompt
>   category mix via `Models/PromptMix.swift`. This document describes a single
>   pick that only aimed coaching.
> - **Nothing auto-advances.** Goal and level show their payoff line and wait for
>   an explicit Continue. Testers read the timed jump as the app deciding for
>   them, and it made a second goal pick a race against the timer.
> - **The reveal has one action** — `See my full breakdown`. The `Take me home`
>   alternative below was cut: it let people opt out one tap before the screen
>   that explains the number they were just shown.
> - **Script mode was cut** (2026-08-05). Big Talk trains thinking on the spot;
>   Read-Aloud practice lives in the Library instead. Baseline copy quotes **30
>   seconds**, not the 45 used in early drafts below.

---

## 1. UX Audit of the Current Onboarding

What actually happens today (traced through `OnboardingView` → `ContentView.fullScreenCover` → `CountdownOverlayView` → `RecordingView`):

Welcome → How It Works → What's Inside → Name → Goal → Level → Vocab → Mic → Ready → *(500ms delay)* → 3-2-1 countdown with `prompt: nil` → full-screen recorder, **already recording**, 60-second timer, **nothing on screen telling you what to say**.

### The fatal flaw

**F1. The baseline recording — the entire point of the flow — is the only unguided moment in it.** Nine screens of preparation, then the app launches `recordingPrompt = nil` (`ContentView.swift:362`). The user free-falls into `RecordingView` where the prompt card renders only `if let prompt` (`RecordingView.swift:302`) — so a first-timer sees a timer, a waveform, and a red button. This is the exact moment of maximum anxiety (a mic is live, a clock is running) paired with minimum guidance. Every line of the user's feedback maps to this one handoff.

**F2. Recording starts without consent-in-the-moment.** The countdown auto-fires 500ms after onboarding dismisses. The user never presses record for their first-ever recording. Loss of control is the textbook anxiety trigger — performance anxiety research consistently shows perceived control is the main lever on state anxiety. They toggled a switch ~30 seconds ago on a different screen; that is not the same as choosing to start *now*.

**F3. The prompt disappears — literally the user's words.** When a prompt *does* exist, `CountdownOverlayView` shows a `prominentPromptCard`, then the recorder replaces it with a `compactPromptCard` (category + small text) — and in the baseline case there is no prompt at all. The one piece of information the user is desperately holding onto is taken away at the moment recording starts.

### Cognitive overload

- **C1. Two consecutive reading screens before anything interactive.** "How It Works" (3 beats × 2 lines) then "What's Inside" (10 feature tiles + a 40-word privacy paragraph). That's ~120 words of reading with zero interaction. "Too much reading makes people turn their brains off" — this is where it happens. Feature inventories serve the *builder's* pride, not the user's needs; a first-time user cannot cache 10 feature names, so the grid produces the *feeling* of complexity while transmitting nothing.
- **C2. The Vocab step is homework.** Mid-flow, the user is asked to curate a word list — a text field, a dictation mic, spell-check rejections with warning notes — before they've ever recorded. It's the "never like setup, never like homework" violation in its purest form. Its own docs admit the seeds are fine ("surfaced on the ready step as a quick preview").
- **C3. The Ready step asks for a decision at the finish line.** A summary table (a receipt — reads as "setup complete", i.e., confirms this *was* setup) plus a toggle ("Start a 60-second session right now") — a commitment decision framed in the scariest possible unit ("60 seconds" reads as a long time to speak when you don't know what to say).

### Missing context

- **M1. "Baseline" appears once, in small gray text, on the last screen** ("Your first recording is the baseline every later session gets compared against"). The single most motivating concept in the product — *this recording is your starting line, and the app will show you improving against it* — is a subtitle nobody reads at the moment they're bracing to perform.
- **M2. Nothing ever answers: what should I say? how long is enough? can I retry? what happens after?** These are the questions the user actually walked in with. The flow answers questions they didn't ask (which 10 features exist, which difficulty mix their prompts will have).
- **M3. The 60-second timer implies a requirement.** Nothing says a shorter recording is valid. The scoring engine's substance curve handles ~30s fine — the user is never told.

### Interaction & pacing problems

- **I1. The mic step is titled "Say something."** The user's feedback verbatim describes this anti-pattern. It's actually the best screen in the flow (live waveform, "Mic is working" pill) — but its copy squanders it. It also asks the user to *perform* before explaining that this is just a sound check that isn't kept or scored.
- **I2. Nine steps before the payoff.** Duolingo-length quiz without Duolingo's per-answer payoff. Goal and Level selections produce no visible personalization response ("since you picked X, you'll get Y") until a recap table at the end.
- **I3. Keyboard-first steps early.** Name (focused keyboard at step 4) and Vocab (keyboard + dictation) put typing — the highest-effort mobile interaction — in a flow that's supposed to feel light.

### Emotional friction & trust

- **E1. No emotional arc.** The flow is emotionally flat: inform → ask → ask → ask → done. There is no moment of "it heard me!" delight (the mic pill comes closest), no anticipation build, no celebration. Compare: Duolingo ends onboarding with a full-screen "Learning legend!" celebration.
- **E2. First-score risk is unmanaged.** A nervous first take can hit the gibberish gate or substance multiplier and score in the teens. Showing a 14/100 as the user's first-ever result is a churn event. Nothing in the current flow prevents it.
- **E3. Privacy is argued in paragraphs, not shown in moments.** The trust pills on the cover are good; the 40-word iCloud caveat card is a lawyer talking.

### What's already right (keep these)

- Deferred asks (`FirstRecordingSetupSheet` for calibration / AI model / reminders *after* the first score) — this is exactly Headspace's pattern. Keep.
- The live mic waveform + `hasHeardVoice` pill — the only "alive" moment in the flow. Promote it.
- Resume persistence, per-step analytics funnel (`skip` vs `continue`), the tick meter, equal-gutter top bar, dark hero bookends. All solid scaffolding — reuse.

---

## 2. Lessons from the Mobbin Case Studies

Reverse-engineered psychology, not screenshot descriptions. Each ends with what Big Talk steals.

### Duolingo — [onboarding](https://mobbin.com/flows/b0b4f93f-5637-46ec-9d77-49ecda6b991d) · [first lesson](https://mobbin.com/flows/b736389a-cb5c-4889-8011-a220baf09171)
1. **Activation moment:** completing lesson 1 — which happens *inside* onboarding, before account creation.
2. **Anxiety reduction:** the owl asks one question per screen in a speech bubble — a conversation, not a form. The first lesson's first exercise is trivially easy multiple-choice (guessable even with zero knowledge) — engineered early success.
3. **Delayed information:** everything. No feature tour, no explanation of hearts/leagues/streaks. You learn the product by using it.
4. **Alive:** mascot reacts to answers; answers echo back as commitments ("I'M COMMITTED" instead of "Continue"); per-answer payoff ("Since you know a few words, let's start at Score 10!").
5. **Guidance into first action:** the lesson *is* the last onboarding step; there is no handoff to fumble.
6. **Steal:** put the baseline *inside* onboarding as its climax; make the CTA language commitment-flavored; give each answer an immediate visible consequence; end with a celebration screen carrying real stats.

### Headspace — [onboarding](https://mobbin.com/flows/31b21791-dec6-448a-8253-648f5ebbba3e) · [starting a course](https://mobbin.com/flows/7d991d93-45b1-4ec9-bb5a-e89fd324d89a)
1. **Activation:** finishing Basics Session 1 (audio).
2. **Anxiety:** one intent question ("What's on your mind?"); the quiz is framed as a *reveal* ("Answer a few questions and we'll reveal which course…") — you're receiving, not filling out. The recommendation ships with "Why this recommendation," which converts a black box into a considered gift.
3. **Delayed:** reminders, notifications, HealthKit — all offered *after* session 1 completes, when the product has earned them.
4. **Alive:** the breathing orb ("Breathe in") makes the first screen a tiny practice of the product itself.
5. **Guidance:** course → session 1 is a single obvious path; the session has live captions so you're never lost.
6. **Steal:** Big Talk already defers the permission cluster — keep. Add: frame the setup questions as building toward a reveal; make the cover screen itself a micro-practice (the orb should *breathe*); explain recommendations ("Because you chose interviews…").

### Speechify — [onboarding](https://mobbin.com/flows/6ba96348-6b9d-43a5-a608-d84a78a2eeb0) · [voice sample screen](https://mobbin.com/screens/fed530bb-bb3e-47ac-86d9-8720c0ba45ed)
1. **Activation:** hearing your first document read aloud (and for voice cloning: recording the sample).
2. **Anxiety:** name captured first, then every question addresses you by name ("Sam, what do you want to read…?") — the app models a person, not a database.
3. **Delayed:** everything technical. The voice sample screen is radically simple: "Record the sample — read this text," a script card, one red button. The script removes *all* composition burden.
4. **Alive:** "Sam, we are finalizing your listening plan" with checkmark rows ticking in — anticipation as UI.
5. **Steal:** the exact voice-sample pattern (script on screen + one button) as the baseline's zero-thought fallback; the "finalizing your plan" recap as a *pre-baseline* hype beat rather than a post-hoc receipt.

### Meta AI — [voice sample](https://mobbin.com/screens/bd96b097-5c27-43e0-a3f6-a95159165424) · [glasses setup](https://mobbin.com/flows/5cdc8697-5e92-4141-ab8e-ce21fcc18670)
1. The voice-clone sample screen: "Read these sentences," **the full script stays visible while recording**, progress reads `0:13 / 0:30` beneath a live waveform. Nothing disappears mid-take.
2. The glasses first-conversation screen is a teleprompter: `Say: "…"` → `Now say: "…"` — the app literally puts words in your mouth, stepwise.
3. **Steal:** script pinned and persistent during recording (the direct fix for "the prompt disappeared immediately"); progress as `elapsed / target` rather than a countdown; teleprompter-style "start with:" scaffolding.

### Character AI — [Create Voice](https://mobbin.com/screens/cc148ee0-f628-49ad-8c4f-fbec2c26a152)
Constraints stated in two plain lines before the button ("Record a clip 3–15s long. Avoid background noise."), a "Try saying…" script card, and a refresh icon to swap scripts. **Steal:** state the rules in one breath (how long, what to avoid, retryable), and let the user swap the prompt if it doesn't fit — control kills anxiety.

### Speak — [speaking lesson](https://mobbin.com/screens/3e01c79e-3175-4df8-9fc6-91966389ffb3)
A *speaking-first* learning app: `Say, "Nice to meet you!"` with a "Speak now…" affordance, a discard ✕, and a keyboard fallback. Warm-up section is labeled "Refresh your memory with some quick practice." **Steal:** always show the escape hatches next to the mic (redo, fallback); label the first real exercise as a warm-up so failure is definitionally impossible.

### Oura — [unguided session](https://mobbin.com/flows/781d9e8d-d7c5-431f-abbf-aa4ae1238877)
1. Before you commit to a session, the duration picker shows "You'll see: Heart rate · HRV · Skin temp" — **what you get, before you give**.
2. Results are framed against *your* baseline ("Your nighttime baseline is 48 bpm") — the number is a comparison to yourself, never a judgment.
3. Measurement-quality coaching without blame: "Excessive hand movement may have affected the quality… next time, try to remain as still as possible."
4. **Steal:** the entire baseline *framing* ("your starting line, everything compares to this"); before recording, show the 3–4 metrics the user is about to unlock; quality problems (silence, too short) get coached, never scored.

### Life Reset — [building your profile](https://mobbin.com/screens/cf33e352-fc3f-4018-9d31-6ec3f469b020) · Cleo — [checklist](https://mobbin.com/screens/bae4115d-f0c5-457a-bc4b-4d9abf0a6276)
Loading as theater: "Building your profile…" with sequential check lines ("Identifying patterns ✓ Matching insights ✓"). Cleo: "You're on a roll" checklist momentum. **Steal:** the post-recording analysis wait (Whisper transcription is genuinely slow on first run) becomes the *best* screen in the flow — real pipeline stages ticking in, labor-illusion working for us. Never a bare spinner.

### Microsoft Copilot — [onboarding](https://mobbin.com/flows/b83a3666-782d-4077-a2ad-8fee91eae1cd)
"Nice to meet you, Sam. How should my voice sound?" — one warm question per screen, name woven in immediately, choices as tappable cards with friendly names. **Steal:** the conversational register for every question screen; tap-to-advance on single-choice questions (no redundant Continue).

### Cross-product synthesis — the six laws

1. **The first meaningful action lives inside onboarding.** Never hand off at the scary moment (Duolingo, Headspace, Speak).
2. **One question, one screen, one tap.** Speech bubbles beat section headers. Tapping an answer *is* the continue (Duolingo, Copilot).
3. **Every input gets a visible payoff within one screen** ("Because you said X → Y") (Duolingo, Headspace, Speechify).
4. **Words on screen during performance.** Scripts/prompts persist through the entire take (Meta AI, Speechify, Character AI, Speak).
5. **Ask for effort/permissions only after delivering value** (Headspace, and Big Talk's own deferred steps — already right).
6. **Waiting is a stage, not a spinner** (Life Reset, Duolingo's per-answer processing beats).

---

## 3. Design Principles for This Flow

1. **The baseline is the destination, not the doorstep.** Every screen before it either builds capability (mic works), context (why we're recording), or courage (what to say). Anything else is cut.
2. **Coach, don't configure.** Every screen is something a human coach would *say*, in the order they'd say it. If a sentence wouldn't come out of a coach's mouth in the first five minutes, it doesn't appear.
3. **Teach through interaction, never through paragraphs.** Hard cap: no screen carries more than ~25 words of body copy. Anything needing more gets taught by doing or deferred to the moment it matters.
4. **The user presses every record button.** No auto-started recording, ever. Countdown only after their tap, with the prompt visible through it.
5. **Nothing the user needs disappears.** The prompt/script is pinned for the entire take.
6. **The first number is never a grade.** Baseline framing everywhere: "starting line," "compared only to you." Quality failures get coached ("we couldn't hear enough"), never scored (no 8/100 on day one).
7. **Escape hatches at arm's length, shame-free.** Restart, swap prompt, read a script instead, skip for now — visible at the moment of panic, not chosen in advance.
8. **Earn every tap.** Each screen ends with a reason to want the next one (a payoff, a reveal, a promise one step from being kept).

---

## 4. The New Flow

Nine screens → six beats. Reading screens: two → zero. Time to baseline: ~90 seconds of interaction.

```
1. COVER        "Hear yourself improve."          (orb breathes — the app is alive)
2. NAME         "What should we call you?"        (one field, skippable)
3. GOAL         "What brought you here, Vansh?"   (shipped: multi-select + payoff line + Continue)
4. LEVEL        "Where are you starting from?"    (shipped: tap card + payoff line + Continue)
5. SOUND CHECK  "Let's make sure we can hear you" (mic permission + live waveform test)
6. THE BASELINE  a) Briefing — coach cascade, 3 beats, conversational
                 b) Recording — prompt pinned, user-initiated, guided live
                 c) Analyzing — real pipeline stages ticking in
                 d) Reveal — starting line + one insight + celebration
→ TodayView (Day 1 streak lit; FirstRecordingSetupSheet later, unchanged)
```

Cut from the first run: **How It Works** (its one essential promise moves to the Cover subtitle; the rest is taught by the baseline itself), **What's Inside** (the product teaches its own inventory; Library tab exists), **Vocab** (seeds applied silently from level — current `vocabSeeds(for:)` logic unchanged — editable in Settings → Word Bank; the reveal screen plants the pointer), **Ready recap + toggle** (the flow no longer needs a receipt or a decision — the baseline is inside it).

Kept from the current build: `OnboardingPage` scaffold, tick meter, back/skip top bar, UserDefaults resume, analytics funnel, deferred `FirstRecordingSetupSheet`, the mic step's waveform machinery, `AnalyzingView`'s pipeline hooks, `CoachingTipService` for the first insight.

---

## 5–6. Screen-by-Screen Wireframes + Microcopy

Copy is final-intent quality: simple, confident, minimal, friendly. No marketing fluff.

---

### Screen 1 — Cover

**Purpose:** one promise, one tap, zero anxiety. **Primary emotion:** calm curiosity.

```
┌─────────────────────────────┐
│                             │
│         ( ~ orb ~ )         │   orb slowly breathes: scale 1.0→1.06,
│                             │   6s cycle, teal glow swells with it
│         BIG TALK            │
│   Hear yourself improve.    │
│                             │
│   Speak for a minute a day. │
│   Big Talk listens, scores, │
│   and coaches — all on      │
│   this iPhone.              │
│                             │
│  [On-device] [Offline]      │
│  [No account]               │
│                             │
│  ┌───────────────────────┐  │
│  │      Let's start      │  │
│  └───────────────────────┘  │
│   About two minutes.        │
└─────────────────────────────┘
```

- **Headline:** `Hear yourself improve.` **Supporting:** `Speak for a minute a day. Big Talk listens, scores, and coaches — all on this iPhone.`
- **CTA:** `Let's start` **Caption:** `About two minutes.` **Progress:** none (cover).
- **Animation:** staggered fade-up (existing pattern); the orb *breathes* on a 6s cycle — Headspace's trick of making screen one a tiny practice of the product's calm.
- **Interaction:** single tap. On tap, kick off `WhisperService` preload in the background so the model is warm before the baseline needs it.
- **Why it exists:** first impressions set the emotional register; the trust pills answer the privacy question before it forms. **If removed:** the flow opens on a question from a stranger — trust and tone never get established.

---

### Screen 2 — Name

**Purpose:** turn every following screen into a conversation. **Primary emotion:** ease.

```
┌─────────────────────────────┐
│ ●○○○                        │
│                             │
│  What should we call you?   │
│                             │
│  ┌───────────────────────┐  │
│  │ Your name              │  │
│  └───────────────────────┘  │
│                             │
│  Stays on this iPhone.      │
│                             │
│  ┌───────────────────────┐  │
│  │       Continue        │  │
│  └───────────────────────┘  │
│         Skip                │
└─────────────────────────────┘
```

- **Headline:** `What should we call you?` **Supporting:** `Stays on this iPhone.` (four words — the whole privacy story at the moment it's relevant; drop the dictionary explanation, which is plumbing).
- **CTA:** `Continue` (enabled with text) / top-bar `Skip` allowed — a name should never gate a voice app.
- **Animation:** keyboard rises after crossfade settles (existing 420ms task — keep).
- **Interaction:** text field, `.done` submits.
- **Why it exists:** Speechify/Copilot show that name-first makes every later screen warmer at near-zero cost; the name also seeds the dictation dictionary (silent side effect — keep the `makeResult` logic). **If removed:** goal/reveal screens lose their address-by-name warmth; measurable drop in perceived personalization for one saved tap. Keep, but skippable.

---

### Screen 3 — Goal

**Purpose:** aim the coaching; give the first personalization payoff. **Primary emotion:** feeling understood.

```
┌─────────────────────────────┐
│ ●●○○                        │
│                             │
│  What brought you here,     │
│  Vansh?                     │
│                             │
│  ┌ Speak up at work       ┐ │
│  ┌ Nail interviews        ┐ │
│  ┌ Everyday confidence  ✓ ┐ │
│  ┌ Public speaking        ┐ │
│  ┌ Sound clearer          ┐ │
│                             │
│  ✓ Got it. Your daily       │
│    prompts will lean        │
│    everyday-conversation.   │
└─────────────────────────────┘
```

- **Headline:** `What brought you here, Vansh?` (existing copy — it's good).
- **Interaction (as drafted):** tap card → payoff line materializes under the list → auto-advance after ~900ms, no Continue button. (Duolingo/Copilot: the answer is the navigation.) **As shipped:** the step is multi-select (1 to 3) with a permanent Continue, because a timed jump turns a second pick into a race — and the picks now weight the prompt category mix, not just tip tone.
- **Microcopy payoffs (one per goal):** work → `Got it. Prompts will lean toward meetings and updates.` · interviews → `Got it. Expect interview-style questions.` · confidence → `Got it. Prompts will feel like everyday conversation.` · public speaking → `Got it. Expect prompts you could open a talk with.` · clarity → `Got it. Coaching will focus on pace and crispness.`
- **Animation:** selected card lifts + teal hairline; payoff line slides in from below with `Haptics.selection()`; others dim 40%.
- **Why it exists:** the goal drives prompt selection and tip weighting — and the *payoff line* is the proof the app listened (audit gap I2). **If removed:** coaching is generic and the user's first score has no "for you" story; personalization would have to be inferred silently, invisibly.

---

### Screen 4 — Level

**Purpose:** set difficulty + silently seed vocab. **Primary emotion:** honesty without judgment.

```
┌─────────────────────────────┐
│ ●●●○                        │
│                             │
│  How do you feel about      │
│  speaking today?            │
│                             │
│  ┌ Finding my feet        ┐ │
│  │  I avoid it when I can │ │
│  ┌ Getting comfortable  ✓ ┐ │
│  │  Fine, want to be good │ │
│  ┌ Sharpening up          ┐ │
│  │  Good, chasing great   │ │
│                             │
│  ✓ We'll start you with     │
│    mostly medium prompts.   │
└─────────────────────────────┘
```

- **Headline:** `How do you feel about speaking today?` — a feelings question, not an assessment ("Where are you starting from" + "Beginner" labels make people grade themselves; self-assessment is exactly the anxiety we're removing).
- **Options map to existing `SpeakerLevel`:** beginner = `Finding my feet — I avoid it when I can` · intermediate = `Getting comfortable — fine, but I want to be good` · advanced = `Sharpening up — good, chasing great`.
- **Interaction:** tap → payoff line (`We'll start you gentle and ramp up.` / `We'll start you with mostly medium prompts.` / `We'll skew your prompts hard.`) → Continue. (Drafted as auto-advance; shipped with an explicit Continue to match the goal step.) Vocab seeds applied silently via existing `vocabSeeds(for:)`.
- **Why it exists:** drives `dailyDifficultyWeights` and vocab seeding — real product consequences from one tap. **If removed:** everyone gets intermediate defaults; recoverable in Settings, but the flow loses its second "it listened" beat. This is the first screen to cut if the funnel says four questions is one too many — the payoff line is what earns its slot.

---

### Screen 5 — Sound Check

**Purpose:** mic permission + proof the app hears you — reframed from "perform" to "test the equipment." **Primary emotion:** playful confidence ("it works!").

```
   Before permission:                After permission:
┌─────────────────────────────┐   ┌─────────────────────────────┐
│ ●●●●                        │   │ ●●●●                        │
│  Let's make sure we can     │   │  Sound check                │
│  hear you                   │   │  Say anything. Try          │
│                             │   │  "testing, one two three."  │
│  Big Talk listens only      │   │                             │
│  while you're recording.    │   │   ▁▂▅▇▅▂▁▂▅▇▅▂▁  (live)     │
│  Audio stays on this        │   │                             │
│  iPhone.                    │   │   ✓ Loud and clear          │
│                             │   │                             │
│  ┌───────────────────────┐  │   │  ┌───────────────────────┐  │
│  │   Allow microphone    │  │   │  │       I'm ready       │  │
│  └───────────────────────┘  │   │  └───────────────────────┘  │
└─────────────────────────────┘   └─────────────────────────────┘
```

- **Pre-permission headline:** `Let's make sure we can hear you` **Supporting:** `Big Talk listens only while you're recording. Audio stays on this iPhone.` (two lines replace the current three-bullet card — bullets read as terms & conditions).
- **Post-permission headline:** `Sound check` **Supporting:** `Say anything. Try "testing, one two three."` — *sound check* is the crucial reframe: roadies do sound checks; nobody judges a sound check. Fixes the "Say something" anti-pattern while keeping the entire existing waveform + `hasHeardVoice` machinery.
- **On voice detected:** pill flips to `✓ Loud and clear` with `Haptics.success()` — the flow's first micro-win, deliberately cheap to earn.
- **CTA:** `I'm ready` (not "Continue" — it's the hinge into the main event; commitment language per Duolingo).
- **Why it exists:** permission is a hard requirement, and hearing-yourself-registered converts the mic from threat to toy before the take that counts. **If removed:** the permission dialog ambushes the user inside the baseline, and the first time they see the app react to their voice is while being scored — maximum-stakes discovery.

---

### Screen 6a — Baseline Briefing (the coach sits down)

**Purpose:** answer *why / what / what are the rules* in one conversational beat. **Primary emotion:** anticipation, held hand.

```
┌─────────────────────────────┐
│                             │
│   ( orb, listening pose )   │
│                             │
│  ╭─────────────────────╮    │
│  │ One recording, and   │   │  ← beat 1, fades up
│  │ I'll know your voice.│   │
│  ╰─────────────────────╯    │
│  ╭─────────────────────╮    │
│  │ I'll measure pace,   │   │  ← beat 2, +0.9s
│  │ clarity, fillers,    │   │    [pace][clarity][filler]
│  │ and pauses.          │   │    chips pop in one by one
│  ╰─────────────────────╯    │
│  ╭─────────────────────╮    │
│  │ 30 seconds. No grade,│   │  ← beat 3, +1.8s
│  │ no pressure — this is│   │
│  │ your starting line.  │   │
│  ╰─────────────────────╯    │
│                             │
│  ┌───────────────────────┐  │
│  │  Set my starting line │  │
│  └───────────────────────┘  │
│      What will I say?       │
└─────────────────────────────┘
```

- **Copy, exactly:** `One recording, and I'll know your voice.` → `I'll measure pace, clarity, fillers, and pauses.` (four metric chips pop in with the words — Oura's "You'll see: HR · HRV" pattern) → `30 seconds is enough. No grade, no pressure. This is your starting line.` (30 is the only duration onboarding copy ever quotes; early drafts said 45.)
- **Interaction:** bubbles cascade automatically (0.9s apart); a tap fast-forwards the cascade. `What will I say?` is a quiet text button → opens the prompt preview early (same content as 6b's prompt card) for users whose anxiety is specifically compositional.
- **CTA:** `Set my starting line` — the feature is named by what it does *for* them.
- **Progress:** ticks replaced by a subtle `Your baseline` eyebrow — this is no longer a step among steps; it's the event.
- **Why it exists:** this is the coach-beside-you moment the user asked for; it answers *why are we recording / what are we measuring / how long / is it graded* in three spoken-register lines, before the mic is anywhere near live. **If removed:** the recording screen must carry all context itself and becomes the wall of text we're forbidding; the emotional pivot from "setup" to "event" never happens.

---

### Screen 6b — The Baseline Recording (the centerpiece)

**Purpose:** the first guided take. **Primary emotion:** "I know exactly what to do."

```
   Ready state:                       Recording state:
┌─────────────────────────────┐   ┌─────────────────────────────┐
│  YOUR BASELINE      Swap ⟳  │   │  YOUR BASELINE              │
│ ┌─────────────────────────┐ │   │ ┌─────────────────────────┐ │
│ │ Introduce yourself.     │ │   │ │ Introduce yourself.     │ │
│ │ What do you do, and     │ │   │ │ What do you do, and     │ │
│ │ what kind of speaking   │ │   │ │ what kind of speaking   │ │
│ │ do you want to improve? │ │   │ │ do you want to improve? │ │
│ └─────────────────────────┘ │   │ └─────────────────────────┘ │
│  If you're stuck, start:    │   │                             │
│  ┌ "My name is…"          ┐ │   │      0:19  ╌╌╌╌│╌╌╌╌        │
│  ┌ "I spend my days…"     ┐ │   │            30s = enough ✓   │
│  ┌ "I want to sound…"     ┐ │   │                             │
│                             │   │     ▁▂▅▇▅▂▁▂▅▇▅▂▁           │
│       ┌─────────┐           │   │   "You're doing great."     │
│       │  ● REC  │           │   │                             │
│       └─────────┘           │   │   ┌──────┐    ┌─────────┐   │
│  Tap when you're ready.     │   │   │ ↺    │    │  ■ Done │   │
│  You can retry as many      │   │   └──────┘    └─────────┘   │
│  times as you like.         │   │    Start over               │
│                             │   │                             │
│  (script fallback: cut)     │   │                             │
└─────────────────────────────┘   └─────────────────────────────┘
```

**The seven anxious questions, answered *in the interface*, never dumped in one block:**

| Question | Where it's answered |
|---|---|
| Why are we recording? | 6a beat 1 + eyebrow `YOUR BASELINE` |
| What are we measuring? | 6a beat 2 (metric chips) |
| How long? | 6a beat 3 + the 30s "enough" tick on the progress line |
| What should I say? | Prompt card, pinned forever + three starter chips + `Swap ⟳` |
| What if I mess up? | `Start over` visible from second zero + ready-state caption |
| Can I retry? | `You can retry as many times as you like.` printed *before* the first take |
| What happens next? | 6a CTA promise + analyzing screen delivers it |

**Ready state:**
- Prompt card pinned top. Default prompt: `Introduce yourself. What do you do, and what kind of speaking do you want to improve?` — chosen because everyone can answer it, it produces natural free speech (better baseline data than read speech), and its content feeds the goal narrative.
- Three starter chips (teleprompter scaffolding, Meta AI glasses pattern): `"My name is…"` · `"I spend my days…"` · `"I want to sound…"`. Tapping one gently pulses it — they're crutches to read, not inputs.
- `Swap ⟳` cycles 3 alternate prompts (e.g., `Describe your typical morning, start to finish.` / `What's something you know a lot about? Explain it simply.`) — Character AI's swap affordance; control kills panic.
- ~~`Read a script instead`~~ **Cut 2026-08-05.** Drafted as a quiet button swapping the card for a short `ReadAloudPassage`. Removed because a read-aloud baseline trains the wrong muscle and doesn't compare honestly against the spontaneous sessions that follow it; the starter chips remain the anti-freeze aid, and Read-Aloud practice lives in the Library. See `ONBOARDING_VISION.md` → "Deliberately cut".
- **The user taps record.** 3-2-1 countdown plays *in the button itself* — the prompt card never leaves the screen (fixes F2 + F3 in one move).
- Caption: `Tap when you're ready. You can retry as many times as you like.`

**Recording state:**
- Prompt card stays exactly where it was (opacity 0.9 — present, not shouting).
- Time counts **up** with a tick at 0:30 labeled `30s = enough ✓`; the bar keeps filling to a soft 1:30 cap. Counting up says "look what you've built"; counting down says "time is running out."
- One-line encouragements fade through beneath the waveform: 0:08 `You're doing great.` → 0:22 `Keep going — say it however it comes.` → 0:31 (tick reached, `Haptics.light()`) `That's enough for a baseline. Stop anytime — or keep rolling.` → 0:55 `Strong. Wrap up whenever you like.`
- `Done` (primary) enabled from 0:10; before 0:30 tapping it asks nothing — a short take is *accepted*, and quality is handled at analysis, not litigated mid-take. `Start over ↺` (ghost) always present; tapping: `No problem. Nothing was saved.` → instant reset to ready state, same prompt.

**Why this screen exists:** it *is* the product's activation moment; every design choice above is a direct answer to a line of user feedback. **If removed** (i.e., baseline handled by the generic `RecordingView`): the redesign is cosmetic and the original failure recurs — the generic recorder is optimized for the hundredth take, not the first.

---

### Screen 6c — Analyzing (loading with purpose)

**Purpose:** absorb 5–20s of real pipeline latency as anticipation. **Primary emotion:** "it's working *for me*."

```
┌─────────────────────────────┐
│                             │
│      ( orb, thinking )      │
│                             │
│   Reading your voice…       │
│                             │
│   ✓ Transcribing your words │
│   ✓ Measuring your pace     │
│   ◌ Counting pauses and     │
│     fillers                 │
│   ◌ Setting your baseline   │
│                             │
│   You said 112 words.       │
│                             │
└─────────────────────────────┘
```

- **Headline:** `Reading your voice…`
- Four stages tick in, mapped to the *real* pipeline (transcription → analysis → subscores → persist), each with `Haptics.light()`. Minimum 600ms per row even when fast — comprehension needs rhythm; cap total theater at ~4s beyond real work.
- One true artifact appears as soon as transcription lands: `You said 112 words.` — proof it genuinely listened (labor illusion needs one verifiable fact to become trust; Life Reset's checklist pattern, upgraded with real data).
- **Why it exists:** first-run Whisper latency is unavoidable; undressed, it's the moment users think the app broke. Dressed in real stages it *builds* the reveal. **If removed:** a spinner at the emotional peak — abandonment risk exactly when we're one screen from activation.

---

### Screen 6d — The Reveal (starting line, not report card)

**Purpose:** pay everything off; convert score → excitement → tomorrow. **Primary emotion:** pride + curiosity.

```
┌─────────────────────────────┐
│        ✦ tiny confetti ✦    │
│                             │
│   Your starting line        │
│        ┌──────┐             │
│        │  62  │  ← ring     │
│        └──────┘   sweeps up │
│                             │
│   [Pace 138 wpm] [Fillers 4]│
│                             │
│  ╭─────────────────────╮    │
│  │ Steady pace, Vansh.  │   │
│  │ We'll work on pauses │   │
│  │ first — that's your  │   │
│  │ fastest win.         │   │
│  ╰─────────────────────╯    │
│                             │
│   Every session from now    │
│   on is compared to this.   │
│   🔥 Day 1                  │
│                             │
│  ┌───────────────────────┐  │
│  │  See my full breakdown│  │
│  └───────────────────────┘  │
│   (no secondary action)     │
└─────────────────────────────┘
```

- **Headline:** `Your starting line` — never "Your score."
- Ring sweeps 0 → N over 1.2s with ascending haptic ticks; restrained confetti (existing `ConfettiView`, low density); score uses `AppColors.scoreColor` ramp.
- Two metric chips max (pace + fillers — the two most self-explanatory). The other seven wait in the detail view; the reveal is a headline, not the article.
- **One coaching insight** in the coach's bubble voice, from `CoachingTipService`, name included: `Steady pace, Vansh. We'll work on pauses first — that's your fastest win.` This single line *is* the activation promise kept — the app heard you, and it has a plan for you.
- **Baseline framing line:** `Every session from now on is compared to this.` + `🔥 Day 1` streak spark (investment loop opens).
- **CTA:** `See my full breakdown` → `RecordingDetailView` (natural teach-the-app moment). **Shipped with no secondary action** — the drafted `Take me home` was cut, since the breakdown is where a first score becomes information. Onboarding is complete either way and `FirstRecordingSetupSheet` fires on Today afterwards exactly as it does now.
- **Low-score guard:** if overall < 40, suppress the number as the hero — show the two metric chips + `You showed up — that's the hard part. Plenty of headroom, and headroom is the fun part.` The number still exists in detail view. First-session churn is not worth numeric purity.
- **Why it exists:** this is the moment the activation metric measures — completion + understanding + excitement in one screen. **If removed:** the baseline ends in the generic detail view: information present, *meaning* absent, celebration missing.

---

## 7. Motion Ideas (system-wide)

All within the existing `AppMotion.settle` / `.snap` vocabulary; everything herein goes still under Reduce Motion.

- **Orb as coach:** one continuous character across the flow — breathes on the cover, tilts on questions, ripples with mic input on the sound check, orbits during analysis, flares at the reveal. Continuity of a single animated element is what makes a flow feel inhabited (Duolingo's owl, Headspace's blob) without building a mascot.
- **Answer echo:** tapped goal/level card lifts, others dim to 40%, payoff line slides up beneath — cause and effect in one glance.
- **Chip pops:** metric chips in 6a and 6d scale in 0.8→1.0 with 60ms stagger + `Haptics.light()` each.
- **Countdown in the button:** 3-2-1 rendered inside the record button's ring (ring depletes per second) — the screen never changes, so nothing "disappears."
- **The 30s tick:** when elapsed crosses it, tick flips to a checkmark with a spring + soft haptic — a finish line crossed mid-run.
- **Analyzing rows:** each row's ◌ spins subtly, then stamps to ✓ with a 1.1→1.0 settle.
- **Reveal ring:** sweep with 5 ascending haptic ticks; chips and coach bubble follow at 0.3s intervals; confetti burst ≤1.5s.
- **Haptic map:** selection = choice taps · light = chips/ticks/rows · success = mic heard, baseline saved · medium = record start. Never haptic-per-second during recording — the take must feel *calm*.

## 8. Edge Cases

- **Mic permission denied:** sound check becomes `Big Talk can't hear you yet` + `Open Settings` deep link + quiet `Explore the app first` → TodayView with the baseline hero card (see §9) as the persistent way back. Never a dead end, never a nag loop.
- **Silence / gibberish gate trips:** never show the gated score. Analyzing resolves to: `We couldn't hear enough to read your voice. Mic close? Room quiet? Let's take it again.` → one tap back to 6b ready state, same prompt. (Oura's quality-coaching-without-blame, applied at the highest-stakes moment.)
- **Take under 10s:** accept the audio, coach once: `That was quick — a baseline needs about 30 seconds. Give it one more go?` `Try again` / `Keep it anyway`. Autonomy preserved; both routes valid.
- **Interruption (call, backgrounding):** existing scene-phase teardown pattern applies; on return: `We saved nothing — clean slate.` → ready state. Framed as a feature, not an error.
- **Whisper still loading at analysis time:** the analyzing screen simply holds stage 1 longer (`Transcribing your words…`); preload began at the cover, so this is rare. If load *fails* → `DictationService` fallback, invisible to the user (existing backend-order logic).
- **Retry spiral (3+ restarts):** after the third `Start over`: `Honestly — the messy version is the most useful baseline. Imperfect is perfect here.` Reassure, never block.
- **No LLM on device:** 6d insight falls back to rule-based `CoachingTipService` output — flow identical; never mention what's missing. Model download stays in `FirstRecordingSetupSheet`.
- **Re-onboarding with existing recordings:** skip beat 6 entirely; existing `hasShownFirstRecordingSetup` suppression logic already covers the sheet.
- **Force-quit mid-flow:** existing UserDefaults resume, with one change — resuming into beat 6 always lands on 6a (briefing), never cold onto the recorder.

## 9. Empty States

- **Baseline skipped → TodayView hero card** (replaces stats rings until done): `Your starting line is waiting · One 30-second recording unlocks your scores, streaks, and coaching. → Set my baseline` — routes into 6a. The activation moment stays reachable forever; the empty state *is* the funnel re-entry. Still unbuilt — tracked in `ONBOARDING_VISION.md` → "Known ceilings".
- **History before any recording:** `Your story starts with one recording.` + the same CTA. Charts/streak surfaces: show meter tracks with `scoreEmpty`, never bare zeros ("0" reads as failure; an unlit meter reads as *potential*).
- **Sound check hearing nothing for 10s:** `Not hearing you yet. Closer to the mic?` under the flat waveform.

## 10. Accessibility

- **VoiceOver order on 6b:** prompt text → starter chips → record button → swap. During recording, announcements via `AXAnnouncement` only at meaningful moments (record started · 30s reached · stopped) — never per-second.
- **The 30s tick** posts `"30 seconds — that's enough for a baseline"` as an announcement; encouragement lines are polite (non-interrupting) announcements.
- **Reduce Motion:** orb static with opacity pulse only; cascade bubbles appear without offset; ring sets instantly with the number counting via opacity crossfade; confetti off. (Existing `.motion()` wrapper handles most of this.)
- **Dynamic Type:** the script/prompt card is *read aloud from* — it must scale to accessibility sizes without truncation; card scrolls internally rather than clipping. Starter chips wrap via `FlowLayout`.
- **Haptics always paired with a visual** (deaf-blind users get the visual; VoiceOver users get the announcement; nobody depends on the buzz).
- **Auto-advance (goal/level):** dropped entirely rather than special-cased for VoiceOver. Every user gets the explicit Continue, so there is one behaviour to reason about instead of two.
- **Color:** score communicated by number + verdict word (`scoreVerdict`), never color alone. All copy on glass meets 4.5:1.
- **The countdown-in-button** also renders numerals at the screen's center-safe area for low-vision users; `Haptics` tick per second.

## 11. Success Metrics

Instrument via existing `AnalyticsService.onboardingStep` (names stay stable per its own doc), adding: `baseline_briefing`, `baseline_ready`, `baseline_recording`, `baseline_analyzing`, `baseline_reveal`, with actions `continue / skip / retry / swap_prompt / abandon`. (`script_mode` was dropped with script mode.)

- **Funnel:** completion rate per beat; overall cover→reveal. Target: >70% of installs reach the reveal (current equivalent unknown — instrument first).
- **Time-to-baseline:** median install → reveal. Target < 4 minutes.
- **Baseline quality:** % of first takes ≥30s; retry count distribution; % hitting silence/gibberish coaching; swap-prompt share (if high, the default prompt is too scary — iterate the prompt).
- **Comprehension proxy:** % tapping `See my full breakdown` (curiosity = understood there's more).
- **Momentum:** % recording a second session within 48h (the single best predictor of retention); D1/D7 retention vs. pre-redesign cohort.
- **Guardrails:** mic-permission grant rate must not drop (moving it later can only help); `FirstRecordingSetupSheet` engagement unchanged.

## 12. Activation Metric

> **A new user is *activated* when, in their first session, they (1) complete a baseline recording ≥30 seconds, (2) view the reveal screen, and (3) take one forward action from it (`See my full breakdown`, or any tap on Today).**

One number to report: **install → activated %**. Condition (3) is the "excited, not just finished" proxy — a user who force-quits on the reveal saw a score but didn't buy the story. Leading indicator: % of activated users who return within 48h.

## 13. Rationale Index

Every decision above traces to one of four grounds — the per-screen "Why this exists / if removed" entries carry the specifics. The load-bearing ones:

| Decision | Grounding |
|---|---|
| Baseline inside onboarding, not after | Duolingo (lesson-in-onboarding); user feedback ("should be the first guided experience"); the handoff is where the current design dies |
| User presses record; countdown in-button | Perceived control is the primary lever on state anxiety; fixes F2/F3 with one mechanism |
| Prompt pinned during take | Meta AI / Speechify / Character AI convergent pattern; verbatim user feedback |
| ~~Script fallback at arm's reach~~ (cut) | Drafted from "I didn't know if there was a script" + Speechify's zero-composition path. Cut because a read baseline trains the wrong muscle; starter chips carry the anti-freeze job |
| Count up + "30s = enough" tick | Goal-gradient effect (progress motivates; deadlines threaten); M3 fix; substance curve genuinely accepts ~30s |
| Cut How-It-Works / What's-Inside / Vocab | "Too much reading…"; "never homework"; Duolingo/Headspace delay everything; inventory ≠ comprehension |
| Payoff line per answer (auto-advance later dropped) | Duolingo echo pattern; fixes I2 (inputs with no visible consequence) |
| Analyzing as staged theater with one real fact | Labor illusion (Life Reset) + verifiable artifact ("You said 112 words") converts wait into trust |
| "Starting line," never "score"; low-score guard | Oura baseline framing; E2 (first-number churn risk); growth-mindset framing of an initial measurement |
| Defer calibration / AI / reminders (unchanged) | Headspace post-session asks; the current build already got this right — keep it |

---

## Appendix — Implementation Mapping (for build planning)

The redesign itself needed no schema changes. Multi-select goals later added one additive field, `UserSettings.onboardingGoalsRaw`, with an empty default so lightweight migration and CloudKit evolution stay safe.

| New piece | Built from |
|---|---|
| Cover / Name / Goal / Level | Existing steps, copy changes; `OnboardingPage`, `OnboardingChoiceCard`, tick meter as-is. Goal became multi-select feeding `PromptMix`; both question steps keep a permanent Continue |
| Sound check | Existing `OnboardingMicStep` + waveform + `hasHeardVoice`, retitled/recopied |
| 6a briefing cascade | New lightweight view; `onboardingReveal` stagger + `GlassCard` bubbles; orb = existing `OnboardingOrb` |
| 6b guided recorder | New onboarding-owned view wrapping `AudioService` (the mic step already records); prompt card = `GlassCard`; chips = `FlowLayout`; **not** the generic `RecordingView` |
| ~~Script mode~~ | Cut before ship; Read-Aloud practice covers read speech from the Library |
| 6c analyzing | `RecordingProcessingCoordinator` stages surfaced; `AnalyzingView` as base |
| 6d reveal | `RingStatsView` ring + `ConfettiView` + `CoachingTipService`; routes to `RecordingDetailView` |
| Today hero card (empty state) | New card on `TodayView`, shown until first recording exists |
| Removals | `whatsInside`, `vocab` steps; `launchFirstRecording` toggle + `ContentView` auto-countdown path (`ContentView.swift:360-366`) |

Resume-key bump to v7 (steps changed — same reason v6 exists). Bumped again to v8 when the goal draft became a list.
