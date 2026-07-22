# CMPT Daily Fraud Report — Pro package

Self-contained daily dashboard + the Snowflake→HTML injection pipeline. Two files:
fill the SQL slots in the script, run it once per day.

## What's in here

| File | Role |
|---|---|
| `cmpt_report_pro_vv.html` | **The dashboard template (V9 baseline).** Self-contained — no CDN, no fetch; opens via `file://` or as a Gmail attachment. Contains the `INJECTED_DATA` hook. Opened as-is it shows a fully synthetic demo. |
| `build_report_pro_final.py` | **Injection script.** Pulls Snowflake data (and optionally the rule-performance `.xlsx`), bakes everything into a copy of the template as one `INJECTED_DATA` block. All SQL slots + column contracts live at the top of this file. |

> The **template** bundles synthetic data only — no real production rule/source/merchant names
> (testing sources are anonymized as `testing_src_NN`, merchants as `MERCHANT_A/B/…`).
> **Generated** reports contain real production fraud data → internal distribution only;
> never commit them to git, never host them publicly.

## Dashboard structure (V9)

Framework is built around the two core KPIs — **Fraud $** (Total = Approved + Declined) and
**AFPR** (over-block signal):

```
00  Overview        — Executive Summary (system-wide) · Process Deviation Matrix
01  Per-process     — Quality Cards (AFPR + Fraud $ SPC tracks) · AFPR multi-line · Fraud $ trend
02  Attribution     — Fraud Merchant Detail (dual-grain) · Follow-up Fraud Detail (system-wide)
03  Data health     — Process Volume Monitor (own grouping)
06  Methodology     — per-module design rationale (TOC layout)
```

A single **Process Category** selector in the top nav (Testing / CPP / Vendor / ATM) drives
§00.2–§02.1. Modules labeled `SYSTEM-WIDE` / `OWN GROUPING` intentionally don't follow it.

## Filling the SQL slots

All slots live at the top of `build_report_pro_final.py`; a slot left as placeholder/comment
is auto-skipped and the dashboard falls back to synthetic for that block only.

| Slot | Grain | Feeds |
|---|---|---|
| `PROCESS_SQL` — `cpp` / `testing` / `vendor` / `atm` | source × tier × day, ~90d | §00.2, §01.x, §02 trend |
| `MERCHANT_SQL` — `cpp` / `testing` / `vendor` / `atm` | merchant (`mid+mcc`) × SRCE, trailing window | §02.1 |
| `VOLUME_SQL` — `cpp` / `testing` / `mlist` | source × day, ~6 months | §03.1 |

### Contract essentials

**Q2 — process daily metrics** (source × tier × day):
- Emit an explicit **`All` tier row** per source per day. `All` row `FRAUD_DLR` = **TOTAL**
  fraud $ (approved + declined, no approve filter); `T1/T2/T3` row `FRAUD_DLR` = **APPROVED** $.
  Declined = All − Σtier is derived from this — get it backwards and the split shows 0.
- `FRAUD_DLR_HS` (All row) and `FRAUD_DLR_V15` (T2/T3 rows) are **required**, not optional —
  they drive the HS toggle and the 15-min-verified exclusion in §01.3.
- AFPR is recomputed from `TOT_ACCT` / `FRAUD_ACCT`.
- Windows: Testing 10d · CPP/Vendor/ATM 15d, reconstructed as-of each day (no look-ahead).

**Q3 — merchants** (per family):
- Two grains: `SRCE='All'` = per-merchant dedup (each txn once → the ranking view);
  `SRCE=<source>` = per-process attribution ($ NOT additive across processes).
- Group by `mid + mcc` with **`max(merch_name)`** so name variants merge (two WALMART
  descriptors on one MID must be one row).
- Columns: `SRCE, MERCH_NAME, MID, MCC, FRAUD_DLR, FRAUD_DLR_APR, FRAUD_DLR_DCL,
  FRAUD_ACCT_APR, FRAUD_ACCT_DCL, TOT_TRAN, FRAUD_TRAN, TOT_ACCT, FRAUD_ACCT`.
- **Extraction must keep the union of the three top-N boards** — top-N by total AND by
  approved AND by declined — or the Approved/Declined leaderboards silently miss their true
  leaders. Per-source N=10; the `All` grain N=30:

```sql
QUALIFY LEAST(
    ROW_NUMBER() OVER (PARTITION BY srce ORDER BY fraud_dlr     DESC),
    ROW_NUMBER() OVER (PARTITION BY srce ORDER BY fraud_dlr_apr DESC),
    ROW_NUMBER() OVER (PARTITION BY srce ORDER BY fraud_dlr_dcl DESC)
) <= 10          -- merch_all: no PARTITION BY, <= 30
```

### Credentials (cred json)

`snowflake_connect()` reads a **local JSON file** — username/password are never hardcoded in
the script and never committed anywhere. The file must contain exactly these three keys:

```json
{
  "username": "your_snowflake_user",
  "password": "your_password",
  "role_id":  "ROLE_EXIAO"
}
```

- Default location = `CRED_PATH` (a constant near the top of the script); override per-run
  with `--creds /path/to/cred.json`.
- Keep it outside any repo/shared folder and lock it down: `chmod 600 cred.json`.
- Rotating your password = edit this file only; the script never changes.

⚠️ **This copy of the script has the connection constants stripped** (scrubbed for sharing).
Before the first `--snowflake` run, the block above `snowflake_connect()` must define, in
addition to `USE_DFS_PROXY`:

```python
CRED_PATH        = "/path/to/cred.json"   # default cred file location
SF_AUTHENTICATOR = "..."                  # e.g. "snowflake" / your SSO authenticator
SF_ACCOUNT       = "..."                  # company Snowflake account locator
SF_WAREHOUSE     = "..."
SF_DATABASE      = "..."                  # e.g. SFAAP
SF_SCHEMA        = "..."                  # e.g. WS_CARD_FRAUD_DATA
```

Copy the values from your working notebook (they're environment facts, not secrets — the
secret stays in the cred json). Without this block the script stops with a `NameError`
before connecting.

## How to run

```bash
# full daily build (the script's --template default is an old name — always pass it explicitly)
python build_report_pro_final.py --snowflake \
                                 --template cmpt_report_pro_vv.html \
                                 --out cmpt_report_$(date +%Y%m%d).html
```

```bash
# optional: include the rule-performance workbook in the same build
python build_report_pro_final.py --excel <WORKBOOK>.xlsx --snowflake \
                                 --template cmpt_report_pro_vv.html \
                                 --out cmpt_report_$(date +%Y%m%d).html
```

```bash
# dry-run the Excel parse (writes nothing)
python build_report_pro_final.py --excel <WORKBOOK>.xlsx --template cmpt_report_pro_vv.html --validate
```

The build stamps `meta.generated` / `meta.dataAsOf` from the Python run (not the viewer's
clock). The inject summary line (`families[cpp:9p+120m, ...]`) is the quickest check that
each block actually landed.

## Requirements

```
python 3.8+
pip install openpyxl snowflake-connector-python
```

(`openpyxl` only needed for `--excel`; no pandas.)

## Verifying a build

- Masthead shows real `Data as of` / `Generated` timestamps (not the synthetic calendar).
- Each wired category's charts show real dates on the x-axis; unwired categories still show
  the synthetic May dates — that's the fallback, not a bug.
- Controls whose data wasn't supplied (HS / 15-min-verified / approve-decline split) disable
  themselves with a "not provided" tooltip — the dashboard never fabricates a missing series.

## Scheduling

Daily DAG shape:

```
Snowflake → build_report_pro_final.py → cmpt_report_YYYYMMDD.html → EmailOperator (attach HTML)
```

Schedule 4–5am ET; analysts open the attachment at 9am. If posting to Slack, private
access-restricted channels only; token via env var / Airflow Connection, never hardcoded.
