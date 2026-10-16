---
name: jzk-skills-manager-beta
description: 盘点、缓存并管理本机 Codex 插件与 Skill。生成中文离线报告，识别功能重合，并按明确指令执行定向刷新、备份、更新或安全卸载。
---

# JZK's Skills Manager Beta

把本机 Skill 目录整理成一份可离线打开的中文报告。日常查看直接读取缓存；只有用户明确要求“分析”“更新一下”或点名刷新某个 Skill 时，才重新扫描。

## 默认数据位置

运行脚本后，用户数据写入 `%LOCALAPPDATA%\JZK-Skills-Manager`：

- `data/latest.json`：当前缓存。
- `data/inventory.json`：最近一次目录扫描结果。
- `data/history/`：每次完成报告时保存的时间戳快照。
- `reports/current/`：固定网页模板及最新 `catalog.js`。
- `backups/`：仅在用户明确要求备份时写入压缩包。

这些内容不属于 Skill 源码。复制或分享本 Skill 时，不要携带上述目录。

## 意图路由

### 仅查看

当用户说“查看报告”“打开 Skill 报告”或类似表达：

1. 不扫描目录，不读取全部 `SKILL.md`。
2. 若缓存存在，运行请运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Open
```

3. 若缓存不存在，再说明需要首次分析，并执行完整分析流程。

### 完整分析或更新一下

当用户说“请使用 `JZK's-Skills-manager-beta` 分析我的插件和 Skill 安装情况”“更新一下”或明确要求重新扫描：

1. 运行目录扫描：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Inventory
```

2. 读取脚本返回的 `inventory.json`。只处理其中 `pending` 列出的新增或内容已变化条目；未变化条目沿用 `latest.json` 的中文简介、分类和重合判断。
3. 对每个待处理条目读取其 `SKILL.md` 全文，生成：
   - `summaryZh`：简体中文，50字以内，直接说明它能完成什么；
   - `category`：一个稳定的中文功能分类；
   - `functions`：1—5个简短功能词；
   - `overlaps`：仅列真正共享核心输入、主要处理过程和主要输出的 Skill 名称；
   - `difference`：若有重合，用一句话说明分工差异；无重合留空。
4. 不要因为名称里同时出现 paper、figure、research 等宽泛词就判定撞车。至少同时比较目标任务、输入、工作过程和输出。
5. 将增量结果保存为 UTF-8 JSON 数组，示例：

```json
[
  {
    "path": "C:\\Users\\name\\.codex\\skills\\example\\SKILL.md",
    "summaryZh": "把研究数据整理成可投稿的静态图表",
    "category": "科研绘图",
    "functions": ["数据检查", "图形设计", "导出成图"],
    "overlaps": ["another-figure-skill"],
    "difference": "更偏向投稿级静态图，而非探索式分析"
  }
]
```

6. 完成缓存和网页报告：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Finalize -EnrichmentPath "增量结果.json"
```

7. 告诉用户本次新增、变化、失效和复用缓存的数量，并提供报告路径。

### 定向刷新

当用户只点名一两个 Skill 时，在 Inventory 命令后增加 `-TargetName`。只读取返回的待处理条目，不重写其他缓存。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Inventory -TargetName "skill-name"
```

### 备份

只有用户明确要求时执行。先用报告中的名称或完整路径定位目标，再运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Backup -TargetName "skill-name"
```

### 更新

只更新同时满足以下条件的条目：已经安装在 Codex/Agents 目录、存在本地 Git 仓库、远程地址为 GitHub。自建目录、只有网页链接或存在未提交改动时停止更新，不覆盖内容。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Update -TargetName "skill-name"
```

用户要求“更新前备份”时增加 `-BackupFirst`。更新后只对目标执行定向刷新。

### 删除

删除分两步。第一步只生成影响清单：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action RemovePlan -TargetName "skill-name"
```

如果目录包含多个 `SKILL.md`，必须把所有受影响的母子 Skill 列给用户并取得确认。确认后使用上一步返回的令牌：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\jzk-manager.ps1 -Action Remove -ConfirmToken "令牌"
```

脚本将目标移入 Windows 回收站，不做永久删除。完成后定向刷新报告。

## 报告规则

- 名称、目录创建时间、所属仓库、功能分类均可排序。
- 能确认 GitHub 地址时，名称显示为超链接。
- 红色感叹号只标记高可能功能重合。
- 失效时间表示“第一次扫描到目录已不存在”的时间。
- `本地目录创建时间`只是文件系统记录，不改写成发布日期或安装日志。
- 网页只展示与排序，不在页面中执行更新、删除或备份。
