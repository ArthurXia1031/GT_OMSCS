# Airflow single-file build

The cloud Airflow can only run **one Python file** — it can't ship the HTML template as a
sidecar. This folder solves that by **embedding the template inside the script** (gzip +
base64), producing one self-contained file.

| File | Role |
|---|---|
| `pack.py` | The packer. Reads the pipeline script + the HTML template from `../cmpt_report_pro_package/` and emits `cmpt_daily_report.py`. |
| `cmpt_daily_report.py` | **Build artifact — never edit by hand.** The single file Airflow runs. Contains the full pipeline + the embedded template. Regenerate with `pack.py` after any change to the sources. |

## Workflow

```
edit SQL in build_report_pro_final.py  ─┐
edit template cmpt_report_pro_vv.html  ─┴─►  python pack.py  ─►  cmpt_daily_report.py  ─►  Airflow
```

On the **company machine**, run `pack.py` against YOUR copy of the script (the one with the
real SQL filled in):

```bash
python pack.py --script /path/to/build_report_pro_final.py \
               --template /path/to/cmpt_report_pro_vv.html \
               --out cmpt_daily_report.py
```

The packed file inherits whatever SQL the source script had at pack time — repack after
every SQL/template change.

## Running the packed file

**Zero-config — this is the Airflow mode.** Just execute the file, no arguments:

```bash
python cmpt_daily_report.py
```

**Smoke test first** (any machine, incl. the first Airflow deploy — no Snowflake, no creds):

```bash
CMPT_DEMO=1 python cmpt_daily_report.py     # writes cmpt_report_demo.html (synthetic data)
```

If that produces an openable dashboard, the file + output path work; drop `CMPT_DEMO` for real runs.

That alone = full daily build: Snowflake pull → inject into the embedded template →
`cmpt_report_YYYYMMDD.html` written next to the script. Optional env overrides:

| Env var | Effect | Default |
|---|---|---|
| `CMPT_OUT_DIR` | where the dated HTML lands | the script's own folder |
| `CMPT_SNOWFLAKE` | `0` disables the Snowflake pull | on |
| `CMPT_EXCEL` | path to a rule workbook to include | off |

CLI mode still works when arguments are given (`--out`, `--validate`, etc.), and an explicit
`--template some.html` **overrides** the embedded copy (useful for testing a template tweak
without repacking).

### In the DAG

Either shape works:

```python
# BashOperator
BashOperator(task_id="build_report",
             bash_command="python /path/cmpt_daily_report.py --snowflake "
                          "--out /data/cmpt/cmpt_report_{{ ds_nodash }}.html")

# PythonOperator — the packed file exposes run_daily()
from cmpt_daily_report import run_daily
PythonOperator(task_id="build_report", python_callable=run_daily,
               op_kwargs={"out": "/data/cmpt/cmpt_report_{{ ds_nodash }}.html"})
```

## Connection constants & credentials

The packed file still needs, at runtime:

1. **The cred json** (`username` / `password` / `role_id`) at `CRED_PATH` or via `--creds`.
   Never packed, never committed. See the main package README for the format.
2. **Connection constants** (`SF_ACCOUNT`, `SF_WAREHOUSE`, `SF_DATABASE`, `SF_SCHEMA`,
   `SF_AUTHENTICATOR`, `CRED_PATH`). If the source script defines them (company copy),
   they're baked in and nothing else is needed. If it doesn't (scrubbed/shared copy),
   `pack.py` auto-adds **env-var fallbacks** — set `CMPT_SF_ACCOUNT`, `CMPT_SF_WAREHOUSE`,
   etc. (e.g. in the Airflow Connection/env), and a missing value fails with a clear
   actionable error instead of a `NameError`.

## What's verified

- Embedded template is **byte-identical** to the source HTML (sha256-checked).
- Injection works with no template file on disk; explicit `--template` override still works.
- `--help`, missing-source, and missing-constants paths all exit with clear errors.

> Same security boundaries as the main package: the packed file contains only the synthetic
> template; **generated** reports carry real data → internal only, never in git.
