# JZK's-Skills-manager-beta

一个在 Codex 内调用、无需启动本地服务的 Skill 管理器。它扫描本机插件和 Skill，增量生成中文说明与功能重合判断，并把结果写入固定的离线 HTML 报告。

## 安装

把整个文件夹复制到：

```text
%USERPROFILE%\.codex\skills\JZK's-Skills-manager-beta
```

重启或刷新 Codex 后输入：

```text
请使用 `JZK's-Skills-manager-beta` 分析我的插件和 Skill 安装情况。
```

## 查看缓存报告

```text
请使用 `JZK's-Skills-manager-beta` 打开上一次的 Skill 报告，不要重新扫描。
```

## 目录

```text
JZK's-Skills-manager-beta/
├─ SKILL.md
├─ README.md
├─ scripts/
│  └─ jzk-manager.ps1
└─ report/
   ├─ index.html
   └─ catalog.js
```

运行时缓存、历史报告和备份位于 `%LOCALAPPDATA%\JZK-Skills-Manager`，不应打包进项目源码。
