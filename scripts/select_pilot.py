"""從官方 dataset/minif2f.jsonl 用固定種子抽 10 題，只供試跑量成本。"""
import hashlib, json, random, sys

SEED = 20261011
src, dst = sys.argv[1], sys.argv[2]
raw = open(src, "rb").read()
rows = [json.loads(l) for l in raw.decode().splitlines() if l.strip()]
assert len(rows) == 244, len(rows)
picked = sorted(random.Random(SEED).sample(range(len(rows)), 10))
with open(dst, "w") as f:
    for i in picked:
        f.write(json.dumps(rows[i], ensure_ascii=False) + "\n")
json.dump({"seed": SEED, "source_sha256": hashlib.sha256(raw).hexdigest(),
           "indices": picked, "names": [rows[i]["name"] for i in picked]},
          open(dst + ".meta.json", "w"), indent=2)
print(picked, [rows[i]["name"] for i in picked])
