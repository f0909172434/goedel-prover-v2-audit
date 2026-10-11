"""把官方 dataset/minif2f.jsonl（244 題）用固定種子打亂後切成 N 片，讓每片難度相近。
用法：make_shards.py <minif2f.jsonl> <out_dir> [N=16]"""
import hashlib, json, os, random, sys

SEED = 20261012
src, out = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 16
raw = open(src, "rb").read()
rows = [json.loads(l) for l in raw.decode().splitlines() if l.strip()]
assert len(rows) == 244, len(rows)
order = list(range(len(rows)))
random.Random(SEED).shuffle(order)
os.makedirs(out, exist_ok=True)
manifest = {"seed": SEED, "source_sha256": hashlib.sha256(raw).hexdigest(), "shards": []}
for s in range(n):
    idx = order[s::n]
    path = os.path.join(out, f"shard_{s:02d}.jsonl")
    with open(path, "w") as f:
        for i in idx:
            f.write(json.dumps(rows[i], ensure_ascii=False) + "\n")
    manifest["shards"].append({"shard": s, "audit_seed": 1000 + s, "indices": idx,
                               "names": [rows[i]["name"] for i in idx]})
assert sorted(i for sh in manifest["shards"] for i in sh["indices"]) == list(range(244))
json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=2)
print(n, "shards", [len(sh["indices"]) for sh in manifest["shards"]])
