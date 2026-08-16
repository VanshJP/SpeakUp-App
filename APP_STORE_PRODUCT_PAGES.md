# Big Talk — custom product pages

Four audience-specific App Store pages, on top of the default listing in
`APP_STORE_LISTING.md`. The default page has to speak to everyone who searches
"public speaking"; these four each speak to one person arriving from one place,
which is the whole reason conversion improves.

Read `APP_STORE_LISTING.md` first — the text fields, capture rules, brand
colour, and the "do not claim" list all apply here unchanged.

## What a custom product page can and cannot change

Verified against Apple's product page documentation, current as of the last
edit to this file. Getting this wrong wastes a review cycle.

| Element | Per page? | Limit |
|---------|-----------|-------|
| Screenshots | Yes | 10 per display size |
| App previews | Yes | 3 |
| Promotional text | Yes | 170 characters, editable without a build |
| Keyword assignment | Yes | **Only terms already in the app's keyword field** |
| Deep link | Yes | iOS 18+ |
| Name, subtitle, icon, description, price, rating, privacy labels | **No** | Shared with the default page |

Up to 70 pages per app. Each gets a URL of the form
`https://apps.apple.com/app/big-talk/id<APP_ID>?ppid=<UUID>`, and each is
submitted for review (24-48 hours) before its URL goes live.

Two consequences worth planning around:

- **Keywords are drawn from one shared field.** A page cannot invent a term. The
  keyword field was changed to include `interview` for exactly this reason; if a
  future page needs a term, it has to earn a slot in that 100-character field
  first. `public speaking` moved into the app name, which is *not* assignable
  here — the three pages that used it were reassigned rather than left broken.
- **The subtitle is shared.** Every page below carries "Practice speeches &
  interviews" above its own screenshots, so no page's first slide should
  repeat that idea — it is already on screen.

## Attribution is already wired

`AttributionStore` reads `page`, `ppid`, and `cpp` from an incoming link and
stores whichever it finds as the campaign page, so a first open that arrived
through one of these pages is distinguishable from organic in the local event
log without any further work. Confirm on device after each page goes live: open
the page URL, install, then check `Settings → Usage Diagnostics` for the
`first_open` event carrying the page id.

Where a page's traffic comes from a link you control (a newsletter, a partner
site, a bio link), append `source` and `campaign` too:

```
https://apps.apple.com/app/big-talk/id<APP_ID>?ppid=<UUID>&source=newsletter&campaign=launch
```

## Slide economics

Sixteen slide positions across four pages, but only nine distinct captures.
Three slides from the default set are reused verbatim, and the rest are new.
Capture the default six first; these pages are largely a re-cut of that work.

Reused from `APP_STORE_LISTING.md` section 5:

- **D2** — `CATCH` / `FILLERS AS YOU SAY THEM`, `RecordingView` mid-recording
- **D5** — `SEE` / `HOW FAR YOU HAVE COME`, `BeforeAfterReplayView`
- **D6** — `KEEP` / `EVERY WORD ON DEVICE`, `Settings → Usage Diagnostics`

New captures needed for these pages (`P1`-`P6`):

| ID | Screen | Required state |
|----|--------|----------------|
| `P1` | `AllPromptsView`, Interview Prep category selected | List full and scrolled slightly, so it reads as a deep library rather than a starter set. |
| `P2` | `RecordingDetailView`, Breakdown tab, session linked to an Interview Prep prompt | The prompt text visible above the score. This is the slide that proves the score is about *this answer*, not speech in the abstract. |
| `P3` | `RecordingDetailView`, Transcript tab | Fillers and hedges marked inline. Needs a transcript with 4-6 of them — a clean transcript shows nothing. |
| `P4` | `WPMChartView` in `RecordingDetailView` | A 60s+ session with visible pace variation, so the chart has shape. A flat line sells nothing. |
| `P5` | `StoryDetailView` | A real script with 3+ linked sessions and populated tags. Content differs per page — see each page below. |
| `P6` | `WarmUpExerciseView`, breathing exercise mid-cycle | Animation caught at expansion, timer running. |

`P5` is captured three times with different script content (interview answer,
talk script, pitch, video script). Same screen, different story — write the
stories before the capture session.

---

## Page 1 — Interview prep

**Internal name:** `bigtalk-interview`
**Traffic:** Apple Search Ads on interview terms, career and job-search
newsletters, university career-services partnerships.
**Keyword assignment:** `interview`, `speech`, `coach`
**Deep link:** `speakup://record` — a page that promises rehearsal should open
on the recording screen, not the home tab.

**Promotional text (168 characters):**

```
Practice the questions you will actually be asked, out loud. Big Talk scores your pace, your fillers, and whether you answered the question. Nothing leaves your iPhone.
```

| # | Verb | Descriptor | Capture |
|---|------|------------|---------|
| 1 | `REHEARSE` | `REAL INTERVIEW QUESTIONS` | `P1` |
| 2 | `HEAR` | `HOW YOUR ANSWER LANDED` | `P2` |
| 3 | `CUT` | `THE UMS AND YOU KNOWS` | `P3` |
| 4 | `SCRIPT` | `YOUR STAR ANSWERS` | `P5`, story = a STAR-format answer to a common behavioural question |
| 5 | `SEE` | `HOW FAR YOU HAVE COME` | `D5` |

Slide 2 is the one doing the work. Every competitor can show a score; showing
the score underneath the question that was asked is what says this is interview
practice rather than a generic voice meter. It is also honest — the relevance
sub-score genuinely measures whether the answer stayed on the question.

---

## Page 2 — Presentations

**Internal name:** `bigtalk-presentation`
**Traffic:** Apple Search Ads on presentation and Toastmasters terms, workplace
L&D newsletters, conference speaker packs.
**Keyword assignment:** `presentation`, `toastmaster`, `speech`
**Deep link:** `speakup://story` — this audience arrives with a talk already
written, so the Library is the right landing.

**Promotional text (157 characters):**

```
Rehearse the talk, not a generic prompt. Paste your script and get pace charted second by second, pause quality, and every filler marked. All on your iPhone.
```

| # | Verb | Descriptor | Capture |
|---|------|------------|---------|
| 1 | `REHEARSE` | `YOUR ACTUAL TALK` | `P5`, story = a conference talk script with linked sessions |
| 2 | `PACE` | `A ROOM THAT IS LISTENING` | `P4` |
| 3 | `LAND` | `YOUR PAUSES ON PURPOSE` | `P2`, scrolled to the Pause Quality tile with its explainer open |
| 4 | `WARM UP` | `BEFORE YOU GO ON` | `P6` |
| 5 | `SEE` | `HOW FAR YOU HAVE COME` | `D5` |

`WARM UP` is two words and will auto-size smaller in `compose.py`. Check it
against the other four at thumbnail size before approving the set; if it reads
noticeably lighter, use `PREP` instead.

---

## Page 3 — Pitching

**Internal name:** `bigtalk-pitch`
**Traffic:** Founder and startup newsletters, accelerator resource lists, sales
enablement communities.
**Keyword assignment:** `speech`, `pitch`, `articulation`
**Deep link:** `speakup://record`

**Promotional text (158 characters):**

```
Sixty seconds, said well. Big Talk scores your pace, your hedging, and how much of your pitch you actually delivered. On device, no account, nothing uploaded.
```

| # | Verb | Descriptor | Capture |
|---|------|------------|---------|
| 1 | `TIGHTEN` | `YOUR SIXTY SECONDS` | `DrillSessionView`, Impromptu Sprint, timer under 0:20 remaining |
| 2 | `DROP` | `THE HEDGING` | `P3` — the transcript needs visible hedges ("I think maybe", "sort of"), not just fillers |
| 3 | `REHEARSE` | `YOUR OWN PITCH` | `P5`, story = a 60-second company pitch |
| 4 | `SOUND` | `LIKE YOU MEAN IT` | `P2`, scrolled to the Delivery and Vocal Variety sub-scores |
| 5 | `SEE` | `HOW FAR YOU HAVE COME` | `D5` |

Slide 1 needs one extra capture beyond the `P` list — the Impromptu Sprint
drill screen. It is the only slide in any of the four pages that shows a clock
running out, which is the emotional truth of pitching and worth the extra
capture.

---

## Page 4 — Creators

**Internal name:** `bigtalk-creator`
**Traffic:** Creator-economy newsletters, podcast and YouTube gear roundups,
partnerships with editing-tool audiences.
**Keyword assignment:** `voice`, `filler`, `pronunciation`
**Deep link:** `speakup://story/new` — this audience has a script to paste.

**Promotional text (153 characters):**

```
Rehearse the take before you hit record. The filler counter runs live, your script gets scored against what you wrote, and none of it leaves your iPhone.
```

| # | Verb | Descriptor | Capture |
|---|------|------------|---------|
| 1 | `NAIL` | `THE TAKE IN ONE GO` | `D2` |
| 2 | `SCRIPT` | `IT THEN SPEAK IT` | `P5`, story = a video script with linked sessions |
| 3 | `CUT` | `FILLERS BEFORE THE EDIT` | `P3` |
| 4 | `KEEP` | `EVERY WORD ON DEVICE` | `D6` |
| 5 | `SEE` | `HOW FAR YOU HAVE COME` | `D5` |

This is the one page where the privacy slide is a selling point rather than
reassurance: unreleased scripts are the thing this audience most does not want
sitting on someone else's server. It sits at position 4 rather than last so it
lands before the swipe ends.

---

## Building the pages

Same pipeline and same constraints as the default set — `compose.py` needs a
Mac with SF Pro Display Black, the crop step needs `sips`, and the enhancement
pass needs the Gemini MCP server. Two things carry across from the default set
and must not be re-decided per page:

- **Background stays `#0FB3AE` on all four pages.** A visitor may see two of
  these pages, and the App Store shows the shared name and icon above both. A
  page in a different colour reads as a different app.
- **The approved slide 1 of the default set stays the style template** for every
  slide on every page, not just the six it was made for. The skill's
  subsequent-screenshot prompt takes the style template as its second image;
  keep passing the same file.

Capture order that minimises simulator setup: seed the four stories in one
sitting, run enough real sessions against them to populate history and the
before/after trend, then take `P1`-`P6` and the drill screen in one pass.

## After the pages are live

- [ ] Record each `ppid` URL next to its internal name, in the release notes for
      the version that shipped it.
- [ ] Verify each URL opens the intended page on a device, not the default one.
- [ ] Confirm the deep link lands on the right screen post-install.
- [ ] Check `first_open` in `Settings → Usage Diagnostics` carries the page id.
- [ ] Compare per-page conversion in App Analytics → Custom Product Pages after
      enough traffic to be worth reading. A page that does not beat the default
      page is costing a review cycle to maintain — retire it rather than keeping
      it for completeness.
