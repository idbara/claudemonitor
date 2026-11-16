# Pick the account whose limit resets soonest — design (short)

Date: 2026-11-17 · Status: approved in conversation (option A)

**Why:** quota that resets soon is lost if unused. Bara wants to burn the
account closest to its 5-hour reset while it still has plenty left, keeping
fresher accounts for later.

**Rule (★ in Claude Monitor and `cc` start/next account — identical):**
- headroom = `100 − max(5h, 7d)` (weekly still caps it).
- Eligible = headroom ≥ **20%**. Among eligible, the account whose 5-hour
  `resets_at` is soonest wins; any account whose reset is within **15 min** of
  that soonest one competes on headroom (larger wins). Tie → lower 5h, then id.
- An account with no running 5-hour window (no `resets_at`, or one in the past)
  sorts after every account with a window — its quota cannot be lost.
- No eligible account → fall back to the largest headroom > 0. None → no ★ /
  "semua akun penuh".
- ★ still needs ≥ 2 accounts with data.
- `cc`: `expired`/`unknown` accounts still come after all `ok` ones.

**Approaches:** A (threshold + soonest reset, chosen) vs B (score =
headroom ÷ hours to reset; rejected: chases tiny remainders, frequent switches
cost a prompt-cache rebuild).

**Touches:** `AccountMath.recommend` (+ `UsageSnapshot.fiveHourResetsAt`, `now`),
`AccountStore.arrange` (passes resets and `now`), `scripts/cc.py` `_ranked`,
README wording for ★.
