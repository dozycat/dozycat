# We Rewrote It Anyway

> They did it by making the single worst strategic mistake that any software company can make: They decided to rewrite the code from scratch.
>
> — Joel Spolsky, "Things You Should Never Do, Part I", 2000

Spolsky wrote that in 2000, about Netscape deciding to rebuild its browser from the ground up and then going three years without shipping a new version. His reasoning was simple. Old code looks messy because it's full of bug fixes collected over the years. Every strange branch is there because of a real user's problem, and a rewrite throws all of that knowledge away.

For more than twenty years, that has been close to industry consensus. We rewrote anyway.

This post is about what happened. But first, the framework we were betting on.

**The premise: AI now writes code faster than people can read it.**

A coding agent today can open more pull requests in one evening than I can carefully review the next day. It writes features, adds unit tests, fixes CI, and updates the docs along the way. Writing code is no longer the bottleneck. **Knowing the code is right** is.

So whenever I design a framework or a process for Zero, the AI assistant we're building, I start with two questions:

1. **Will it become the bottleneck?** If a verification step takes minutes, or needs a person, the whole pipeline moves at that speed, no matter how fast the AI writes.
2. **Can the AI game it?** The AI's goal is to make the check pass. The closer a check sits to the implementation, the easier it is to satisfy without doing the real work: change what a mock returns, loosen an assertion, add a special case to one branch. When no human can keep up with the output, nobody notices. This is reward hacking.

::: diagram review-throughput

Three decisions came out of those two questions.

**First: verification has to be as fast as the AI.**

Zero had a full native Swift app, and it felt great. But a compiled UI slows verification down in two ways. Changing one line of interface means a full compile, sign, and install cycle. And running it needs Xcode and a simulator, which is hard to do in bulk, in parallel, and unattended on an ordinary Linux machine.

I made a fairly big bet: **as CPUs keep getting faster, an interpreted UI will be good enough in most cases.** The human eye can only follow so many frames, while hardware keeps getting faster. Most users will never feel the extra performance a compiled UI buys. The time an interpreted UI saves on verification gets used every single day.

So the client moved to Expo and React Native. The same interface renders in a browser through react-native-web, and Playwright drives it. On every pull request, a Linux runner starts the production backend and agent, an embedded PGlite database, Redis, and the web app, and puts the whole product through a checkup. Every step saves a screenshot and the accessibility tree, so when something fails, the AI can read those files and find the problem on its own. Nobody has to tap through a simulator.

One round of end-to-end verification now takes about as long as one round of the model writing code.

The web isn't native, of course. Lock-screen cards, the Dynamic Island, and system animations still have to be checked on a Mac, a simulator, or a real phone. So verification has four layers. Each layer down is more realistic, slower, more expensive, and runs less often.

::: diagram verify-layers

**Second: one clock for the whole system.**

A lot of what Zero does is about time. It starts preparing a meeting brief 30 minutes before the meeting and sends the notification 15 minutes before. A note you jot down on your iPad late at night shouldn't make your phone buzz all night. A login token expires after an hour and should be refreshed without you noticing. In the real world, you'd wait tens of minutes, or a whole night, to see any of this happen once.

The usual approach is to mock time wherever it's used: a fake clock in the scheduler, another in the token check, a parameter in place of `now()` in SQL. Every mock is one more gap where time in the test can drift from time in production, and every gap is a place for the AI to cheat.

We went the other way: **no business code touches time. We control how fast it flows, at the very bottom.** Before any service loads, the checkup process replaces the global `Date` with `virtual = real + offset`. The database's `now()`, the scheduler, token issuing, and the current time in the agent's prompt all read the same clock, and the browser follows it through Playwright's clock. Time still passes at real speed, so timers and concurrency stay real, but the clock can jump forward. It never goes back. Production code doesn't know it exists.

::: diagram virtual-clock

Confirm an 11:00 meeting at 9:00. Jump to 10:29: nothing should have happened. At 10:30, the agent starts preparing the brief, using its notes on Kiwi and Monica. At 10:44 the brief is ready, and the lock screen is still quiet. At 10:45, the notification arrives. Two hours of product time play out in about a minute.

**Third: trust only what the user sees.**

Where an assertion lives decides how easy it is to fool.

Zero's tests are written as a storybook called *Kiwi's Wednesday*. Each test is a scene from one day in Kiwi's life: what Kiwi asked for, which card appeared, and, after one tap on the lock screen, what showed up in the app and what went away. Between that tap and the change on screen sits the whole real system: client, backend, agent, database, and push.

An assertion like that is hard to fake with a one-line change. To make "Kiwi sees this card" true, you have to get the whole path right.

A few rules make cheating harder still:

- **Only the model and the outside world are replaced.** The model is a scripted stand-in that follows a script, and Google, Feishu, and APNs are protocol-level fakes. Everything else is production code.
- **Assertions are promises Kiwi could read.** "Exactly one card on the lock screen, no ordinary notification", not `apns.length === 1`. If a test can't be written into the story, we haven't worked out what it means for the user yet.
- **Known issues fail in reverse.** If a bug marked `knownIssue` stops reproducing, the checkup turns red, so someone has to confirm why it went away.
- **Ratchets only tighten.** Things like the number of web-only code branches and iOS pixel differences have baselines that can only go down.
- **The data is locked.** Kiwi's seed data is pinned by SHA-256, so nobody can change the data to make a test pass.

Because the assertions sit where the user is, they don't care about the implementation. As long as Kiwi's day goes the same way, the checkup stays green. I used to say this was what would let us do big refactors safely. Until this rewrite, that was only a claim.

**Then we rewrote it.**

Zero 2.0 was an incompatible rewrite. From the audit on October 30 to the merge on November 2: four days, 381 commits, 366 of them written by coding agents, 2,139 files changed, and roughly a hundred thousand lines added and as many removed.

No one can read a change that big line by line. It was the premise above taken to its extreme: the AI writes far faster than anyone can review, and verification is all you have. So I treated it as an experiment. This is the write-up.

**Why it had to happen all at once.**

2.0 assumed every user would be made to upgrade once. No compatibility with old clients, old protocols, or old local storage. Production data would move to the new structure in one go, during a write freeze.

We skipped a gradual migration because of what the audit found: the compatibility layer was itself the biggest piece of code. To match the old Java and Python backends byte for byte, the code had 147 places with things like `javaBlank`, `LegacyJsonNumber`, and Jackson fingerprints, all locked down by golden fixtures exported from a sibling repo. The state of a single confirmation card was spread across six to eight fields. Each agent pod ran 13 pollers, each writing in its own way. A gradual migration would have kept old and new side by side for a long time, and all of that would have lived on.

The price of doing it at once is that there's no gradual rollout. A gradual migration finds problems through dual writes, feature flags, and a small group of users going first. A one-shot switch can only find them before the merge. Our refactoring plan had a single acceptance rule: correctness no longer means matching the old implementation byte for byte. Behavior is defined by the product checkup and by eval replays.

This was also our answer to Spolsky. Some of the knowledge collected in the old code no longer lives in the code. It lives in the story of *Kiwi's Wednesday*. As long as the story survives, a rewrite only throws away the implementation. Whether that holds up is what the rest of this post is about.

**How much the storybook changed.**

Start with the most direct question: the foundation was replaced, so how much did the checkup have to change?

All of `scripts/product-checkup` changed across 64 files, +511/−392. The tests themselves were 54 files, +359/−300. The assertions fall roughly into three layers, and they fared very differently:

::: diagram rewrite-layers

The top layer barely moved, as expected. The work was in the other two. We'd added them to see what was happening in the middle. They're easy to write and handy when debugging, but they're really assertions about the implementation. Looking back, the thicker those two layers are, the more a migration costs.

Two more things helped. The checkup runs the real production backend and agent, so once the internals moved to jobs, `/api/v2`, and the client runtime, the checkup was testing the new code directly, with no extra adapter. And Kiwi's seed data is pinned by SHA-256. We didn't re-export it this time. We kept its pre-2.0 shape and mapped it to v2 at load time. The data and the story stayed the same. Only the implementation in between changed.

**What it caught.**

To accept the change, we ran all 67 checkup tests on the baseline commit, ran them again after the rewrite, and compared. Plenty of red lights came on along the way. These are the ones that turned out to be real product bugs. The unit tests were green for every one of them.

*After the token expired, the app stopped getting updates.* `journey-conference-day` is a morning with Kiwi and Monica. After the four domain branches were merged, the scene stalled at 12:10, when Kiwi reopens the app: the "Contact Updated" that should have appeared never did. The calendar domain had copied `connection.token` when it mounted, and because it happened to mount last, it took over the sync port for the whole account. When the session was renewed, the new token went into the original connection object. The calendar domain's copy stayed stale, so once the token expired, every `/api/v2/sync` call for the account came back 401.

This bug needs three things at once: the calendar domain mounts last, the token expires, and the server has changes after that. Every domain branch passed its own tests. The bug only shows up after the merge, and only after one token lifetime of real time has passed. The virtual clock fast-forwarded the morning to 12:10, and production code decided on its own whether the token had expired. Nobody mocked it. Making time a first-class part of the system paid off right here.

*The notification arrived before the brief.* To track down the bug above, we bisected the merge commits. On the commit just before the calendar branch was merged, the same scene got further and stalled somewhere else: the APNs reminder came at the wrong moment. Once the assistant's pre-meeting run moved to the jobs runtime, it fired right on time. But the brief was still being published by its own timer, every 15 seconds. So when the notification reached the lock screen, the brief it was meant to open hadn't been published yet. Two bugs were stacked in that one scene, and the first was hiding the second.

*Things handed to the assistant didn't show up in Up next.* The account domain recorded every calendar write as an `assistant.schedule` change, but the assistant's store ignored that kind of change and only reloaded after the assistant sent a message.

*A screenshot was saved to contacts, but the thread never got the message.* A few server-side paths, like screenshot results and the welcome thread, inserted rows straight into `task_messages`, bypassing the message store. No change log entry was written, so the client never received them.

These bugs have one thing in common: **the data in the database was right.** What broke was somewhere along the chain from database write to change log to client cache to screen. 2.0 made the server the single source of truth, with the client catching up only through the change log. The price is a new kind of bug: something writes to the database and forgets to emit the change. Assertions that query the database can't see it. Assertions that read the screen can.

::: diagram sync-chain

**The one it missed.**

There was also a time when the check passed and the product was wrong. The cause was our acceptance rule, not the AI changing a test.

The baseline already had 7 failing checkup tests. Our rule was: after the rewrite, if the remaining failures have the same names as the baseline failures, that counts as a pass. In the end, 60 passed and 7 failed, and the names matched exactly.

One of them was `contact-merge`. On the baseline, it stopped at step two. An earlier redesign on main had changed some copy, the test couldn't find "Introduced by Wang", and it aborted. Line 137 of that test holds the assertion "calendar attendee Monica is still a contact link you can open". That line never ran once during the entire rewrite.

And the rewrite introduced a regression right there. When contacts were merged, the attendee was re-pointed to the surviving contact, but no change was written for the calendar event. The client cache still held the id of the deleted duplicate, so the attendee turned into plain text you couldn't tap. Only when we merged main and picked up the copy fix did `contact-merge` on CI reach step 14 and turn red.

This wasn't a new bug. It's the first row of our checkup findings table, "merging contacts doesn't re-point calendar attendees", fixed on October 13. My earlier write-up even used it as an example. Three weeks later, it came back on the new foundation in a different form. This is exactly what Spolsky worried about: bugs you've already fixed get thrown away along with the old code. This time the knowledge really did live in the story, and the story really could catch it. The assertion was just blocked by an unrelated failure earlier in the same test.

::: diagram blind-spot

The framework actually has a tool for this. `knownIssue` marks a known problem, and the checkup fails if the problem stops reproducing. We didn't use it this time. We compared test names by hand. Comparing names means treating every assertion after the failure point in a failing test as a pass. Seven failing tests meant seven blind spots.

It reminded me of Goodhart's law: when a measure becomes a target, it stops being a good measure. "The failure list matches the baseline" was a reasonable approximation. Once it became the bar for merging, all it measured was whether the lists matched.

**False alarms.**

It went the other way too. Several red lights turned out to be problems in the tests themselves. `contact-card-confirm` reported "POST action missing" and `meeting-brief-timeline` reported "confirmation card missing". In both cases, the timing matcher was still looking for `/api/v1/tasks/:id/action`, while card decisions had moved to `POST /api/v2/cards/:id/decision`. `voice-message` reported "key = not connected" because, after a security fix, the voice service now uses a short-lived key issued by the backend.

The most misleading was `journey-duplicate-person`. Its failure message read "merge was blocked… blocked false, duplicate still present", which looks exactly like a product bug. It was only the regex for `HTTP 409 POST /api/v1/contacts/:id/merge` no longer matching the new route.

None of these makes the checkup looser, but each one takes time to sort out: is the product wrong, or the test? After enough of them, people start assuming red probably means a test problem, and the next real red light is easier to wave through. Those 76 route regexes are 76 places where that can happen.

**What it can't see.**

After the merge, 2.0 ran for a day with internal accounts on the zero-v2 environment. The most serious problems it turned up were ones the checkup can't see by design:

- **Hermes has no `crypto.randomUUID`.** Generating idempotency keys threw an error, so on TestFlight builds, device registration, push registration, and every PATCH never went out. The checkup runs in Chromium and the tests run in Bun, and both have that global.
- **First sync for a large account was too slow.** One page of the snapshot query took 15 seconds, migrated accounts pulled everything again, and over a trans-ocean link a page couldn't finish downloading in 15 seconds. After a reinstall, task details just spun. Kiwi's data is small and PGlite runs on localhost, so the checkup has neither scale nor a slow network.
- **Every token refresh created a new push registration.** Seventeen piled up in 11 hours, and the Live Activity binding got lost. That's native-only code, and the virtual iPhone never takes that path.
- **The data migration stalled on a production copy.** The new tables had no statistics, and a query plan got stuck for more than ten minutes. The checkup doesn't cover data migrations.

Code review caught the client's recovery paths. Greptile raised four P1 issues on the PR: an older edit to a record overwriting a newer one after a retry; deleted events staying in local storage after a snapshot restarted halfway; the 409 for `idempotency_key_in_progress` being treated as a final failure, which dropped pending writes; and the cursor moving forward even when the local database had only saved part of a batch. The checkup's weak-network tests touched very few of these.

None of this contradicts the four layers. I used to describe the fast L0 web checkup as the main line, with the slower L1 to L3 layers there to calibrate it. What I learned this time is that the lower layers aren't just calibration. The Hermes runtime, real data volumes, slow networks, and native-only code are things L0 will never see, however we change it. The rewrite listed real-device testing, real-database testing, eval replays, and a cutover rehearsal as launch gates, and those are exactly where the problems surfaced. They just surfaced after the merge.

**What we'll change next.**

In order of priority:

- **Compare against the baseline down to the assertion.** Compare the first failing assertion and its reason, not just the test name. Assertions that don't depend on the failure point keep running. Known failures get a `knownIssue` mark on the specific assertion, instead of someone checking lists by hand.
- **Run the full suite on CI for big changes.** The rewrite only ran the core 6 tests on CI, three times, and never added `checkup:full`. The full runs, the bisecting, and the baseline comparison all happened locally, with no record on the PR. Pull requests above a certain size should run the full suite automatically and post the per-assertion comparison.
- **Move middle-layer assertions into semantic helpers.** Table queries and route regexes go into a small set of helpers, like "card was decided", "merge was rejected", and "duplicate still present". Routes and table names appear only inside the helpers, so the next migration changes one place, and failure messages say what they mean.
- **Turn what it can't see into stories.** Strip the globals Hermes doesn't have from the web checkup. Add a large-account version of Kiwi. Write the client's recovery paths as scenes with fault injection, like Kiwi editing a note about Monica on the subway.

All of this is still a plan. None of it has shipped yet.

**Back to Spolsky.**

He was against rewrites because the knowledge collected in old code had nowhere else to live. Things are a little different now. Writing code is cheap, and that knowledge can move out of the code and into stories about what users go through. Then the code itself can be replaced.

I think the results mostly back that up. A hundred thousand lines changed, the storybook changed by a few hundred, and several bugs that crossed branches and crossed time were all found by one morning in Kiwi's life. The results also show what it depends on: every scene has to play all the way through, and the acceptance rule can't skip scenes on the story's behalf. A rewrite should throw away the implementation, not the lessons the story remembers.
