Subject: CMPT Daily Fraud Report — Dashboard Updates (Jul 16–17)

Hi team,

Summary of the dashboard changes shipped over the past two days:

1. Navigation & framework

Replaced the four per-section family tab strips with a single "Process Category" selector in the sticky top nav (Testing / CPP / Vendor / ATM) — one click now switches all detail modules (§00.2–§02.1) together.
Modules that intentionally do not follow the selector are now labeled: §00.1 and §02.2 carry a SYSTEM-WIDE tag, §03.1 OWN GROUPING — no more ambiguity about what the selector controls.
Methodology page redesigned as a left table-of-contents layout (one module at a time instead of nine stacked cards).
2. Process Quality Cards (§01.1)

Cards now show two SPC tracks side by side: AFPR and Fraud $ — both as μ ± 2σ control bands with today's marker, so rate deviation and dollar deviation read together at a glance. (Fraud $ uses a per-card scale with the range printed, since $ spans ~100–700× across processes.)
The 7-day trend chart moved into the expandable drawer (click a card) — cards stay compact and never reflow their row. The drawer chart now supports hover: any day shows date, AFPR, total and fraud accounts.
Status colors cleaned up: card border color = classification group (Action / Data Check / Watch), track color = strictly "inside/outside its own ±2σ band" — the legend no longer conflates the two.
Stats compressed to a single line; ~40px shorter per card.
3. Correctness fixes

Masthead status is now a true system-wide roll-up. Previously it was computed once from the Testing category only and never refreshed — it could display "ALL CLEAR" while other categories had active attack/bleed alerts. It now always agrees with the Executive Summary.
7-day chart dates: the x-axis was reading the template's synthetic calendar instead of the injected report dates (charts appeared stuck in May). Now uses the real per-category dates.
Printing now outputs only the page on screen (Dashboard or Methodology), not both.
4. Fraud Merchant Detail (§02.1)

Fixed a ranking-integrity issue in the Approved/Declined lens: extraction previously kept only the top-10 merchants by total $ per source, so approved-heavy merchants that missed the total cut were absent from the Approved leaderboard entirely. The SQL contract now requires a union of the three top-10s (by total, approved, declined) — each lens shows its true leaders. Merchant name variants (e.g. two WALMART.COM descriptors on the same MID) also merge correctly now.
Layout rebalanced to 7:3 (list : detail), detail pane tightened, the ranking subtitle follows the selected lens, and "By Process" now uses two roomier columns instead of three cramped ones.
5. Volume Monitor (§03.1)

All charts stay visible; the table collapses to the top 8 rows with "+N more". Rows flagged WATCH/ALERT are never hidden behind the collapse.
Also: line-chart hovers now show a second label identifying the exact process under the cursor; keyboard/ARIA support extended on expandable cards.

Action on the data side: the merchant SQL for all four categories needs the QUALIFY clause updated to the union pattern (spec in SQL_CONTRACTS.md, Q3) — dashboards render correctly with current data, but Approved/Declined leaderboards are only complete after the re-extract.

Happy to walk through any of these — the demo file reflects all changes.

Best,
Toby

