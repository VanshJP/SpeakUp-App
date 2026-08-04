# Big Talk — Release Checklist

Everything below is work the code cannot do for itself: App Store Connect
configuration, a website, a device pass, and the judgement calls the launch
plan leaves open. Work top to bottom; each section blocks the one after it.

## 1. Decisions that must be settled before submission

These change shipped copy and shipped behaviour, so settle them first.

- [ ] **Product name.** The bundle display name is `Big Talk`; the code, target,
      and bundle id still say `SpeakUp` (`com.vansh.SpeakUpMore`). The App Store
      listing must match the display name, not the target name.
- [ ] **Free/paid boundary.** Shipping default is `FreeTierPolicy.default` in
      `Monetization.swift`: three intro analyses, then three per rolling 30
      days, with curriculum, journal export, and iCloud sync owned. Progress
      cards are deliberately *not* gated — the share loop has to run on free
      accounts. Change the policy, not the call sites, if this moves.
- [ ] **Price and founding-offer framing.** `FoundingOffer.deadline` ships
      `nil`, which shows no urgency copy at all. If a founding price is used,
      set the deadline and raise the App Store Connect price on the same day —
      the app never sets a price, it only describes one. Note that
      `FoundingOffer.standardDisplayPrice` is a US-storefront literal, because
      StoreKit cannot price a product it is not selling yet; leave the deadline
      unset while shipping internationally, or the "after" price shows in the
      wrong currency.
- [ ] **Analytics transport.** `LocalAnalyticsSink` keeps events on device and
      uploads nothing. If a hosted sink is adopted, it is a
      `AnalyticsService.use(sink:)` swap plus a privacy-label update, not an
      instrumentation project.

## 2. App Store Connect

- [ ] Create the non-consumable IAP with product id
      `com.vansh.SpeakUpMore.lifetime`. It must match `LifetimeProduct.identifier`
      and `Products.storekit` exactly, or the paywall shows no price.
- [ ] Set the localized display name and description for the IAP, and upload
      the required review screenshot of the paywall.
- [ ] Submit the IAP for review *with* the build. A first IAP reviewed
      separately can hold the whole release.
- [ ] Privacy nutrition labels: with the shipped local sink, the answer is no
      data collected and no tracking. Re-answer if a hosted sink is adopted.
- [ ] Privacy policy URL (required) and, because the app sells a non-consumable,
      a terms/EULA link.
- [ ] App Review notes: state that transcription and scoring run on device,
      that the free tier is three analyses then three per month, that no account
      is required, and how a reviewer reaches the paywall (finish one analysis,
      then open a gated feature).
- [ ] Generate offer codes if the launch plan uses them — the redemption sheet
      is already wired into `PaywallView`.

## 3. Website and in-app links

`SupportLinks` reads three keys from `SpeakUp/Info.plist` and hides any row
whose value is missing or not `https://`. Empty values ship a build with no
outbound legal links, which App Review will notice.

- [ ] `BTPrivacyPolicyURL`
- [ ] `BTTermsURL`
- [ ] `BTSupportURL`
- [ ] Confirm `SupportLinks.feedbackEmail` still reaches a monitored inbox.

### Universal links for campaign traffic

`speakup://` links work today. Web links do not, because a domain cannot be
claimed before it is owned — the `associated-domains` entitlement is
deliberately *not* checked in, since adding it without the matching capability
on the App ID fails code signing on the next build. The routing code ships and
goes live the moment these four steps are done, in this order:

- [ ] Set `BT_UNIVERSAL_LINK_DOMAIN` in `Config/SharedVersion.xcconfig` to the
      bare host (`bigtalk.app`, no scheme, no trailing slash). It feeds
      `BTUniversalLinkDomain` in Info.plist, which `UniversalLink` reads.
- [ ] Enable the **Associated Domains** capability on the App ID in the
      developer portal and regenerate the profile.
- [ ] Add `com.apple.developer.associated-domains` to
      `SpeakUp/SpeakUp.entitlements` with the single entry
      `applinks:<the same host>`. It must match the xcconfig value exactly; a
      mismatch fails silently, with links opening Safari instead of the app.
- [ ] Host `Config/apple-app-site-association` at
      `https://<host>/.well-known/apple-app-site-association`, served as
      `application/json` with no `.json` extension and no redirect. Verify the
      `appIDs` entry still matches `<TEAM_ID>.<bundle id>`.

Then confirm on a device that a link pasted into Notes opens the app, that
`https://<host>/record?prompt=<id>` starts a session, and that
`?source=…&campaign=…` shows up on the `first_open` event in Usage Diagnostics.

## 4. Build configuration to verify in Xcode

- [ ] Add the **In-App Purchase** capability to the `SpeakUp` target if it is
      not already on the provisioning profile.
- [ ] Confirm the App Group `group.com.speakup.shared` is enabled on both the
      app and the widget extension — entitlement mirroring and widget data both
      depend on it.
- [ ] Bump `APP_MARKETING_VERSION` and `APP_BUILD_NUMBER` in
      `Config/SharedVersion.xcconfig`.
- [ ] Confirm the shared `SpeakUp` scheme is used for archiving, and that its
      StoreKit configuration reference is cleared for release builds (it is a
      Debug/run-time convenience only).

## 5. Test pass before archiving

The agent working on this repo does not build or run the app; these are the
developer's loops.

```bash
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme SpeakUp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Then, on a device:

- [ ] **First run.** Fresh install, complete onboarding, record, and confirm a
      score appears without a calibration, model-download, or reminder step in
      front of it.
- [ ] **Allowance.** Burn the three intro analyses and confirm the fourth
      recording is saved and shows "Saved, not scored yet" rather than an error.
- [ ] **Purchase.** Buy Lifetime in the sandbox, confirm the deferred recording
      scores automatically and every gated surface opens.
- [ ] **Restore.** Delete and reinstall, tap Restore, confirm entitlement
      returns with no account and no re-purchase.
- [ ] **Refund path.** Use StoreKit's transaction manager to revoke the
      purchase and confirm the app returns to the free tier without crashing.
- [ ] **Share privacy.** Share a score card from a prompt-backed session and
      confirm the default card carries no prompt text; share a Then-vs-Now card
      and confirm it carries no transcript, prompt, or story title.
- [ ] **Offline.** Airplane mode: recording, scoring, and playback all work; the
      paywall degrades to the fallback price rather than an empty sheet.
- [ ] **Widgets.** Add each widget and confirm it hydrates from the App Group.

## 6. Launch measurement

`Settings → Usage Diagnostics` renders the scorecard from the local event log
and exports the raw JSON.

- [ ] Confirm `first_open` carries the campaign source when the build is opened
      through a campaign deep link (`speakup://open?source=…&campaign=…`).
- [ ] Confirm `activated` fires on the first completed analysis, and that its
      time-to-value bucket is the one the launch gate is read against.
- [ ] Collect exports from beta devices before stage gate decisions — a single
      device's activation rate is 0 or 1 and means nothing on its own.
