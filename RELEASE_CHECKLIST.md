# Big Talk — Release Checklist

Everything below is work the code cannot do for itself: App Store Connect
configuration, a website, a device pass, and the judgement calls the launch
plan leaves open. Work top to bottom; each section blocks the one after it.

## 1. Decisions that must be settled before submission

These change shipped copy and shipped behaviour, so settle them first.

- [ ] **Product name.** The bundle display name is `Big Talk`; the code, target,
      and bundle id still say `SpeakUp` (`com.vansh.SpeakUpMore`). The App Store
      listing must match the display name, not the target name.
- [ ] **Free/paid boundary.** Two policies in `Monetization.swift`:
      `FreeTierPolicy.trial` for the first 14 days (everything open except
      iCloud sync) and `.expired` after (three analyses per rolling 30 days,
      with curriculum, journal export, and iCloud sync owned). The 14 days run
      from the first *completed* analysis — `AllowanceGate.consume` starts the
      clock, `EntitlementStore` holds it. Progress cards are deliberately *not*
      gated in either policy — the share loop has to run on free accounts.
      Change the policy, not the call sites, if this moves.
- [ ] **Price and founding-offer framing.** `FoundingOffer.deadline` ships
      `nil`, which shows no urgency copy at all. If a founding price is used,
      set the deadline and raise the App Store Connect price on the same day —
      the app never sets a price, it only describes one.
      `FoundingOffer.standardDisplayPrice` is a US-storefront literal, because
      StoreKit cannot price a product it is not selling yet. The banner now
      drops the "…after" comparison on any storefront not selling in USD, so
      setting a deadline is safe internationally — non-US buyers see "Founding
      price" with no comparison. Update the literal if the US tier changes.
- [ ] **Analytics transport.** `LocalAnalyticsSink` keeps events on device and
      uploads nothing. If a hosted sink is adopted, it is a
      `AnalyticsService.use(sink:)` swap plus a privacy-label update, not an
      instrumentation project.

## 2. App Store Connect

- [ ] **Accept the Paid Apps agreement** (Business → Agreements, Tax, and
      Banking) and complete the bank and tax forms. Until that agreement is
      Active, App Store Connect will not let an in-app purchase reach
      "Ready to Submit" and `Product.products(for:)` returns an empty array on
      device — the paywall shows no price and looks broken. This is the longest
      lead time in the whole release; start it first.
- [ ] Create the non-consumable IAP with product id
      `com.vansh.SpeakUpMore.lifetime`. It must match `LifetimeProduct.identifier`
      and `Products.storekit` exactly, or the paywall shows no price.
- [ ] Set the localized display name and description for the IAP, and upload
      the required review screenshot of the paywall.
- [ ] Submit the IAP for review *with* the build. A first IAP reviewed
      separately can hold the whole release.
- [ ] Privacy nutrition labels: with the shipped local sink, the answer is no
      data collected and no tracking. Re-answer if a hosted sink is adopted.
- [ ] Paste the text fields from `APP_STORE_LISTING.md` and upload the seven
      default screenshots from `screenshots/final/`, in filename order.
- [x] Display size: 6.9" (1320 × 2868) is the only iPhone slot Connect requires;
      the set is exported at that size and Connect scales it down for everything
      smaller.
- [ ] **Re-capture `simulator-screenshots/` before submitting.** The current
      raws are from 2026-08-14 and 84 commits of UI work have landed since, so
      the composed slides show an old build. Capture on iPhone 17 Pro Max with
      `-seedScreenshotData`; the composer refuses any other pixel size.
- [ ] Slide 2's capture has nav-bar bleed-through (the previous screen's text
      ghosts behind the translucent header). Re-capture scrolled.
- [ ] Re-check the `430` prompt count on slide 4:
      `grep -c "PromptData(" SpeakUp/Data/DefaultPrompts.swift`. It is baked
      into an image and goes stale silently. (430 as of 2026-09-06.)
- [x] Slide 7 wording resolved — it reads "It Stays On Your iPhone", not "AI
      Speech Coaching", so it no longer contradicts the do-not-claim list.
- [ ] Create the four custom product pages in `APP_STORE_PRODUCT_PAGES.md`, each
      submitted with the build, and record the `ppid` URL each one returns. They
      can only be assigned keywords already present in the shared keyword field.
- [ ] Privacy policy URL (required) and, because the app sells a non-consumable,
      a terms/EULA link.
- [ ] **Paid build only:** restore the paywall UI. It is deleted for the beta
      (`docs/features/monetization.md`), and `BetaAccess.allFeaturesFree = true`
      opens every gate. A paid submission needs both reverted, or the app sells
      nothing while claiming a free tier.
- [ ] App Review notes: state that transcription and scoring run on device,
      that the free tier is 14 days of everything but iCloud sync and then three
      analyses per 30 days, that this collects no payment method and charges
      nothing when it ends, that no account is required, and how a reviewer
      reaches the paywall during the 14 days (Settings > Unlock, or turning on
      iCloud sync — curriculum and export are open in that window).
- [ ] Generate offer codes if the launch plan uses them — the redemption sheet
      lives in the restored `PaywallView`.

## 3. Website and in-app links

`SupportLinks` reads three keys from `SpeakUp/Info.plist` and hides any row
whose value is missing or not `https://`. Empty values ship a build with no
outbound legal links, which App Review will notice.

- [x] `BTPrivacyPolicyURL` — `https://www.bigtalkapp.com/privacy`
- [x] `BTTermsURL` — `https://www.bigtalkapp.com/terms`
- [x] `BTSupportURL` — `https://www.bigtalkapp.com/support`
- [x] `SupportLinks.feedbackEmail` is `vansh@trygoldfinch.com`, a monitored inbox.
      The website's support page advertises `hello@bigtalk.app`, which is on a
      domain that does not resolve — fix that on the site, not in the app.

### iCloud container identifier

- [ ] Confirm `iCloud.cam.vanshpatel.SpeakUp` in `SpeakUp.entitlements` is
      registered to this team and enabled on both the app and widget App IDs.
      Container ids do not have to match the bundle id, so this is legal — but
      `cam.` next to a bundle id of `com.vansh.SpeakUpMore` reads like a typo
      for `com.`, and an unregistered container fails signing at archive or
      validation at upload. If it has never been provisioned, fix it now:
      changing it after users have iCloud data is a migration, not an edit.

### Universal links for campaign traffic

Host is `www.bigtalkapp.com` — the apex 308-redirects to it, and iOS follows no
redirects when fetching `apple-app-site-association` or resolving a link, so
every outbound link and the entitlement use the `www` form. Inbound matching
accepts both.

- [x] `BT_UNIVERSAL_LINK_DOMAIN = www.bigtalkapp.com` in
      `Config/SharedVersion.xcconfig`. It feeds `BTUniversalLinkDomain` in
      Info.plist, which `UniversalLink` reads.
- [ ] Enable the **Associated Domains** capability on the App ID in the
      developer portal and regenerate the profile. Do this *before* the next
      build — the entitlement below fails code signing without it.
- [x] `com.apple.developer.associated-domains` in
      `SpeakUp/SpeakUp.entitlements`: `applinks:www.bigtalkapp.com`. It must
      match the xcconfig value; a mismatch fails silently, with links opening
      Safari.
- [x] `Config/apple-app-site-association` is hosted at
      `https://www.bigtalkapp.com/.well-known/apple-app-site-association`
      from the website repo (`public/.well-known/` + a `vercel.json` header
      rule forcing `application/json`). If the file changes here, copy it
      there again — the two are not linked. Check:
      `curl -sI https://www.bigtalkapp.com/.well-known/apple-app-site-association`
      must be `200` with `content-type: application/json` and no redirect.

Then confirm on a device that a link pasted into Notes opens the app, that
`https://<host>/record?prompt=<id>` starts a session, that a share-card link
`https://<host>/record?prompt=<id>&text=...&source=share` opens a friend
challenge (prompt visible, optional beat score on the countdown), and that
`?source=…&campaign=…` shows up on the `first_open` event in Usage Diagnostics.

## 4. Build configuration to verify in Xcode

- [x] In-App Purchase needs no capability or entitlement — it is on by default
      for every App ID and StoreKit 2 requires nothing in `SpeakUp.entitlements`.
      The real gate is the Paid Apps agreement in section 2.
- [ ] Confirm the App Group `group.com.speakup.shared` is enabled on both the
      app and the widget extension — entitlement mirroring and widget data both
      depend on it.
- [ ] Bump `APP_MARKETING_VERSION` and `APP_BUILD_NUMBER` in
      `Config/SharedVersion.xcconfig`.
- [x] The shared `SpeakUp` scheme's `StoreKitConfigurationFileReference` sits in
      its `LaunchAction` only, so archives and TestFlight builds already talk to
      real StoreKit. Nothing to clear.

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
- [ ] **Trial.** On a fresh install, confirm Today reads "Free trial · 14 days
      left" after the first score, and that Learn and journal export are open
      while iCloud sync still raises the paywall.
- [ ] **Allowance.** Expire the trial (Settings > Usage Diagnostics > Free trial
      (debug) > Expire, DEBUG builds only), burn the three analyses, and confirm
      the fourth recording is saved and shows "Saved, not scored yet" rather
      than an error — and that Learn, export, and sync are gated again.
- [ ] **Purchase.** Buy Lifetime in the sandbox, confirm the deferred recording
      scores automatically and every gated surface opens.
- [ ] **Restore.** Delete and reinstall, tap Restore, confirm entitlement
      returns with no account and no re-purchase.
- [ ] **Refund path.** Use StoreKit's transaction manager to revoke the
      purchase and confirm the app returns to the free tier without crashing.
- [ ] **Share privacy.** Open the share sheet on a prompt-backed session and
      confirm it opens on the Scores tab with no prompt text on the preview;
      confirm Save writes to Photos after the permission prompt, and that Copy
      pastes the card; share a Then-vs-Now card and confirm it carries no
      transcript, prompt, or story title.
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
