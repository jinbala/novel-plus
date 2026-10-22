# novel-plus 上游同步速览

> 自动生成：2026-10-22 00:50 ｜ 数据来源：`https://github.com/201206030/novel-plus.git`（分支 `master`）
> 重新生成：`powershell -ExecutionPolicy Bypass -File tools\upstream-digest.ps1`

## 一、同步结论

| 项目 | 值 |
| --- | --- |
| 你的分支 / 提交 | `develop_xxy` / `906e776` |
| 分叉点（merge-base） | `906e7762` 2022-01-17 — Merge github.com:201206030/novel-plus into develop_xxy |
| 分叉点最近版本 | `v3.6.0` |
| 上游最新 | `e8daac0a` 2026-10-21 — feat(api): 提交跨端客户端相关接口 |
| 上游新增提交 | **358** 条 |
| 你的独有提交 | 0 条 |
| 你落后时间跨度 | 1738 天（约 4.8 年） |
| 能否直接快进 | 可以：`git merge --ff-only upstream/master` |

结论：你的仓库停在 **v3.6.0** 附近（2022-01-17），上游已经走到 **2026-10-21** 的 `v6.0.0`（如无标签则看最新提交），中间隔了 358 条提交、29 个版本。技术栈和功能规模都发生了代际变化，推荐**重新以最新代码为目标**上手，而不是在 2022 年的代码上打补丁。

## 二、本次同步新增

首次运行：本次按分叉点统计，共 **358** 条上游提交（见第七节全量清单）。

## 三、版本时间线（2022-07-14 → 2026-10-21）

| 版本 | 日期 |
| --- | --- |
| `v3.6.1` | 2022-07-14 |
| `v3.6.2` | 2022-07-15 |
| `v4.0.0` | 2023-04-15 |
| `4.1.0` | 2023-04-18 |
| `4.2.0` | 2023-10-12 |
| `v4.3.0-RC1` | 2023-10-21 |
| `v4.4.0` | 2024-11-02 |
| `v5.0.0` | 2025-03-17 |
| `v5.0.1` | 2025-03-20 |
| `v5.1.0` | 2025-03-23 |
| `v5.1.1` | 2025-04-27 |
| `v5.1.2` | 2025-05-12 |
| `v5.1.3` | 2025-05-13 |
| `v5.1.4` | 2025-06-19 |
| `v5.1.5` | 2025-06-21 |
| `v5.2.0` | 2025-07-12 |
| `v5.2.1` | 2025-07-14 |
| `v5.2.2` | 2025-07-17 |
| `v5.2.3` | 2025-07-19 |
| `v5.2.4` | 2025-07-25 |
| `v5.2.5` | 2025-08-14 |
| `v5.2.6` | 2025-10-04 |
| `v5.3.0` | 2025-10-26 |
| `v5.3.1` | 2026-05-16 |
| `v5.3.2` | 2026-05-17 |
| `v5.3.3` | 2026-05-17 |
| `v5.4.0` | 2026-10-13 |
| `v5.5.0` | 2026-10-19 |
| `v6.0.0` | 2026-10-21 |

## 四、变化主线（这几年项目做了什么）

### 1. 技术栈升级（影响最大）

- **Java 8 → Java 21**，**Spring Boot 2.1.8 → 3.4.0**（见 `pom.xml`），意味着 Java 8 的编译/运行方式已经不再适用
- 引入 **Spring AI**：AI 扩写/缩写/续写/润色、AI 生成封面、AI 长篇创作助手
- 引入 **Sharding-JDBC** 做代码层分库分表，新增外部配置 `config/shardingsphere-jdbc.yml`
- 新增 **Docker** 构建与 **GitHub Actions** 发布流程（`.github/workflows/release.yml`、各模块 `src/main/build/docker`）
- 配置外置化：各模块 `src/main/build/config/application.yml` 与启动脚本（`bin/novel-front.sh` 等）

### 2. 功能版图

- **AI 创作**：章节编辑器 AI 编辑、AI 封面、AI 长篇创作助手（创意→书名→方案→逐章→校验修订→确认保存/断点续写）
- **阅读端**：书单、书架、段落评论、阅读主题、多模板切换、2026 新版 UI
- **前端模板**：新增 `templates` 模块作为模板资源（677+ 文件变化）
- **平台能力**：会员充值、订阅、新闻、实时统计、爬虫采集规则与编辑
- **跨端**：v6.0.0 提交了跨端客户端相关接口（`feat(api)`）

### 3. 数据与部署

- `doc/sql` 新增 12 个增量脚本（`20230413.sql` → `20261020.sql`），并更新全量脚本 `novel_plus.sql`、测试数据 `novel_plus_data.sql.zip`，新增 `Dockerfile`
- 生产环境强制要求 `JWT_SECRET`（≥64 字节随机值），未设置时 `prod` 启动会直接失败

### 4. 提交构成（分叉点至今 358 条）

| 类型 | 数量 |
| --- | --- |
| other | 121 |
| fix | 67 |
| feat | 58 |
| perf | 46 |
| build | 24 |
| chore | 15 |
| docs | 10 |
| ci | 7 |
| refactor | 5 |
| revert | 2 |
| style | 2 |
| add | 1 |

## 五、快速上手（基于上游最新代码）

### 环境

- **JDK 21**（必须，pom 里 `java.version=21`）、Maven 3.9+
- **MySQL 8.x**、**Redis**；按需：Elasticsearch、阿里云 OSS、支付/短信/AI 等第三方服务

### 项目结构

```
novel-plus -- 父工程
├── novel-common -- 通用模块
├── novel-front  -- 前台门户 & 作家后台
├── novel-crawl  -- 爬虫
├── novel-admin  -- 管理后台
└── templates    -- 前端模版
```

### 数据库初始化（按 `doc/sql/readme.md`）

1. 新建库（utf8mb4）并导入表结构 + 初始数据：直接执行 `doc/sql/novel_plus.sql`；或执行 `novel_plus_data.sql`（含测试小说数据）后再依次执行所有 `2026*.sql` 增量
2. 之后每次升级：按日期顺序执行新增的 `yyyyMMdd.sql` 增量脚本

### 关键配置

- 各模块 `src/main/resources/application-dev.yml` / `application-prod.yml` / `application-common-*.yml`：数据源、Redis、端口
- `novel-front` 额外有 `application-alipay.yml`（支付）、`application-oss.yml`（对象存储）、`application-website.yml`（站点）
- AI 功能：`spring.ai.openai.*`（默认接硅基流动，需自备 API key；模型为免费 DeepSeek-R1 蒸馏版 + Kolors 生图）
- 生产：启动前把 `JWT_SECRET` 设为至少 64 字节的随机串（如 `openssl rand -base64 64` 去掉末尾换行），留空时 prod 环境会直接终止启动

### 构建与启动

```bash
mvn clean package -DskipTests        # 根目录打包（4 个模块）
# 或使用各模块自带脚本/镜像：
#   novel-front/src/main/build/scripts/novel-front.sh start
#   novel-front/src/main/build/docker/Dockerfile
```

### 官方资料

- 官网 / 演示站：https://novel.xxyopen.com
- 安装教程：https://docs.xxyopen.com/course/novelplus/1.html
- 微服务版（novel-cloud）：https://github.com/201206030/novel-cloud

## 六、最近 12 个月更新明细

### 2026-10（53 条）

- `2026-10-21` `75b1f31a` fix: 生产环境默认使用 prod 配置
- `2026-10-21` `5f300e45` fix(novel-admin): 修复邀请码校验问题
- `2026-10-21` `8ed4f055` perf(novel-front): 优化作者注册页面
- `2026-10-21` `7201d1ec` fix(novel-admin): 增加图片上传外部配置
- `2026-10-21` `4787f113` refactor: 重构管理后台
- `2026-10-21` `79db1b80` fix(novel-common): prod 环境增加图片上传配置
- `2026-10-21` `4bfc9031` fix(novel-admin): 修改管理后台生产环境端口号
- `2026-10-21` `62b2507e` perf(novel-front): 优化昵称显示
- `2026-10-21` `c1f59921` 模版更新
- `2026-10-21` `537027cd` v6.0.0 发布
- `2026-10-21` `e8daac0a` feat(api): 提交跨端客户端相关接口
- `2026-10-21` `55f59632` 模版更新
- `2026-10-21` `23ec63ef` feat(novel-front): 会员注册自动生成初始随机昵称
- `2026-10-21` `b0c3f4d1` Revert "feat(novel-front): 会员注册自动生成初始随机昵称"
- `2026-10-21` `a2db4a6b` Update README.md
- `2026-10-20` `916f5d17` fix(mobile): 修复小说筛选页书籍列表分页跳转的问题
- `2026-10-20` `f276eba3` fix(mobile): 修复小说筛选页初始状态未选中的问题
- `2026-10-20` `da024491` feat(mobile): 完善移动端个人中心
- `2026-10-20` `2bd93602` perf: 优化作家后台页面UI
- `2026-10-20` `15716638` feat(author): 新增AI创作助手
- `2026-10-20` `2c92b106` feat(mobile): 新增消息系统
- `2026-10-19` `3263048c` feat(mobile): 新增小说段落评论
- `2026-10-19` `864145db` v5.5.0 发布
- `2026-10-19` `170a8f4b` feat(mobile): 新增书单广场
- `2026-10-19` `2bba9682` feat: 完善移动端作品评论区
- `2026-10-19` `89902a5b` feat: 完善移动端个人中心
- `2026-10-19` `251211e8` feat(mobile): 优化移动端小说筛选页面
- `2026-10-19` `efc589a1` feat(mobile): 重新设计移动端UI
- `2026-10-19` `4a667a5c` feat(mobile): 优化移动端首页UI
- `2026-10-19` `f76455f1` fix(mobile): 修复个人中心头像上传问题
- `2026-10-19` `67e6d10d` feat(mobile): 完善移动端排行榜
- `2026-10-18` `1939677e` Require an external JWT signing secret
- `2026-10-18` `05382741` Validate production JWT secret and isolate development fallback
- `2026-10-18` `b30c5a4d` Merge pull request #138 from 28Hus/novel-plus-jwt-secret-fix
- `2026-10-17` `f75c0666` Merge branch 'develop_xxy'
- `2026-10-17` `28e93ea2` Update README.md
- `2026-10-17` `94db3dd4` Merge branch 'develop_xxy'
- `2026-10-17` `53d3ed39` Update README.md
- `2026-10-17` `dc910e53` docs: 更新SQL文件说明
- `2026-10-16` `288b3de4` feat: 首页增加统计图表
- `2026-10-16` `b813fbd3` fix(novel-crawl): 规则修复
- `2026-10-16` `b2fbdec5` Update README.md
- `2026-10-16` `87c8ce2e` 删除废弃文件
- `2026-10-13` `11b7b46c` fix(novel-crawl): 修复爬虫规则
- `2026-10-13` `3a3a8a38` docs: HTTP代理设置说明
- `2026-10-13` `e2cc9a9e` feat(mobile): 完善手机端小说检索功能
- `2026-10-13` `25c30ae7` v5.4.0 发布
- `2026-10-13` `e7cdce98` feat(novel-front): 评论敏感词过滤
- `2026-10-13` `93a44a38` Merge branch '5.4.x' into develop_xxy
- `2026-10-10` `36c082ab` perf(novel-crawl): 设置动态 User-Agent
- `2026-10-10` `e386b8f1` fix(novel-crawl): 设置默认图片
- `2026-10-10` `cfc5d894` feat(SEO): 自动生成和更新网站地图 sitemap.xml
- `2026-10-10` `f10ffa66` feat(novel-front): 作家专区增加作品完结功能

### 2026-09（1 条）

- `2026-09-04` `875f620e` Update README.md

### 2026-06（1 条）

- `2026-06-01` `d9f3f464` fix: 修复 mysql-novel-plus 镜像

### 2026-05（11 条）

- `2026-05-17` `a9a502f9` v5.3.2 发布
- `2026-05-17` `eef24cbe` 内置一批无版权的小说数据
- `2026-05-17` `d9957859` ci: 简化 Dockerfile 文件
- `2026-05-17` `24b9fe2a` fix(author): 加载小说分类
- `2026-05-17` `ebfe6c52` ci: 构建并推送 mysql-novel-plus 镜像
- `2026-05-17` `ff10e4af` Merge branch 'develop_xxy'
- `2026-05-17` `866094af` Update README.md
- `2026-05-17` `f3153587` docs: 更新 sql 文件说明
- `2026-05-17` `d63c3ee3` v5.3.3 发布
- `2026-05-16` `94b8a3a2` ci: 自动上传 Docker 镜像
- `2026-05-16` `159d0faa` v5.3.1 发布

### 2025-12（2 条）

- `2025-12-27` `0f7d81de` fix(novel-front): 修复作品评论区分页错误
- `2025-12-27` `f3f37721` Merge remote-tracking branch 'Gitee/develop_xxy' into develop_xxy

### 2025-11（1 条）

- `2025-11-09` `6fc8e963` Update README.md

### 2025-10（7 条）

- `2025-10-26` `313e73c6` v5.3.0 发布
- `2025-10-26` `01639cbd` Merge branch '5.3.x'
- `2025-10-25` `1aa86bda` chore(novel-crawl): 修改生产环境外部配置文件
- `2025-10-25` `bd12d2f2` fix(novel-admin): 修复小说推荐列表分页显示异常
- `2025-10-25` `3d1b952e` perf(novel-crawl): 优化采集监控页异常提示体验
- `2025-10-25` `6b72d485` feat(novel-admin): 新增小说下载功能
- `2025-10-24` `938ae857` feat(novel-crawl): 新增磁盘保护机制，支持邮件告警与自动熔断

## 七、全量提交清单（自 2022-01-17 起，共 358 条）

- `2026-10-21` `75b1f31a` [fix] fix: 生产环境默认使用 prod 配置
- `2026-10-21` `5f300e45` [fix] fix(novel-admin): 修复邀请码校验问题
- `2026-10-21` `8ed4f055` [perf] perf(novel-front): 优化作者注册页面
- `2026-10-21` `7201d1ec` [fix] fix(novel-admin): 增加图片上传外部配置
- `2026-10-21` `4787f113` [refactor] refactor: 重构管理后台
- `2026-10-21` `79db1b80` [fix] fix(novel-common): prod 环境增加图片上传配置
- `2026-10-21` `4bfc9031` [fix] fix(novel-admin): 修改管理后台生产环境端口号
- `2026-10-21` `62b2507e` [perf] perf(novel-front): 优化昵称显示
- `2026-10-21` `c1f59921` [other] 模版更新
- `2026-10-21` `537027cd` [other] v6.0.0 发布
- `2026-10-21` `e8daac0a` [feat] feat(api): 提交跨端客户端相关接口
- `2026-10-21` `55f59632` [other] 模版更新
- `2026-10-21` `23ec63ef` [feat] feat(novel-front): 会员注册自动生成初始随机昵称
- `2026-10-21` `b0c3f4d1` [other] Revert "feat(novel-front): 会员注册自动生成初始随机昵称"
- `2026-10-21` `a2db4a6b` [other] Update README.md
- `2026-10-20` `916f5d17` [fix] fix(mobile): 修复小说筛选页书籍列表分页跳转的问题
- `2026-10-20` `f276eba3` [fix] fix(mobile): 修复小说筛选页初始状态未选中的问题
- `2026-10-20` `da024491` [feat] feat(mobile): 完善移动端个人中心
- `2026-10-20` `2bd93602` [perf] perf: 优化作家后台页面UI
- `2026-10-20` `15716638` [feat] feat(author): 新增AI创作助手
- `2026-10-20` `2c92b106` [feat] feat(mobile): 新增消息系统
- `2026-10-19` `3263048c` [feat] feat(mobile): 新增小说段落评论
- `2026-10-19` `864145db` [other] v5.5.0 发布
- `2026-10-19` `170a8f4b` [feat] feat(mobile): 新增书单广场
- `2026-10-19` `2bba9682` [feat] feat: 完善移动端作品评论区
- `2026-10-19` `89902a5b` [feat] feat: 完善移动端个人中心
- `2026-10-19` `251211e8` [feat] feat(mobile): 优化移动端小说筛选页面
- `2026-10-19` `efc589a1` [feat] feat(mobile): 重新设计移动端UI
- `2026-10-19` `4a667a5c` [feat] feat(mobile): 优化移动端首页UI
- `2026-10-19` `f76455f1` [fix] fix(mobile): 修复个人中心头像上传问题
- `2026-10-19` `67e6d10d` [feat] feat(mobile): 完善移动端排行榜
- `2026-10-18` `1939677e` [other] Require an external JWT signing secret
- `2026-10-18` `05382741` [other] Validate production JWT secret and isolate development fallback
- `2026-10-18` `b30c5a4d` [other] Merge pull request #138 from 28Hus/novel-plus-jwt-secret-fix
- `2026-10-17` `f75c0666` [other] Merge branch 'develop_xxy'
- `2026-10-17` `28e93ea2` [other] Update README.md
- `2026-10-17` `94db3dd4` [other] Merge branch 'develop_xxy'
- `2026-10-17` `53d3ed39` [other] Update README.md
- `2026-10-17` `dc910e53` [docs] docs: 更新SQL文件说明
- `2026-10-16` `288b3de4` [feat] feat: 首页增加统计图表
- `2026-10-16` `b813fbd3` [fix] fix(novel-crawl): 规则修复
- `2026-10-16` `b2fbdec5` [other] Update README.md
- `2026-10-16` `87c8ce2e` [other] 删除废弃文件
- `2026-10-13` `11b7b46c` [fix] fix(novel-crawl): 修复爬虫规则
- `2026-10-13` `3a3a8a38` [docs] docs: HTTP代理设置说明
- `2026-10-13` `e2cc9a9e` [feat] feat(mobile): 完善手机端小说检索功能
- `2026-10-13` `25c30ae7` [other] v5.4.0 发布
- `2026-10-13` `e7cdce98` [feat] feat(novel-front): 评论敏感词过滤
- `2026-10-13` `93a44a38` [other] Merge branch '5.4.x' into develop_xxy
- `2026-10-10` `36c082ab` [perf] perf(novel-crawl): 设置动态 User-Agent
- `2026-10-10` `e386b8f1` [fix] fix(novel-crawl): 设置默认图片
- `2026-10-10` `cfc5d894` [feat] feat(SEO): 自动生成和更新网站地图 sitemap.xml
- `2026-10-10` `f10ffa66` [feat] feat(novel-front): 作家专区增加作品完结功能
- `2026-09-04` `875f620e` [other] Update README.md
- `2026-06-01` `d9f3f464` [fix] fix: 修复 mysql-novel-plus 镜像
- `2026-05-17` `a9a502f9` [other] v5.3.2 发布
- `2026-05-17` `eef24cbe` [other] 内置一批无版权的小说数据
- `2026-05-17` `d9957859` [ci] ci: 简化 Dockerfile 文件
- `2026-05-17` `24b9fe2a` [fix] fix(author): 加载小说分类
- `2026-05-17` `ebfe6c52` [ci] ci: 构建并推送 mysql-novel-plus 镜像
- `2026-05-17` `ff10e4af` [other] Merge branch 'develop_xxy'
- `2026-05-17` `866094af` [other] Update README.md
- `2026-05-17` `f3153587` [docs] docs: 更新 sql 文件说明
- `2026-05-17` `d63c3ee3` [other] v5.3.3 发布
- `2026-05-16` `94b8a3a2` [ci] ci: 自动上传 Docker 镜像
- `2026-05-16` `159d0faa` [other] v5.3.1 发布
- `2025-12-27` `0f7d81de` [fix] fix(novel-front): 修复作品评论区分页错误
- `2025-12-27` `f3f37721` [other] Merge remote-tracking branch 'Gitee/develop_xxy' into develop_xxy
- `2025-11-09` `6fc8e963` [other] Update README.md
- `2025-10-26` `313e73c6` [other] v5.3.0 发布
- `2025-10-26` `01639cbd` [other] Merge branch '5.3.x'
- `2025-10-25` `1aa86bda` [chore] chore(novel-crawl): 修改生产环境外部配置文件
- `2025-10-25` `bd12d2f2` [fix] fix(novel-admin): 修复小说推荐列表分页显示异常
- `2025-10-25` `3d1b952e` [perf] perf(novel-crawl): 优化采集监控页异常提示体验
- `2025-10-25` `6b72d485` [feat] feat(novel-admin): 新增小说下载功能
- `2025-10-24` `938ae857` [feat] feat(novel-crawl): 新增磁盘保护机制，支持邮件告警与自动熔断
- `2025-10-14` `0279a86e` [fix] fix: 修复中国部分 IP 无省份信息导致地理位置显示为“0”的问题
- `2025-10-04` `f49d0dd1` [fix] fix: 修复因缓存 key 未更新导致小说推荐无法刷新的问题
- `2025-10-04` `43213adb` [other] v5.2.6 发布
- `2025-10-04` `9ba04ccf` [other] Merge branch 'develop_xxy'
- `2025-10-01` `80360735` [perf] perf: 禁用爬虫的 Cookie 管理以绕过 Cookie 限制
- `2025-09-29` `1ad240c7` [perf] perf(linux): 支持从任意路径执行启动脚本
- `2025-09-29` `8448e86a` [feat] feat(windows): 增加生产环境 Windows 一键启动脚本
- `2025-08-14` `d6faab8c` [fix] fix: 删除废弃接口
- `2025-08-14` `05648710` [other] v5.2.5 发布
- `2025-07-25` `7e27456a` [other] build：打包时复制最新模版文件
- `2025-07-25` `d4e8fb1c` [other] 模版更新
- `2025-07-25` `1ef64edc` [other] v5.2.4 发布
- `2025-07-25` `c24c68ec` [perf] perf: 优化缓存模块
- `2025-07-22` `d4e11268` [perf] perf: UI优化
- `2025-07-19` `b2d8fd8c` [feat] feat(AI): 更新默认AI对话模型
- `2025-07-19` `11d9d6f6` [refactor] refactor: 重构排序参数处理代码
- `2025-07-19` `99f1bc78` [other] Merge branch '5.2.x'
- `2025-07-19` `84a90bbc` [other] v5.2.3 发布
- `2025-07-18` `1cd8a49f` [perf] perf: 优化排序参数校验
- `2025-07-18` `bb1a87e3` [chore] chore(sql): 内置海外专用源
- `2025-07-18` `8c7b891a` [build] build(AI): Spring AI 升级到 1.0.0
- `2025-07-17` `91e7d271` [refactor] refactor: 重构sort和order参数校验功能
- `2025-07-17` `3db88283` [fix] fix: 修复sort和order参数的SQL注入漏洞
- `2025-07-17` `21816c6b` [other] Merge tag 'v5.2.2'
- `2025-07-17` `773ce159` [other] v5.2.2 发布
- `2025-07-16` `54bd194b` [feat] feat(novel-crawl): 增加爬虫源采集章节数量监控功能
- `2025-07-15` `3d41cf3e` [perf] perf(novel-crawl): 优化爬虫源列表排序
- `2025-07-14` `522bb7c7` [fix] fix(novel-front): 修复评论回复中的XSS漏洞
- `2025-07-14` `72071141` [other] v5.2.1 发布
- `2025-07-14` `d5d174e8` [other] Merge branch 'develop_xxy'
- `2025-07-12` `675b1560` [perf] perf(novel-front): 优化评论时间显示
- `2025-07-12` `972a49f1` [docs] docs: 错别字修改
- `2025-07-12` `02fb8191` [feat] feat(novel-front): 增加评论回复功能
- `2025-07-12` `3c409023` [feat] feat(novel-front): 增加评论点赞/点踩功能
- `2025-07-12` `d54eda23` [perf] perf: 未登录自动跳转
- `2025-07-12` `64e1686f` [other] v5.2.0 发布
- `2025-07-12` `16cec226` [other] Merge branch 'develop_xxy'
- `2025-07-12` `6452c160` [fix] fix(templates): URI编码
- `2025-07-12` `90009a57` [other] 模版更新
- `2025-07-11` `8c9013ad` [feat] feat(novel-crawl): 增加单本采集任务进度显示功能
- `2025-07-11` `8c572edb` [perf] perf(novel-crawl): 优化单本采集任务进度显示功能
- `2025-06-30` `4693c7ff` [feat] feat(novel-front): 增加评论用户地理位置显示功能
- `2025-06-21` `1534220f` [perf] perf(novel-crawl): 增加小说简介过滤规则
- `2025-06-21` `0830f6ff` [other] Merge remote-tracking branch 'Gitee/develop_xxy' into develop_xxy
- `2025-06-21` `adc83db6` [perf] perf(novel-crawl): 去除小说内容末尾的所有换行
- `2025-06-21` `efb136e3` [other] v5.1.5 发布
- `2025-06-21` `7955db0e` [perf] perf(novel-crawl): 去除小说简介前后空格
- `2025-06-21` `60dc28c5` [perf] perf(novel-crawl): 去除小说简介末尾冗余的小说名
- `2025-06-19` `a9fc80eb` [fix] fix: 修复 ConcurrentModificationException
- `2025-06-19` `24abe771` [chore] chore: 增加在线演示网站
- `2025-06-19` `9c11f228` [other] v5.1.4 发布
- `2025-05-13` `a07643bd` [fix] fix(novel-crawl): 解决多个爬虫进程间的爬虫源状态冲突问题
- `2025-05-13` `1f53b56b` [fix] fix(novel-crawl): 调整线程终止逻辑
- `2025-05-13` `32541a7c` [other] v5.1.3发布
- `2025-05-13` `42bcecc3` [fix] fix(novel-crawl): 解决爬虫进程间的冲突问题，支持同时启动多个爬虫进程
- `2025-05-12` `55d5deea` [fix] fix(novel-crawl): 修复部分源无法停止的问题
- `2025-05-12` `a4d6272a` [perf] perf(novel-crawl): 减小失效爬虫的CPU占用
- `2025-05-12` `2c86cb9a` [other] v5.1.2 发布
- `2025-05-07` `4f474b91` [other] Update README.md
- `2025-04-27` `ca22eed6` [other] v5.1.1 发布
- `2025-04-25` `415bf8a6` [perf] perf: 设置小说推荐缓存时间
- `2025-04-25` `df1b72fb` [style] style: 代码格式化
- `2025-04-21` `3f009dc1` [fix] fix: 小说封面图修改
- `2025-03-27` `0e156c04` [fix] fix: 修复部分环境 Public Key Retrieval is not allowed 错误
- `2025-03-23` `328bd555` [feat] feat: AI自动生成小说封面图片
- `2025-03-23` `f043ddff` [style] style: 代码格式化
- `2025-03-23` `970ad407` [perf] perf: AI内容生成失败提醒
- `2025-03-23` `04fc8e87` [fix] fix: 修复升级v5.0.0导致图片上传失败的问题
- `2025-03-23` `a06132a4` [other] 模版更新
- `2025-03-23` `eff4fc4c` [fix] fix: Spring AI 流式 API 请求 400 错误 在对 RestController 返回对象 json 格式化时，将所有 Long 类型转为 String 类型返回，避免前端数据精度丢失的问题。  主要是为了取代 spring.jackson.generator.write-numbers-as-strings=true 配置，避免影响全局的 ObjectMapper
- `2025-03-23` `d4fa0abc` [perf] perf: 使用流式响应处理AI生成文本，提高用户体验
- `2025-03-23` `02ad0f93` [other] v5.1.0 发布
- `2025-03-23` `8c1c0f10` [build] build: 修改外部配置文件
- `2025-03-21` `75a4c300` [other] 合并 5.0.x 分支
- `2025-03-21` `f8079f44` [other] Update README.md
- `2025-03-20` `6cdb6889` [ci] ci: GitHub Actions 指定中央仓库下载 maven 依赖
- `2025-03-20` `5dcc2b0b` [other] v5.0.1 发布
- `2025-03-20` `99f2a159` [build] build: 创建 GitHub Actions 工作流自动发布版本
- `2025-03-20` `d955b111` [ci] ci: 创建 GitHub Actions 工作流自动发布版本
- `2025-03-20` `c0634a33` [ci] ci: GitHub Actions 上传ZIP包
- `2025-03-20` `ec9674f2` [feat] feat: 移出书架
- `2025-03-20` `e4e511ae` [feat] feat: 移出书架
- `2025-03-20` `73654dda` [ci] ci: GitHub Actions 设置上传 token
- `2025-03-20` `06074faf` [feat] feat(pc): 移除书架
- `2025-03-19` `acf9c767` [perf] perf: 提前创建数据库连接池 Spring Boot 新版本默认会在第一次请求数据库时创建连接池
- `2025-03-19` `4b00ea68` [perf] perf: 提高第一次登录速度
- `2025-03-19` `82658f3b` [perf] perf: 兼容其它数据源
- `2025-03-19` `1081b8e1` [chore] chore: 修改日志
- `2025-03-19` `4b1507b2` [perf] perf: 连接池统一创建
- `2025-03-18` `f5a9a742` [fix] fix: 生产环境web静态资源目录配置
- `2025-03-18` `3858cd4e` [build] build: 修改版本号
- `2025-03-18` `c4a6acf2` [fix] fix: 网站ico图标显示
- `2025-03-18` `0afc7b1b` [fix] fix: 通用异常处理
- `2025-03-18` `d9f9fd8b` [build] build: 优化打包配置
- `2025-03-18` `c1583f83` [fix] fix: 网站icon显示
- `2025-03-18` `eecbb2dd` [fix] fix: 通用异常处理
- `2025-03-17` `a046899d` [other] fix：通用异常处理
- `2025-03-17` `84a06a70` [fix] fix: 通用异常处理
- `2025-03-17` `8781cc54` [chore] chore: 模版/配置/SQL/文档更新
- `2025-03-16` `467290b9` [feat] feat: 集成 Spring AI 实现基础的 AI 写作功能
- `2025-03-16` `14a1ff69` [build] build: 升级配置
- `2025-03-15` `af1237e2` [build] build: Java版本升级到21
- `2025-03-15` `9033ca63` [build] build: Java版本升级到21 & SpringBoot版本升级到2.7.18
- `2025-03-15` `fd200772` [build] build: 修改版本号
- `2025-03-15` `81c1514a` [build] build: 构建生产环境配置
- `2025-03-15` `d77ce5b4` [build] build: Spring Boot 升级到 3.4.0
- `2025-03-15` `8d35aa80` [build] build: 修改打包配置
- `2025-03-15` `11978c2c` [build] build: v5.0.0发布
- `2025-03-14` `74d7ea70` [feat] feat: 代理IP增加用户名密码设置
- `2025-03-14` `cdfe481d` [other] Update README.md
- `2025-03-14` `6d0ab337` [perf] perf: 爬虫分类规则优化
- `2025-03-14` `73502a27` [feat] feat: 支持非utf-8编码的网站采集
- `2025-03-14` `85b64bbc` [perf] perf: 爬虫采集流程优化
- `2025-02-28` `0ff87614` [fix] fix: 修复失效的爬虫规则
- `2025-01-18` `2cb9f850` [other] 优化提示
- `2024-11-02` `4b9dbe96` [other] 修复i笔趣阁爬虫规则
- `2024-11-02` `2136f749` [other] 增加爬虫规则
- `2024-11-02` `71b9d1d9` [other] 模版更新
- `2024-11-02` `d8e559ab` [other] 修复规则
- `2024-11-02` `3849a9b8` [build] build: 修改版本号
- `2024-09-21` `a8219253` [other] 优化
- `2024-09-21` `f78a2a36` [other] 优化
- `2024-09-21` `3586ffbc` [other] 优化
- `2024-09-16` `5c35f7af` [other] 更换默认logo图片
- `2024-08-06` `21a6a49c` [fix] fix: 作家稿费统计
- `2024-08-06` `d55e1a3e` [revert] revert: sql格式化还原
- `2024-07-20` `3735023c` [perf] perf(novel-front): UI优化
- `2024-06-01` `3a7972a4` [other] Merge remote-tracking branch 'Gitee/master'
- `2024-06-01` `89992dc7` [perf] perf(novel-crawl): 增加小说内容过滤
- `2024-05-31` `976db942` [build] build: 修改版本号
- `2024-05-28` `ea5c0e8b` [other] 模版更新
- `2024-05-28` `48a70c2a` [build] build: 修改版本号
- `2024-05-28` `e33db860` [other] Update README.md
- `2024-05-26` `b976a003` [perf] perf: UI优化
- `2024-05-26` `730fcb4c` [fix] fix: 默认logo图片失效
- `2024-05-26` `b0c249cd` [fix] fix: 默认logo图片失效
- `2024-05-25` `6d9b5635` [fix] fix: 文件上传大小限制
- `2024-05-12` `bfb7d6cc` [fix] fix: i笔趣阁域名更换
- `2024-03-03` `9d4dc409` [fix] fix: URI编码
- `2024-02-21` `34d211af` [fix] fix: 只推荐有内容的小说
- `2024-02-18` `2d218076` [chore] chore: 修改打包默认模版
- `2024-02-07` `f494aae2` [chore] chore: 模版更新
- `2024-02-07` `331f56d1` [fix] fix: 移动端首页在数据量小于10时报错
- `2024-02-07` `674e4df8` [chore] chore: 模版更新
- `2024-02-05` `82758271` [feat] feat: 增加语音播放小说内容
- `2024-02-05` `2fc533f8` [fix] fix(novel-crawl): 登录页样式问题
- `2024-02-04` `4c82c2d7` [perf] perf: 优化支付宝支付流程
- `2024-02-03` `7bbabb34` [fix] fix: 修复充值页面的未登录跳转路径
- `2024-02-03` `4665b5c4` [fix] fix: bug
- `2023-12-29` `c62da9bb` [fix] fix: nickName、userPhoto 更新校验
- `2023-12-29` `f77792aa` [perf] perf: 限制昵称长度并优化显示
- `2023-12-29` `d6093d81` [fix] fix(novel-admin): 友情链接URL格式校验
- `2023-10-31` `8a63cff0` [other] Update README.md
- `2023-10-30` `e7005004` [perf] perf(mobile): 登录/注册页优化
- `2023-10-30` `ff68cdd8` [perf] perf(mobile): 首页优化
- `2023-10-30` `07bed12f` [fix] fix(mobile): 充值页标题
- `2023-10-30` `0d6e0ffb` [perf] perf(mobile): 内容页优化
- `2023-10-22` `98f1f804` [chore] chore(sql): 自动创建 novel_plus 数据库
- `2023-10-22` `b61dc4d0` [build] build(Docker): 管理 Dockerfile 文件
- `2023-10-21` `ef290bed` [fix] fix: 书架列表时间格式化
- `2023-10-21` `5978d6cb` [build] build: 修改版本号
- `2023-10-15` `a55f456b` [perf] perf: 更新爬虫管理系统主题颜色
- `2023-10-15` `c66d5661` [other] Merge pull request #128 from 201206030/develop_xxy
- `2023-10-15` `0332802f` [feat] feat(crawl): 账号退出
- `2023-10-15` `156f0378` [other] Merge pull request #129 from 201206030/develop_xxy
- `2023-10-15` `5543e5aa` [perf] perf: 设置网站 ico 图标
- `2023-10-14` `d8434591` [other] Update README.md
- `2023-10-14` `54067833` [other] 删除垃圾文件
- `2023-10-14` `a5394cb4` [other] Update README.md
- `2023-10-14` `2062123e` [perf] perf(mobile): 去除手机网站底部空白间隙
- `2023-10-14` `2275b857` [chore] chore: 模版更新
- `2023-10-14` `96960789` [fix] fix(alipay): 修改默认支付宝支付成功跳转地址
- `2023-10-14` `f6d66e69` [other] Update README.md
- `2023-10-14` `1998dcd4` [fix] fix(alipay): 修复支付宝支付页面报错
- `2023-10-14` `30959da0` [other] 删除垃圾文件
- `2023-10-14` `a33d8f68` [other] 删除垃圾文件
- `2023-10-13` `255b3f8c` [feat] feat(templates): 新增绿色主题模版，并设置为默认模版
- `2023-10-12` `05d65c19` [perf] perf: 手机端页面优化
- `2023-10-12` `4c9f39ab` [feat] feat: 手机端阅读历史页面适配
- `2023-10-12` `8bc05a16` [other] Merge remote-tracking branch 'Gitee/4.1.x' into develop_xxy
- `2023-10-12` `98a51576` [feat] feat: 支付宝手机网站支付
- `2023-10-12` `00179359` [chore] chore: 更新 Dockerfile 文件
- `2023-10-12` `6019ce11` [build] build: 修改版本号
- `2023-10-12` `3e1c1f02` [chore] chore: 模版更新
- `2023-10-10` `8311681b` [perf] perf(mobile): 加入书架按钮样式优化
- `2023-10-10` `f9aad61b` [chore] chore: 模版更新
- `2023-09-29` `f333a2c0` [perf] perf: 优化小说推荐管理
- `2023-09-29` `44bf0cd6` [fix] fix: 修复作家专区小说封面更新问题
- `2023-09-29` `4497dd19` [chore] chore: 模版更新
- `2023-06-09` `bff5b082` [perf] perf: 爬虫配置自定义登录页面
- `2023-06-05` `14f9205d` [docs] docs: 修正小说内容保存配置的注释
- `2023-05-28` `04d7b453` [feat] feat: 移除 FastDFS 模块
- `2023-05-28` `24c80e38` [fix] fix: 修改依赖组件漏洞
- `2023-05-28` `cb2ff39b` [build] build: 移除 Elasticsearch 依赖
- `2023-05-28` `3eaa5260` [fix] fix: 修复CVE漏洞
- `2023-05-17` `9fe51eab` [fix] fix: 页面请求异常处理
- `2023-05-14` `eb982b51` [feat] feat: 手机端充值页面适配
- `2023-05-14` `e1c800d7` [feat] feat: 手机端用户中心优化
- `2023-05-13` `dabfb9d1` [feat] feat: 手机端登录页面适配
- `2023-05-13` `dce8a21c` [feat] feat: 首页是否登录识别
- `2023-05-13` `4fb0d478` [feat] feat: 手机端注册页面适配
- `2023-05-13` `18f5fbf5` [feat] feat: 手机端我的书架页面适配
- `2023-05-13` `c63b4d61` [feat] feat: 手机端用户中心页面适配
- `2023-05-08` `d9ad02e3` [fix] fix(sql): 网站信息修改提示未授权
- `2023-04-18` `aa2929a3` [feat] feat: 后台小说推荐管理
- `2023-04-18` `281561c8` [fix] fix: 会员注册验证码
- `2023-04-18` `cab350db` [fix] fix: 刷新首页新闻缓存
- `2023-04-18` `b02a2b3b` [build] build: 4.1.0 发布
- `2023-04-18` `f28c8a9c` [revert] revert: 恢复误删文件
- `2023-04-18` `e4497861` [feat] feat: 后台会员反馈管理
- `2023-04-17` `9ed46578` [fix] fix: 网站信息管理的权限问题
- `2023-04-16` `e2cfa5a7` [other] Update README.md
- `2023-04-15` `8c3fb7f1` [build] build: 4.0.0 发布
- `2023-04-15` `749fd1ae` [docs] docs: 项目演示
- `2023-04-15` `6fb1e5cc` [chore] chore: 模版更新
- `2023-04-14` `3b0edd8e` [fix] fix: sql
- `2023-04-14` `c76df15a` [feat] feat: 后台友情链接管理
- `2023-04-14` `57eca58b` [feat] feat: 后台会员管理
- `2023-04-14` `2c3b735d` [feat] feat: 后台网站信息管理
- `2023-04-14` `282bc7b7` [refactor] refactor: 移除 RabbitMQ 和 Elasticsearch 相关功能
- `2023-04-14` `29d074ec` [refactor] refactor: 移除 Ehcache，默认缓存设置为 Redis
- `2023-04-14` `b45b83fd` [other] Update README.md
- `2023-04-14` `0c59adf2` [feat] feat: 后台订单管理
- `2023-04-14` `8ddc6cc4` [feat] feat: 后台评论管理
- `2023-04-14` `3ffa75dc` [perf] perf: 后台评论管理
- `2023-04-14` `c71eadef` [perf] perf: 后台订单管理
- `2023-04-14` `5854536c` [fix] fix: 代码生成数据表查询
- `2023-04-14` `9f23f817` [feat] feat: 后台小说管理
- `2023-04-14` `687eb618` [feat] feat: 后台小说删除
- `2023-04-14` `a7d825cc` [fix] fix: 后台模块查询过滤相同的行
- `2023-01-11` `68b3458c` [other] Add favicon.ico
- `2022-08-29` `2f5002f6` [other] Update README.md
- `2022-07-31` `a9080310` [other] update template & sql
- `2022-07-31` `d293d7bf` [other] Merge branch 'develop_xxy' of https://gitee.com/novel_dev_team/novel-plus into develop_xxy
- `2022-07-26` `7be529fe` [other] Update README.md
- `2022-07-26` `1f571f9b` [other] Update README.md
- `2022-07-24` `d9626208` [other] Update README.md
- `2022-07-24` `2f62641b` [other] Update README.md
- `2022-07-21` `7640d153` [other] Update README.md
- `2022-07-20` `05608d03` [other] Update README.md
- `2022-07-20` `4f6ec5aa` [other] Update README.md
- `2022-07-20` `e3010ea8` [other] Update README.md
- `2022-07-20` `3d9f52ff` [other] Update README.md
- `2022-07-20` `0112af20` [other] Update README.md
- `2022-07-18` `617f6f50` [other] Update README.md
- `2022-07-18` `01984f71` [other] Update README.md
- `2022-07-16` `e0686f07` [other] Update README.md
- `2022-07-15` `54aeef7c` [other] Update README.md
- `2022-07-15` `5e113526` [other] Update README.md
- `2022-07-15` `3abe7e22` [other] Update README.md
- `2022-07-15` `027fbffb` [other] Update README.md
- `2022-07-15` `b997367f` [other] Merge github.com:201206030/novel-plus into develop_xxy
- `2022-07-15` `607deaa8` [build] build: v3.6.2 发布
- `2022-07-15` `5d70e440` [other] Update README.md
- `2022-07-15` `09a4f391` [other] Update README.md
- `2022-07-15` `028c2007` [fix] fix: 新笔趣阁规则移动到全量sql文件
- `2022-07-15` `4bf495b6` [other] Update README.md
- `2022-07-15` `5fb17177` [other] Update README.md
- `2022-07-15` `472440ef` [other] Update README.md
- `2022-07-15` `d93bf3dd` [other] Update README.md
- `2022-07-15` `9a0a7995` [other] Update README.md
- `2022-07-15` `5278b5fc` [other] Update README.md
- `2022-07-14` `cdceb381` [other] Update README.md
- `2022-07-14` `3c322a9d` [other] Update README.md
- `2022-07-14` `ec3428c3` [docs] docs: 增加 sql 说明
- `2022-07-14` `40a999f3` [perf] perf: 模版更新
- `2022-07-14` `c45b81fb` [build] build: 优化打包
- `2022-07-14` `6fc2df9b` [docs] docs: 更新源码安装教程
- `2022-07-14` `7d1b024c` [other] Update README.md
- `2022-07-14` `ba272bd8` [feat] feat: 增加 HTTP 代理配置，助力爬虫采集
- `2022-07-14` `3d3cbc22` [feat] feat: 增加 HTTP 代理配置，助力爬虫采集
- `2022-07-14` `0b728b9f` [docs] docs: 修改 sql 文件说明
- `2022-07-14` `78de1de8` [other] Update README.md
- `2022-07-14` `e732c0fd` [other] Update README.md
- `2022-05-22` `547bf00f` [docs] docs: update README.md
- `2022-05-17` `303cc205` [other] update README.md
- `2022-05-17` `dc654086` [other] update README.md.
- `2022-05-17` `d6849bc5` [other] update README.md.
- `2022-05-01` `fe90345f` [fix] fix: 首页小说推荐数据渲染
- `2022-04-27` `029cce95` [other] update
- `2022-04-27` `7ac4b628` [other] update
- `2022-04-26` `7395cf63` [add] add: 启动日志

## 八、文件变化统计（分叉点 → 上游最新）

| 目录/模块 | 变化文件 | 新增 | 修改 | 删除 |
| --- | --- | --- | --- | --- |
| novel-admin | 1464 | 201 | 14 | 1249 |
| novel-front | 682 | 354 | 101 | 227 |
| templates | 678 | 637 | 36 | 5 |
| assets | 56 | 0 | 0 | 56 |
| novel-crawl | 53 | 19 | 26 | 8 |
| novel-common | 46 | 22 | 21 | 3 |
| doc | 20 | 16 | 1 | 3 |
| pom.xml | 1 | 0 | 1 | 0 |
| .github | 1 | 1 | 0 | 0 |
| .gitignore | 1 | 0 | 1 | 0 |
| config | 1 | 1 | 0 | 0 |
| README.md | 1 | 0 | 1 | 0 |

## 九、以后怎么再同步

```powershell
# 1) 预览上游新增（不改变你的工作区）
git fetch --no-tags --filter=blob:none upstream master
git log --oneline HEAD..upstream/master

# 2) 重新生成本文档（会自动更新 tools/.upstream-state.json）
powershell -ExecutionPolicy Bypass -File tools\upstream-digest.ps1

# 3) 确认没问题后，把你的分支快进到上游（当前分支是上游的祖先时可用）
git merge --ff-only upstream/master
```

> 提示：`--filter=blob:none` 只取提交与目录树，不下载文件内容，几秒即可完成；等你真要合并/构建时再按需拉取文件。

