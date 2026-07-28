# CODING AGENTS: READ THIS FIRST

This is a **handoff bundle** from Claude Design (claude.ai/design).

A user mocked up designs in HTML/CSS/JS using an AI design tool, then exported this bundle so a coding agent can implement the designs for real.

> **Local copy — two notes.** The bundle folder was renamed from
> `ridebuddy-design-set/` to `fahrmitbar-design-set/`, and the paths below
> were fixed to match. Upstream the project is still called
> `RideBuddy Design Set`; the product has been MitFahrBar since v0.34.0.
>
> This is an **export, not the source.** Never edit these files to record a
> decision — the next export overwrites them. Colours the app uses but the
> set does not contain are marked as derived in `lib/core/tokens.dart`.

## What you should do — IMPORTANT

**Read `fahrmitbar-design-set/project/MitFahrBar Design Set.dc.html` in full.** The user had this file open when they triggered the handoff, so it's almost certainly the primary design they want built. Read it top to bottom — don't skim. Then **follow its imports**: open every file it pulls in (shared components, CSS, scripts) so you understand how the pieces fit together before you start implementing.

**If anything is ambiguous, ask the user to confirm before you start implementing.** It's much cheaper to clarify scope up front than to build the wrong thing.

## About the design files

The design medium is **HTML/CSS/JS** — these are prototypes, not production code. Your job is to **recreate them pixel-perfectly** in whatever technology makes sense for the target codebase (React, Vue, native, whatever fits). Match the visual output; don't copy the prototype's internal structure unless it happens to fit.

**Don't render these files in a browser or take screenshots unless the user asks you to.** Everything you need — dimensions, colors, layout rules — is spelled out in the source. Read the HTML and CSS directly; a screenshot won't tell you anything they don't.

## Bundle contents

- `fahrmitbar-design-set/README.md` — this file
- `fahrmitbar-design-set/project/` — the `RideBuddy Design Set` project files (HTML prototypes, assets, components)
