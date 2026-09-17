# Retention — notifications, streak protection, milestones

Owns everything that brings a user back: the notification ladder, streak freezes, and milestone moments. Sibling docs: [settings.md](./settings.md) (the consent screen), [achievements-goals.md](./achievements-goals.md) (in-app celebration), [widgets.md](./widgets.md) (streak surface).

## Key files

| Path | Role |
|------|------|
| `Services/RetentionNotificationPlanner.swift` | Pure. Snapshot → `[PlannedNotification]`. All copy lives here. |
| `Services/PracticeRhythm.swift` | Pure. Practice timestamps → the hour the daily reminder should fire. |
| `Services/RetentionScheduler.swift` | The single entry point. State → plan → scheduled. MainActor, touches `ModelContext`. |
| `Services/NotificationService.swift` | `UNUserNotificationCenter` only. No product decisions. |
| `Models/StreakProtection.swift` | Pure freeze math. |
| `Extensions/Date+Helpers.swift` | `calculateStreak(from:frozenDays:now:)` |
| `Views/Settings/ReminderSettingsView.swift` | Consent + per-class toggles. |

## Invariants

1. **`dailyReminderEnabled` is the consent for the entire channel.** Off means nothing ships — no streak rescue, no comeback, no milestone. Enforced twice on purpose: `RetentionNotificationPlanner.plan` returns `[]`, and `RetentionScheduler.refresh` bails before it builds a snapshot. Do not add a notification class that reads around it.
2. **One entry point.** Every caller goes through `RetentionScheduler.refresh`. The four call sites (foreground in `SpeakUpApp`, take saved in `RecordingViewModel+RecordingControl`, `SettingsViewModel.saveSettings`, `FirstRecordingSetupSheet`) pass a context and nothing else. The previous build scheduled from each site independently and left orphaned identifiers behind.
3. **The daily reminder time is derived, not asked for.** `PracticeRhythm` takes the recency-weighted circular mean of practice times and subtracts a 30-minute lead; `RetentionScheduler.refresh` writes the result to `dailyReminderHour`/`Minute` on every refresh. Nothing asks the user for a time during the first run — `FirstRecordingSetupSheet` is one consent toggle and no picker. Settings → Reminders shows the learned time as a **readout**, and "Set the time myself" clears `adaptiveReminderEnabled`, after which the scheduler never touches the stored hour again. `SettingsViewModel.saveSettings` only writes hour/minute while adaptive is off; otherwise an unrelated toggle would drag the reminder back to whatever that screen last loaded.
4. **Averaging times of day is circular, never arithmetic.** 23:50 and 00:10 are twenty minutes apart; their arithmetic mean is noon. `PracticeRhythm` averages unit vectors on the 24-hour circle, which is what keeps a late-night practitioner's reminder at night. `PracticeRhythmTests.timesAverageAroundMidnightNotThroughNoon` fails the build on regression.
5. **A scattered history moves nothing.** At or above `minimumSessions` (4) the mean resultant length must clear `minimumConcentration` (0.55) or `suggestion` returns nil and the stored time stands — moving a reminder daily for someone with no settled rhythm is churn wearing personalization's clothes. Under that floor there is nothing to be concentrated about, so a single real session is allowed to seed the slot; a default nobody chose is the thing being replaced. With **no** sessions at all `suggestion` returns nil and the stored time stands — so the one path that would otherwise land on the 9:00 column default (turning reminders on in Settings before ever recording) seeds from the moment of consent instead, in `SettingsViewModel.saveSettings`, fed through `PracticeRhythm` so the lead keeps one definition. `FirstRecordingSetupSheet` needs no seed: a take already exists by the time it appears.
6. **Three notifications a day is the ceiling**, and only for a user with a 7-day-plus streak who has not practised. Typical day is one or two. Raising this needs a real reason — see the Duolingo note below.
7. **Copy names the stake and does not hedge.** No "if you want to", "no pressure", "skip today". `RetentionTests.copyNamesTheStakeAndNeverHedges` fails the build on regression.
8. **A freeze holds the chain; it never extends it.** The streak number stays a count of days the user actually spoke. `calculateStreak` only increments on practice days.
9. **A freeze covers exactly one day.** Two days gone is a comeback, not a slip.
10. **Freeze balance is derived, never stored.** `streakFrozenDays` is the only new column; the balance is `practiceDays / 5 - frozenDays.count`, capped at 2. Recomputation converges instead of drifting.
11. **Banked freezes survive a settings reset.** They are earned practice, not a preference.
12. **Practising clears the rescue immediately** (`afterPractice: true`), so a 19:00 take never produces a 20:30 "your streak ends tonight".
13. **Evening slots are pinned to today.** `NotificationService.resolve` skips an `onceAt` whose time has already passed rather than letting a non-repeating calendar trigger roll it to tomorrow — otherwise "your 10-day streak ends at midnight" arrives the evening *after* it ended, and the notification is a lie by the time it lands.
14. **The comeback ladder stops at day 7.** Past that it is noise, and noise gets the app muted — which costs the channel permanently.

## The ladder

| Class | ID | When | Toggle |
|-------|----|------|--------|
| Daily reminder | `daily_reminder` | learned time, repeating | `dailyReminderEnabled` |
| Streak rescue | `streak_at_risk` | 20:30, streak ≥ 1, not practised | `streakRemindersEnabled` |
| Last call | `streak_last_call` | 21:45, streak ≥ 7, not practised | `streakRemindersEnabled` |
| Comeback | `comeback_d2/d4/d7` | 2, 4, 7 days after last take | `comebackRemindersEnabled` |
| Milestone | `streak_milestone` | immediate, at 3/7/14/30/50/100/200/365 | `milestoneNotificationsEnabled` |
| Freeze used | `streak_freeze_used` | immediate, when a freeze is spent | `streakRemindersEnabled` |

Daily reminder copy is streak-aware and rescheduled on every foreground, so the number it quotes is never more than one app-open stale. The **slot** is recomputed on the same pass, which is how a user who moves from mornings to evenings is followed within a couple of weeks (`halfLifeDays` = 14).

## Why it is shaped this way

From what Duolingo's retention team has published, which is narrower than the folklore:

- Their team could tune **timing, template and copy** freely but could not raise notification **quantity** without CEO sign-off. The DAU wins came from relevance, not volume.
- The practice reminder lands **~23.5h after the last session**, converging on the time that person actually practises. Big Talk converges on the same place from the other direction: it averages the times rather than chaining off the last one, and lands 30 minutes *ahead* of the usual time rather than a day after the last take. Chaining off one session lets a single 2 a.m. outlier drag the schedule with it; the weighted mean does not.
- **Streak freezes are the forgiveness mechanic**, and forgiveness is what their team credits for the long-run retention step change — not pressure. A missed Tuesday resetting a 40-day habit to zero is what makes people quit for good, because the thing they were protecting is already gone.
- A **7-day streak** is the documented inflection point for return rates, which is why the 3–6 day copy counts down to it and why last call is gated there.

## Schema

Additive only (`UserSettings`): `streakRemindersEnabled`, `comebackRemindersEnabled`, `milestoneNotificationsEnabled`, `adaptiveReminderEnabled` (all default `true`), `streakFrozenDays: [Date]`, `lastMilestoneNotified: Int`.

Never `#Predicate` on `streakFrozenDays` — Codable blob column (gotchas §2).

## Entitlement gap

The streak rescue is the one notification that genuinely warrants `.timeSensitive`, but that needs `com.apple.developer.usernotifications.time-sensitive` on the provisioning profile. Until the capability is enabled in the developer portal, `NotificationService` sets `.active` plus a high `relevanceScore`, which still orders the iOS summary. Enabling it is a one-line change in `NotificationService.schedule` plus the entitlements file.
