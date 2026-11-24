"""Export analysis tables + experiment sample sizes to dashboard/data.json and inline it into the dashboard."""
import duckdb, json, math, pathlib
from statistics import NormalDist
ROOT = pathlib.Path(__file__).parent
con = duckdb.connect(str(ROOT / "data/ga4.duckdb"), read_only=True)

def rows(sql):
    df = con.sql(sql).df()
    for c in df.columns:
        if str(df[c].dtype).startswith("datetime"):
            df[c] = df[c].dt.strftime("%Y-%m-%d")
    return json.loads(df.to_json(orient="records"))

def n_per_arm(p1, p2, alpha=0.05, power=0.8):
    z = NormalDist().inv_cdf
    za, zb = z(1 - alpha / 2), z(power)
    return math.ceil((za + zb) ** 2 * (p1 * (1 - p1) + p2 * (1 - p2)) / (p2 - p1) ** 2)

h = rows("select * from headline")[0]
chk = rows("""select count(*) filter (where checkout) n, count(*) filter (where payment)/count(*) filter (where checkout) p
              from sessions""")[0]
cat = rows("""select count(*) n, avg(purchase::int) p from sessions where landing_type='category page'""")[0]
home = rows("select avg(purchase::int) p from sessions where landing_type='home'")[0]
rep = rows("""select count(*) filter (where o=1) one, avg((o>1)::int) p from (select user_id, count(*) o from purchases group by 1)""")[0]
days = 92
exp = {
  "checkout": {"baseline": chk["p"], "target": chk["p"] + 0.03, "n_per_arm": n_per_arm(chk["p"], chk["p"] + 0.03),
               "traffic_per_day": chk["n"] / days},
  "category": {"baseline": cat["p"], "target": cat["p"] + 0.25 * (home["p"] - cat["p"]),
               "n_per_arm": n_per_arm(cat["p"], cat["p"] + 0.25 * (home["p"] - cat["p"])), "traffic_per_day": cat["n"] / days},
  "repeat":   {"baseline": rep["p"], "target": rep["p"] + 0.03, "n_per_arm": n_per_arm(rep["p"], rep["p"] + 0.03),
               "traffic_per_day": rep["one"] / days},
}
for e in exp.values():
    e["days"] = math.ceil(2 * e["n_per_arm"] / e["traffic_per_day"])

data = {
  "headline": h,
  "funnel": rows("select * from funnel"),
  "funnel_by_device": rows("select * from funnel_by_device"),
  "landing": rows("select * from landing_perf where landing_type <> 'no pageview'"),
  "search": rows("select * from search_perf"),
  "retention": rows("select * from retention where cohort_wk >= date '2020-11-02' and week_n <= 8"),
  "retention_by_segment": rows("select * from retention_by_segment where segment <> '(data deleted)'"),
  "attribution": rows("select * from attribution where medium not in ('(data deleted)')"),
  "channel_perf": rows("select * from channel_perf where medium not in ('(data deleted)')"),
  "rfm": rows("select * from rfm_summary"),
  "repeat": rows("select * from repeat_gap")[0],
  "opportunities": rows("select * from opportunities"),
  "experiments": exp,
}
out = ROOT / "dashboard"; out.mkdir(exist_ok=True)
(out / "data.json").write_text(json.dumps(data, indent=1))
tpl = (out / "template.html").read_text()
(out / "index.html").write_text(tpl.replace("/*__DATA__*/null", json.dumps(data)))
print(json.dumps(exp, indent=1))
