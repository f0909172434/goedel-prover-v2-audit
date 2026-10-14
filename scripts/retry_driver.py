"""逾時重驗驅動（取代會在 OOM 後卡住的官方 scheduler，只用於重驗）。
範圍（預先登記修訂，2026-10-14）：只重驗第一輪「未解題目」中有 system_errors 的生成；同一題一旦有一次通過，
該題其餘的重驗略過（記為 skipped_problem_solved）。對 pass@32 而言這是精確的：Lean 檢查是確定性的，
第一輪已正常判定的生成不會改變，已解題目再多通過也不影響 pass@32。
每個證明：獨立 REPL（scripts/check_one.py，呼叫官方函式），PROOF_TIMEOUT=1200，
systemd scope 記憶體上限 20G、不用 swap，外層 timeout 1500 秒。每筆結果立即附加到 JSONL，可續跑。
用法：retry_driver.py <results/main-bf16> [workers=8] [mem=20G] [proof_timeout=1200] [--only name1,name2]"""
import json, os, subprocess, sys, threading, time, glob
from concurrent.futures import ThreadPoolExecutor

R = sys.argv[1]
W = int(sys.argv[2]) if len(sys.argv) > 2 else 8
MEM = sys.argv[3] if len(sys.argv) > 3 else "20G"
PT = int(sys.argv[4]) if len(sys.argv) > 4 else 1200
ONLY = None
if "--only" in sys.argv:
    ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(","))
HOME = "/home/wangzhikai"; A = f"{HOME}/audit"; G = f"{A}/Goedel-Prover-V2"; PY = f"{A}/venv/bin/python"
OUT = f"{R}/retry_results_t{PT}_m{MEM}.jsonl" if ONLY is None else f"{R}/retry_test_t{PT}_m{MEM}.jsonl"
TMP = f"{R}/retry_tmp"; os.makedirs(TMP, exist_ok=True)


def correct(cr, code):
    return cr.get("complete") is True and "apply?" not in code and "exact?" not in code


# 第一輪結果
codes, comp = {}, []
for d in sorted(glob.glob(f"{R}/shard_*")):
    for c in json.load(open(f"{d}/to_inference_codes.json")):
        codes[c["problem_id"]] = c
    comp += json.load(open(f"{d}/code_compilation_repl.json"))
prob = lambda name: name.rsplit("_g", 1)[0]
solved = {}
for r in comp:
    solved[prob(r["name"])] = solved.get(prob(r["name"]), False) or correct(r["compilation_result"], r["code"])
if ONLY is not None:
    tasks = sorted(ONLY)
else:
    per = {}
    for r in comp:
        if r["compilation_result"].get("system_errors") and not solved[prob(r["name"])]:
            per.setdefault(prob(r["name"]), []).append(r["name"])
    for v in per.values():
        v.sort(key=lambda n: int(n.rsplit("_g", 1)[1]))
    # 各題輪流排：第一波就涵蓋不同題目，讓「通過就停」真的省到時間
    tasks = [per[p][i] for i in range(max(map(len, per.values()))) for p in sorted(per) if i < len(per[p])]
done = set()
if os.path.exists(OUT):
    for line in open(OUT):
        rec = json.loads(line); done.add(rec["name"])
        if rec.get("correct"):
            solved[prob(rec["name"])] = True
lock = threading.Lock()
print(f"tasks={len(tasks)} already_done={len(done)} workers={W} mem={MEM} timeout={PT}", flush=True)


def run(name):
    p = prob(name)
    with lock:
        if name in done:
            return
        if ONLY is None and solved.get(p):
            rec = {"name": name, "problem": p, "status": "skipped_problem_solved"}
            open(OUT, "a").write(json.dumps(rec) + "\n"); done.add(name); return
    inp, outp = f"{TMP}/{name}.in.json", f"{TMP}/{name}.out.json"
    json.dump(codes[name], open(inp, "w"))
    if os.path.exists(outp):
        os.remove(outp)
    unit = f"lean-retry-{name}-{os.getpid()}-{int(time.time())}"
    cmd = ["sudo", "systemd-run", "--scope", "--quiet", f"--unit={unit}", "-p", f"MemoryMax={MEM}", "-p", "MemorySwapMax=0",
           "--uid=wangzhikai", "--gid=wangzhikai", "/usr/bin/env", f"HOME={HOME}",
           f"PATH={HOME}/.elan/bin:/usr/local/bin:/usr/bin:/bin", f"PROOF_TIMEOUT={PT}",
           "bash", "-c", f"cd {G} && timeout {PT + 300} {PY} {A}/scripts/check_one.py {inp} {outp}"]
    t0 = time.time()
    rc = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    wall = round(time.time() - t0, 1)
    rec = {"name": name, "problem": p, "rc": rc, "wall": wall, "unit": unit}
    if os.path.exists(outp):
        res = json.load(open(outp))
        rec["compilation_result"] = res["compilation_result"]
        rec["verify_time"] = res.get("verify_time"); rec["import_seconds"] = res.get("import_seconds")
        rec["correct"] = correct(res["compilation_result"], res["code"])
        se = res["compilation_result"].get("system_errors") or ""
        rec["status"] = ("correct" if rec["correct"] else
                         "timeout" if se.startswith("TIMEOUT") else
                         "repl_exited(consistent_with_mem_cap)" if se.startswith(("EOF", "JSONDECODE")) else
                         "lean_error" if not se else "other_system_error")
    else:
        rec["correct"] = False
        rec["status"] = "no_output(killed_or_outer_timeout)"
    with lock:
        open(OUT, "a").write(json.dumps(rec) + "\n"); done.add(name)
        if rec["correct"]:
            solved[p] = True
    print(f"{len(done)}/{len(tasks)} {name} {rec['status']} {wall}s", flush=True)


with ThreadPoolExecutor(W) as ex:
    list(ex.map(run, tasks))
print("RETRY_DRIVER_DONE", flush=True)
