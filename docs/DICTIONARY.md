# 离线词典构建

源码仓库不提交生成后的 `Resources/App/ecdict.sqlite3`，因为文件约 108 MiB，超过 GitHub 100 MiB 单文件限制。GitHub Release 的应用安装包已经包含完整数据库；只有从源码构建时才需要本页步骤。

## 数据来源与许可

词典数据来自 [ECDICT](https://github.com/skywind3000/ECDICT)。请阅读上游许可证，以及本仓库中的：

- `Resources/App/ThirdPartyLicenses/ECDICT-LICENSE.txt`
- `Resources/App/ThirdPartyLicenses/NOTICE.txt`

本项目没有使用 `lemma.en.txt`。词形索引只从 `ecdict.csv` 的 `exchange` 字段生成。

## 生成数据库

1. 从 ECDICT 上游取得 `ecdict.csv`。
2. 在项目根目录运行：

```bash
python3 scripts/build-dictionary.py /absolute/path/to/ecdict.csv Resources/App/ecdict.sqlite3
```

脚本会创建英文主词条、词形映射和汉英反向索引。生成后运行完整检查：

```bash
./scripts/check.sh
```

## 刷新汉英反向索引

已有数据库只需补建或刷新中文索引时运行：

```bash
python3 scripts/add-chinese-index.py Resources/App/ecdict.sqlite3
```

数据库是构建产物，已由 `.gitignore` 排除，请勿强制提交到 GitHub。
