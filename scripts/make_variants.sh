#!/bin/bash
# 從官方 src/inference.py 產生稽核用變體，並把 diff 存檔。官方檔案不改。
#   inference_seedlog.py：種子可由 AUDIT_SEED 指定；不指定時照官方用 random，但印出來（唯一修補）
#   inference_seedlog_kvfp8.py：再加 kv_cache_dtype="fp8"
set -euo pipefail
G=$HOME/audit/Goedel-Prover-V2/src; OUT=$HOME/audit/env
python3 - "$G" <<'EOF'
import sys
g = sys.argv[1]
src = open(f"{g}/inference.py").read()
old_seed = "seed = random.randint(1, 99999)"
new_seed = ('seed = int(os.environ["AUDIT_SEED"]) if os.environ.get("AUDIT_SEED") else random.randint(1, 99999)\n'
            'print(f"AUDIT_SEED_USED={seed}", flush=True)')
assert src.count(old_seed) == 1
seedlog = src.replace(old_seed, new_seed)
open(f"{g}/inference_seedlog.py", "w").write(seedlog)
old_llm = "max_model_len=args.max_model_len, tensor_parallel_size=args.gpu)"
assert seedlog.count(old_llm) == 1
open(f"{g}/inference_seedlog_kvfp8.py", "w").write(
    seedlog.replace(old_llm, 'max_model_len=args.max_model_len, tensor_parallel_size=args.gpu, kv_cache_dtype="fp8")'))
EOF
# os 在 seed 那行之前已 import（官方第 5 行）
diff -u $G/inference.py $G/inference_seedlog.py > $OUT/patch_seedlog.diff || true
diff -u $G/inference.py $G/inference_seedlog_kvfp8.py > $OUT/patch_seedlog_kvfp8.diff || true
echo variants ready
