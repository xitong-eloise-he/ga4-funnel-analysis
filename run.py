"""Run all SQL against DuckDB and export results to dashboard/data.json."""
import duckdb, json, pathlib, sys, time
ROOT = pathlib.Path(__file__).parent
con = duckdb.connect(str(ROOT / "data/ga4.duckdb"))
steps = sys.argv[1:] or sorted(p.name for p in (ROOT / "sql").glob("*.sql"))
for name in steps:
    t = time.time()
    con.execute((ROOT / "sql" / name).read_text())
    print(f"{name}: {time.time()-t:.1f}s", flush=True)
