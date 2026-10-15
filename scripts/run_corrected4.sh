#!/bin/bash
# 後續驗證：論文所用 miniF2F（AI-MO/minif2f_test）中與 repo 版本不同的 4 題，修正版陳述 × 32 次。
# 生成：官方 inference_seedlog.py（同主跑），AUDIT_SEED=2000。Lean：官方 compile.py（300 秒），系統錯誤再以 1200 秒／20G 重驗。
set -uo pipefail
A=$HOME/audit; G=$A/Goedel-Prover-V2; M=$A/models/Goedel-Prover-V2-8B; PY=$A/venv/bin/python
F=$A/followup; O=$F/out; mkdir -p $O
export PATH=$HOME/.elan/bin:$PATH
exec 9>$A/followup.lock; flock -n 9 || exit 1
cd $G
log() { echo "$(date -u +%FT%TZ) $*" >> $F/followup.log; }

# 1. 陳述可編譯（帶 sorry：應 pass=True、complete=False）
$PY - <<EOF
import json
for l in open("$F/minif2f_corrected4.jsonl"):
    r = json.loads(l)
    json.dump({"problem_id": r["name"] + "_stmt", "full_code": r["lean4_code"]}, open(f"$O/{r['name']}_stmt.in.json", "w"))
EOF
for f in $O/*_stmt.in.json; do
  PROOF_TIMEOUT=300 $PY $A/scripts/check_one.py $f ${f%.in.json}.out.json
done
$PY -c "
import json,glob
for f in sorted(glob.glob('$O/*_stmt.out.json')):
    c=json.load(open(f))['compilation_result']; print(f.split('/')[-1], 'pass', c.get('pass'), 'complete', c.get('complete'), 'errors', len(c.get('errors') or []))
" >> $F/followup.log
log "statement check done"

# 2. 生成（看門狗同 run_main.sh）
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv > $O/gpu.txt
t0=$(date +%s)
AUDIT_SEED=2000 $PY src/inference_seedlog.py --input_path $F/minif2f_corrected4.jsonl --model_path $M --output_dir $O --n 32 --gpu 1 \
  --inference_handler dpskcot --correction_round 0 --max_model_len 40960 --temp 1.0 > $O/inference.log 2>&1 &
pid=$!
while kill -0 $pid 2>/dev/null; do
  if grep -q "Script finished." $O/inference.log; then sleep 60; pkill -P $pid; kill $pid 2>/dev/null; break; fi
  sleep 20
done
wait $pid
log "generation done seconds=$(( $(date +%s) - t0 )) finished=$(grep -c 'Script finished.' $O/inference.log)"

# 3. 官方 Lean 檢查（300 秒），3 workers
PROOF_TIMEOUT=300 $PY src/compile.py --input_path $O/to_inference_codes.json --output_path $O/code_compilation_repl.json --cpu 3 > $O/compile.log 2>&1
log "compile rc=$?"

# 4. 系統錯誤以 1200 秒、20G 重驗（每證明獨立 REPL）
$PY - <<EOF
import json, os, subprocess
O = "$O"; A = "$A"; G = "$G"; PY = "$PY"; H = os.path.expanduser("~")
codes = {c["problem_id"]: c for c in json.load(open(f"{O}/to_inference_codes.json"))}
res = json.load(open(f"{O}/code_compilation_repl.json"))
out = open(f"{O}/retry_t1200_m20G.jsonl", "w")
for r in res:
    if not r["compilation_result"].get("system_errors"):
        continue
    n = r["name"]; inp, outp = f"{O}/{n}.retry.in.json", f"{O}/{n}.retry.out.json"
    json.dump(codes[n], open(inp, "w"))
    cmd = ["sudo", "systemd-run", "--scope", "--quiet", f"--unit=fu-{n}-{os.getpid()}", "-p", "MemoryMax=20G", "-p", "MemorySwapMax=0",
           "--uid=wangzhikai", "--gid=wangzhikai", "/usr/bin/env", f"HOME={H}", f"PATH={H}/.elan/bin:/usr/bin:/bin", "PROOF_TIMEOUT=1200",
           "bash", "-c", f"cd {G} && timeout 1500 {PY} {A}/scripts/check_one.py {inp} {outp}"]
    subprocess.run(cmd)
    rec = {"name": n}
    if os.path.exists(outp):
        rec.update(json.load(open(outp)))
    out.write(json.dumps(rec) + "\n"); out.flush()
EOF
log "retry done"

# 5. 摘要
$PY - <<EOF >> $F/followup.log
import json, collections
O = "$O"
ok = lambda cr, code: cr.get("complete") is True and "apply?" not in code and "exact?" not in code
res = json.load(open(f"{O}/code_compilation_repl.json"))
retry = {}
for l in open(f"{O}/retry_t1200_m20G.jsonl"):
    r = json.loads(l)
    if "compilation_result" in r: retry[r["name"]] = r
c300, c1200, se = collections.Counter(), collections.Counter(), collections.Counter()
for r in res:
    p = r["name"].rsplit("_g", 1)[0]
    c300[p] += ok(r["compilation_result"], r["code"])
    rr = retry.get(r["name"], r)
    c1200[p] += ok(rr["compilation_result"], rr["code"])
    se[p] += bool(r["compilation_result"].get("system_errors"))
for p in sorted(c300):
    print(f"RESULT {p}: correct@300s={c300[p]}/32 correct@1200s-retry={c1200[p]}/32 system_errors@300s={se[p]}")
EOF
log "FOLLOWUP_DONE"
sudo shutdown -h +3 "followup finished"
