# 离线词典构建

源码仓库不提交生成后的 `Resources/App/ecdict.sqlite3`，因为包含近义词后的文件约 131 MiB，超过 GitHub 100 MiB 单文件限制。GitHub Release 的应用安装包已经包含完整数据库；只有从源码构建时才需要本页步骤。

## 数据来源与许可

词典数据来自 [ECDICT](https://github.com/skywind3000/ECDICT)。请阅读上游许可证，以及本仓库中的：

- `Resources/App/ThirdPartyLicenses/ECDICT-LICENSE.txt`
- `Resources/App/ThirdPartyLicenses/NOTICE.txt`

本项目没有使用 `lemma.en.txt`。词形索引只从 `ecdict.csv` 的 `exchange` 字段生成。

相关近义词来自 [Princeton WordNet 3.1](https://wordnet.princeton.edu/)。应用只保留 ECDICT 已收录词之间的词义关系，不重新分发 WordNet 原始数据文件；许可和来源记录见：

- `Resources/App/ThirdPartyLicenses/WORDNET-LICENSE.txt`
- `Resources/App/ThirdPartyLicenses/NOTICE.txt`

## 生成数据库

1. 从 ECDICT 上游取得 `ecdict.csv`。
2. 从 Princeton 官方下载 `wn3.1.dict.tar.gz` 并解压，取得其中的 `dict` 目录。
3. 在项目根目录运行：

```bash
python3 scripts/build-dictionary.py \
  /absolute/path/to/ecdict.csv \
  Resources/App/ecdict.sqlite3 \
  --wordnet-dict /absolute/path/to/wordnet/dict
```

脚本会创建英文主词条、词形映射、汉英反向索引和离线近义词表。生成后运行完整检查：

```bash
./scripts/check.sh
```

## 刷新汉英反向索引

已有数据库只需补建或刷新中文索引时运行：

```bash
python3 scripts/add-chinese-index.py Resources/App/ecdict.sqlite3
```

数据库是构建产物，已由 `.gitignore` 排除，请勿强制提交到 GitHub。

## 为已有数据库补充近义词

不重建 ECDICT 主表时，可单独运行：

```bash
python3 scripts/wordnet_synonyms.py \
  Resources/App/ecdict.sqlite3 \
  /absolute/path/to/wordnet/dict
```

脚本只保留 ECDICT 中也存在的候选词，并按 WordNet 常见词义与 ECDICT 常见度排序。旧数据库没有 `synonyms` 表时，客户端会自动隐藏近义词区域，不影响其他功能。
