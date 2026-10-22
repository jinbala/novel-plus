<#
.SYNOPSIS
  同步 novel-plus 上游（201206030/novel-plus），并重新生成 UPSTREAM-UPDATES.md。

.DESCRIPTION
  - 自动添加/复用 upstream 远端，拉取上游分支（只取 commit/tree，不下载 blob，速度快）
  - 以「分叉点」和「上次同步记录」两个基准统计变化
  - 生成一份中文汇总文档：同步结论 / 本次新增 / 版本时间线 / 变化主线 /
    快速上手 / 最近更新明细 / 文件变化统计 / 全量提交清单 / 再次同步方法
  - 每次运行都会把同步记录写入 tools/.upstream-state.json，下次运行据此显示"本次新增"

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\upstream-digest.ps1
  powershell -ExecutionPolicy Bypass -File tools\upstream-digest.ps1 -OutFile docs/upstream.md
#>
[CmdletBinding()]
param(
  [string]$UpstreamUrl = "https://github.com/201206030/novel-plus.git",
  [string]$UpstreamBranch = "master",
  [string]$OutFile = "docs/UPSTREAM-UPDATES.md"
)

$ErrorActionPreference = "Continue"

function Invoke-Git {
  param([string[]]$Arguments, [switch]$Quiet)
  $out = & git @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') 失败：`n$($out -join "`n")" }
  return $out
}

$repo = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0) { throw "当前目录不在 Git 仓库内" }
Set-Location $repo

# --- 1. 远端准备与拉取 -------------------------------------------------------
$remotes = & git remote
if ($remotes -notcontains "upstream") { & git remote add upstream $UpstreamUrl | Out-Null }
& git fetch --no-tags --filter=blob:none upstream $UpstreamBranch 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { throw "拉取上游失败：git fetch 返回 $LASTEXITCODE" }

$tip  = (& git rev-parse "upstream/$UpstreamBranch").Trim()
$head = (& git rev-parse HEAD).Trim()
$base = (& git merge-base HEAD "upstream/$UpstreamBranch").Trim()
if (-not $base) { throw "找不到与上游的公共祖先" }
$currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()

$behind = [int](& git rev-list --count "$base..upstream/$UpstreamBranch")
$ahead  = [int](& git rev-list --count "upstream/$UpstreamBranch..HEAD")
& git merge-base --is-ancestor HEAD "upstream/$UpstreamBranch" | Out-Null
$isAncestor = ($LASTEXITCODE -eq 0)

$baseInfo = (& git log -1 --format="%h|%ad|%an|%s" --date=short $base) -split '\|', 4
$tipInfo  = (& git log -1 --format="%h|%ad|%an|%s" --date=short $tip)  -split '\|', 4
$now      = Get-Date -Format "yyyy-MM-dd HH:mm"
$spanDays = [int](((Get-Date $tipInfo[1]) - (Get-Date $baseInfo[1])).TotalDays)

# --- 2. 提交清单 -------------------------------------------------------------
$rawCommits = & git log --format="%h`t%ad`t%an`t%s" --date=short "$base..upstream/$UpstreamBranch"
$commits = foreach ($line in $rawCommits) {
  $parts = $line -split "`t", 4
  if ($parts.Count -lt 4) { continue }
  $subject = $parts[3]
  $type = "other"
  if ($subject -match '^([a-zA-Z]+)(\([^)]*\))?!?:') { $type = $matches[1].ToLower() }
  elseif ($subject -match '^([a-zA-Z]+):') { $type = $matches[1].ToLower() }
  [pscustomobject]@{
    Hash    = $parts[0]
    Date    = $parts[1]
    Author  = $parts[2]
    Subject = $subject
    Type    = $type
    Month   = $parts[1].Substring(0, 7)
  }
}
$typeOrder = @("feat","fix","perf","build","chore","refactor","docs","ci","style","revert","add","other")
$typeStats = $commits | Group-Object Type | Sort-Object Count -Descending

# --- 3. 版本时间线 -----------------------------------------------------------
$mergedTags = & git tag --merged "upstream/$UpstreamBranch"
$timeline = foreach ($t in $mergedTags) {
  $d = (& git log -1 --format="%ad" --date=short $t)
  if ([datetime]$d -lt [datetime]$baseInfo[1]) { continue }
  [pscustomobject]@{ Version = $t; Date = $d }
}
$timeline = @($timeline | Sort-Object Date, Version)
$forkVersion = (& git tag --merged $base --sort=-creatordate 2>$null | Select-Object -First 1)
if (-not $forkVersion) { $forkVersion = "(无标签)" }

# --- 4. 文件变化统计（按顶层目录） --------------------------------------------
$nameStatus = & git diff --no-renames --name-status $base $tip
$fileStats = foreach ($line in $nameStatus) {
  $p = $line -split "`t"
  if ($p.Count -lt 2) { continue }
  $top = ($p[1] -split '/')[0] -replace '"', ''
  [pscustomobject]@{ Status = $p[0].Substring(0,1); Top = $top }
}
$moduleStats = $fileStats | Group-Object Top | Sort-Object Count -Descending |
  Select-Object @{n="Module";e={$_.Name}}, @{n="Total";e={$_.Count}},
    @{n="Added";e={@($_.Group | Where-Object Status -eq "A").Count}},
    @{n="Modified";e={@($_.Group | Where-Object Status -eq "M").Count}},
    @{n="Deleted";e={@($_.Group | Where-Object Status -eq "D").Count}}

# --- 5. 上次同步状态 ---------------------------------------------------------
$statePath = Join-Path $repo "tools\.upstream-state.json"
$lastTip = $null; $lastDate = $null
if (Test-Path $statePath) {
  $state = Get-Content $statePath -Raw | ConvertFrom-Json
  $lastTip = $state.lastSyncedTip
  $lastDate = $state.syncedAt
}
$newCommits = @()
if ($lastTip -and ($lastTip -ne $tip)) {
  & git merge-base --is-ancestor $lastTip $tip | Out-Null
  $ok = ($LASTEXITCODE -eq 0)
  if ($ok) {
    $rawNew = & git log --format="%h`t%ad`t%an`t%s" --date=short "$lastTip..$tip"
    $newCommits = @($rawNew | ForEach-Object { $p = $_ -split "`t", 4; if ($p.Count -ge 4) { [pscustomobject]@{ Hash=$p[0]; Date=$p[1]; Subject=$p[3] } } })
  }
}

# --- 6. 生成 Markdown --------------------------------------------------------
$sb = [System.Text.StringBuilder]::new()
$md = {
  param([string]$Text)
  [void]$sb.AppendLine($Text)
}

& $md "# novel-plus 上游同步速览"
& $md ""
& $md "> 自动生成：$now ｜ 数据来源：``$UpstreamUrl``（分支 ``$UpstreamBranch``）"
& $md "> 重新生成：``powershell -ExecutionPolicy Bypass -File tools\upstream-digest.ps1``"
& $md ""
& $md "## 一、同步结论"
& $md ""
& $md "| 项目 | 值 |"
& $md "| --- | --- |"
& $md "| 你的分支 / 提交 | ``$currentBranch`` / ``$($head.Substring(0,7))`` |"
& $md "| 分叉点（merge-base） | ``$($baseInfo[0])`` $($baseInfo[1]) — $($baseInfo[3]) |"
& $md "| 分叉点最近版本 | ``$forkVersion`` |"
& $md "| 上游最新 | ``$($tipInfo[0])`` $($tipInfo[1]) — $($tipInfo[3]) |"
& $md "| 上游新增提交 | **$behind** 条 |"
& $md "| 你的独有提交 | $ahead 条 |"
& $md "| 你落后时间跨度 | $spanDays 天（约 $([math]::Round($spanDays/365,1)) 年） |"
$ffHint = if ($isAncestor) { "可以：``git merge --ff-only upstream/$UpstreamBranch``" } else { "不可以，存在分叉，需要 merge/rebase" }
& $md "| 能否直接快进 | $ffHint |"
& $md ""
& $md "结论：你的仓库停在 **$forkVersion** 附近（$($baseInfo[1])），上游已经走到 **$($tipInfo[1])** 的 ``$($timeline[-1].Version)``（如无标签则看最新提交），中间隔了 $behind 条提交、$($timeline.Count) 个版本。技术栈和功能规模都发生了代际变化，推荐**重新以最新代码为目标**上手，而不是在 2022 年的代码上打补丁。"
& $md ""

# 本次新增
& $md "## 二、本次同步新增"
& $md ""
if ($newCommits.Count -gt 0) {
  & $md "上次同步：``$($lastTip.Substring(0,7))``（$lastDate）→ 本次：``$($tip.Substring(0,7))``，新增 **$($newCommits.Count)** 条提交。"
  & $md ""
  & $md "| 日期 | 提交 | 说明 |"
  & $md "| --- | --- | --- |"
  foreach ($c in $newCommits) { & $md "| $($c.Date) | ``$($c.Hash)`` | $($c.Subject) |" }
} elseif (-not $lastTip) {
  & $md "首次运行：本次按分叉点统计，共 **$behind** 条上游提交（见第七节全量清单）。"
} else {
  & $md "已是最新：上游 ``$($tip.Substring(0,7))`` 与上次同步一致，没有新提交。"
}
& $md ""

# 版本时间线
& $md "## 三、版本时间线（$($timeline[0].Date) → $($timeline[-1].Date)）"
& $md ""
& $md "| 版本 | 日期 |"
& $md "| --- | --- |"
foreach ($t in $timeline) { & $md "| ``$($t.Version)`` | $($t.Date) |" }
& $md ""

# 变化主线
& $md "## 四、变化主线（这几年项目做了什么）"
& $md ""
& $md "### 1. 技术栈升级（影响最大）"
& $md ""
& $md "- **Java 8 → Java 21**，**Spring Boot 2.1.8 → 3.4.0**（见 ``pom.xml``），意味着 Java 8 的编译/运行方式已经不再适用"
& $md "- 引入 **Spring AI**：AI 扩写/缩写/续写/润色、AI 生成封面、AI 长篇创作助手"
& $md "- 引入 **Sharding-JDBC** 做代码层分库分表，新增外部配置 ``config/shardingsphere-jdbc.yml``"
& $md "- 新增 **Docker** 构建与 **GitHub Actions** 发布流程（``.github/workflows/release.yml``、各模块 ``src/main/build/docker``）"
& $md "- 配置外置化：各模块 ``src/main/build/config/application.yml`` 与启动脚本（``bin/novel-front.sh`` 等）"
& $md ""
& $md "### 2. 功能版图"
& $md ""
& $md "- **AI 创作**：章节编辑器 AI 编辑、AI 封面、AI 长篇创作助手（创意→书名→方案→逐章→校验修订→确认保存/断点续写）"
& $md "- **阅读端**：书单、书架、段落评论、阅读主题、多模板切换、2026 新版 UI"
& $md "- **前端模板**：新增 ``templates`` 模块作为模板资源（677+ 文件变化）"
& $md "- **平台能力**：会员充值、订阅、新闻、实时统计、爬虫采集规则与编辑"
& $md "- **跨端**：v6.0.0 提交了跨端客户端相关接口（``feat(api)``）"
& $md ""
& $md "### 3. 数据与部署"
& $md ""
& $md "- ``doc/sql`` 新增 12 个增量脚本（``20230413.sql`` → ``20261020.sql``），并更新全量脚本 ``novel_plus.sql``、测试数据 ``novel_plus_data.sql.zip``，新增 ``Dockerfile``"
& $md "- 生产环境强制要求 ``JWT_SECRET``（≥64 字节随机值），未设置时 ``prod`` 启动会直接失败"
& $md ""
& $md "### 4. 提交构成（分叉点至今 $behind 条）"
& $md ""
& $md "| 类型 | 数量 |"
& $md "| --- | --- |"
foreach ($s in $typeStats) { & $md "| $($s.Name) | $($s.Count) |" }
& $md ""

# 快速上手
& $md "## 五、快速上手（基于上游最新代码）"
& $md ""
& $md "### 环境"
& $md ""
& $md "- **JDK 21**（必须，pom 里 ``java.version=21``）、Maven 3.9+"
& $md "- **MySQL 8.x**、**Redis**；按需：Elasticsearch、阿里云 OSS、支付/短信/AI 等第三方服务"
& $md ""
& $md "### 项目结构"
& $md ""
& $md '```'
& $md "novel-plus -- 父工程"
& $md "├── novel-common -- 通用模块"
& $md "├── novel-front  -- 前台门户 & 作家后台"
& $md "├── novel-crawl  -- 爬虫"
& $md "├── novel-admin  -- 管理后台"
& $md "└── templates    -- 前端模版"
& $md '```'
& $md ""
& $md "### 数据库初始化（按 ``doc/sql/readme.md``）"
& $md ""
& $md "1. 新建库（utf8mb4）并导入表结构 + 初始数据：直接执行 ``doc/sql/novel_plus.sql``；或执行 ``novel_plus_data.sql``（含测试小说数据）后再依次执行所有 ``2026*.sql`` 增量"
& $md "2. 之后每次升级：按日期顺序执行新增的 ``yyyyMMdd.sql`` 增量脚本"
& $md ""
& $md "### 关键配置"
& $md ""
& $md "- 各模块 ``src/main/resources/application-dev.yml`` / ``application-prod.yml`` / ``application-common-*.yml``：数据源、Redis、端口"
& $md "- ``novel-front`` 额外有 ``application-alipay.yml``（支付）、``application-oss.yml``（对象存储）、``application-website.yml``（站点）"
& $md "- AI 功能：``spring.ai.openai.*``（默认接硅基流动，需自备 API key；模型为免费 DeepSeek-R1 蒸馏版 + Kolors 生图）"
& $md "- 生产：启动前把 ``JWT_SECRET`` 设为至少 64 字节的随机串（如 ``openssl rand -base64 64`` 去掉末尾换行），留空时 prod 环境会直接终止启动"
& $md ""
& $md "### 构建与启动"
& $md ""
& $md '```bash'
& $md "mvn clean package -DskipTests        # 根目录打包（4 个模块）"
& $md "# 或使用各模块自带脚本/镜像："
& $md "#   novel-front/src/main/build/scripts/novel-front.sh start"
& $md "#   novel-front/src/main/build/docker/Dockerfile"
& $md '```'
& $md ""
& $md "### 官方资料"
& $md ""
& $md "- 官网 / 演示站：https://novel.xxyopen.com"
& $md "- 安装教程：https://docs.xxyopen.com/course/novelplus/1.html"
& $md "- 微服务版（novel-cloud）：https://github.com/201206030/novel-cloud"
& $md ""

# 最近更新明细
& $md "## 六、最近 12 个月更新明细"
& $md ""
$recentFrom = (Get-Date $tipInfo[1]).AddMonths(-12)
$recent = $commits | Where-Object { [datetime]$_.Date -ge $recentFrom }
$recentByMonth = $recent | Group-Object Month | Sort-Object Name -Descending
if (-not $recentByMonth) { & $md "（最近 12 个月无提交）" }
foreach ($m in $recentByMonth) {
  & $md "### $($m.Name)（$($m.Count) 条）"
  & $md ""
  foreach ($c in ($m.Group | Sort-Object Date -Descending)) {
    & $md "- ``$($c.Date)`` ``$($c.Hash)`` $($c.Subject)"
  }
  & $md ""
}

# 全量清单
& $md "## 七、全量提交清单（自 $($baseInfo[1]) 起，共 $behind 条）"
& $md ""
foreach ($c in ($commits | Sort-Object Date -Descending)) {
  $tag = if ($typeOrder -contains $c.Type) { $c.Type } else { "" }
  $prefix = if ($tag) { "[$tag] " } else { "" }
  & $md "- ``$($c.Date)`` ``$($c.Hash)`` $prefix$($c.Subject)"
}
& $md ""

# 文件统计
& $md "## 八、文件变化统计（分叉点 → 上游最新）"
& $md ""
& $md "| 目录/模块 | 变化文件 | 新增 | 修改 | 删除 |"
& $md "| --- | --- | --- | --- | --- |"
foreach ($s in $moduleStats) { & $md "| $($s.Module) | $($s.Total) | $($s.Added) | $($s.Modified) | $($s.Deleted) |" }
& $md ""

# 再次同步
& $md "## 九、以后怎么再同步"
& $md ""
& $md '```powershell'
& $md "# 1) 预览上游新增（不改变你的工作区）"
& $md "git fetch --no-tags --filter=blob:none upstream master"
& $md "git log --oneline HEAD..upstream/master"
& $md ""
& $md "# 2) 重新生成本文档（会自动更新 tools/.upstream-state.json）"
& $md "powershell -ExecutionPolicy Bypass -File tools\upstream-digest.ps1"
& $md ""
& $md "# 3) 确认没问题后，把你的分支快进到上游（当前分支是上游的祖先时可用）"
& $md "git merge --ff-only upstream/master"
& $md '```'
& $md ""
& $md "> 提示：``--filter=blob:none`` 只取提交与目录树，不下载文件内容，几秒即可完成；等你真要合并/构建时再按需拉取文件。"
& $md ""

# --- 7. 写入 ----------------------------------------------------------------
$outPath = Join-Path $repo $OutFile
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), $utf8)

$stateDir = Join-Path $repo "tools"
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
$stateObj = [ordered]@{ lastSyncedTip = $tip; syncedAt = $now; base = $base; upstream = $UpstreamUrl; branch = $UpstreamBranch }
[System.IO.File]::WriteAllText($statePath, ($stateObj | ConvertTo-Json), $utf8)

Write-Host "已生成：$outPath"
Write-Host "分叉点 $($baseInfo[0]) → 上游 $($tipInfo[0])，新增 $behind 条提交；本次新增 $($newCommits.Count) 条"
