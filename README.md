# afumirrors

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

| 镜像 | 来源 | 同步引用 |
|---|---|---|
| `mattpocock-skills` | mattpocock/skills | branches/main |
| `anthropics-skills` | anthropics/skills | branches/main |
