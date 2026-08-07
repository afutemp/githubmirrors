#!/usr/bin/env bash
# afumirrors 同步脚本
# 读取 catalog.toml，把每个镜像的指定引用浅克隆为纯文件目录（无 git 历史）。
# 用法: ./bin/sync.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/catalog.toml"
MIRRORS="$ROOT/mirrors"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

[ -f "$CATALOG" ] || { echo "缺少 $CATALOG" >&2; exit 1; }

# 同步单个引用: sync_ref <name> <source> <ref> <type(branches|tags)>
sync_ref() {
  local name="$1" source="$2" ref="$3" type="$4"
  local target="$MIRRORS/$name/$type/$ref"
  local tmp; tmp="$(mktemp -d)"
  echo "  · $type/$ref …"
  git clone --quiet --depth 1 --branch "$ref" "$source" "$tmp"
  rm -rf "$tmp/.git"            # 砍掉历史，只留文件
  rm -rf "$target"              # 先清空，避免残留已删除的文件
  mkdir -p "$target"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$tmp/" "$target/"
  else
    cp -a "$tmp/." "$target/"
  fi
  rm -rf "$tmp"
}

# 用 python 解析 catalog -> "name<TAB>source<TAB>branch<TAB>tag1,tag2"
mapfile -t ENTRIES < <(python3 - "$CATALOG" <<'PY'
import sys, tomllib
data = tomllib.load(open(sys.argv[1], "rb"))
for m in data.get("mirror", []):
    print("\t".join([
        m["name"], m["source"], m.get("branch", "main"),
        ",".join(m.get("tags", []) or []),
    ]))
PY
)

[ "${#ENTRIES[@]}" -gt 0 ] || { echo "catalog 为空" >&2; exit 1; }

INDEX_ROWS=()

for line in "${ENTRIES[@]}"; do
  IFS=$'\t' read -r name source branch tags <<<"$line"
  echo "▸ $name  ($source)"
  mkdir -p "$MIRRORS/$name/branches" "$MIRRORS/$name/tags"

  sync_ref "$name" "$source" "$branch" "branches"
  refs="branches/$branch"

  if [ -n "$tags" ]; then
    IFS=',' read -ra TAGARR <<<"$tags"
    for t in "${TAGARR[@]}"; do
      [ -n "$t" ] || continue
      sync_ref "$name" "$source" "$t" "tags"
      refs+=", tags/$t"
    done
  fi

  # 每个镜像的元数据
  {
    echo "# $name"
    echo
    echo "- 原始仓库: $source"
    echo "- 同步引用: $refs"
    echo "- 同步时间(UTC): $NOW"
  } > "$MIRRORS/$name/SOURCE.md"

  INDEX_ROWS+=("$name|$source|$refs")
done

# 重新生成根 README.md（镜像索引表由脚本维护）
python3 - "$ROOT" "${INDEX_ROWS[@]}" <<'PY'
import sys
root, *rows = sys.argv[1:]   # argv[0] 是 "-"（stdin 模式占位），跳过
def short(url):
    return url.rstrip("/").replace("https://github.com/", "").replace(".git", "")
lines = ["| 镜像 | 来源 | 同步引用 |", "|---|---|---|"]
for r in rows:
    name, source, refs = r.split("|", 2)
    lines.append(f"| `{name}` | {short(source)} | {refs} |")
table = "\n".join(lines)
readme = f"""# afumirrors

第三方 GitHub 仓库的文件镜像集合。**仅保留文件，不含原始 git 历史。**

## 目录约定

```
mirrors/<owner-repo>/        # 一个镜像 = 一个目录，命名保留来源
├── SOURCE.md                # 来源与同步时间（脚本生成）
├── branches/<分支>/         # 分支快照，纯文件
└── tags/<标签>/             # 标签快照，纯文件
```

## 添加 / 更新镜像

1. 在 `catalog.toml` 追加一段 `[[mirror]]`（name / source / branch / tags）
2. 运行 `./bin/sync.sh`

## 镜像索引

{table}
"""
open(f"{root}/README.md", "w", encoding="utf-8").write(readme)
PY

echo "✓ 完成，共 ${#ENTRIES[@]} 个镜像"
