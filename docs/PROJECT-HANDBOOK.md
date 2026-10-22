# novel-plus 项目全景手册（面试准备版）

> **文档版本：v1.1** ｜ 更新：2026-10-22（新增 **Part B：版本演进与最新版 v6.0.0**）
> **Part A（第 0~11 节）**：基于你仓库当前分支 `develop_xxy` 的代码（novel-plus v3.6 时代，Java 8 + Spring Boot 2.1.8）
> **Part B（第 12~18 节）**：基于上游最新代码 `upstream/master`（**v6.0.0**，Java 21 + Spring Boot 3.4 + Spring AI），读法 `git show upstream/master:<路径>`
> 说明：本文所有类名、表名、配置项、缓存 TTL 都来自实际代码，不是凭印象写的。带「未确认」的是代码里没看全的部分。
>
> **更新记录**
> - v1.1（2026-10-22）：新增 Part B（版本演进史、v6 技术栈/数据模型/新业务/AI 实现/跨端 API/两版对照）；修正 Part A 中审核流、分类管理、默认账号、打包方式等若干细节。
> - v1.0（2026-10-22）：Part A 初版（v3.6 代码全景）。

---

## 0. 先用 3 分钟建立整体印象

**一句话**：小说精品屋-plus 是一套原创文学 CMS，由 **PC/WAP 前台门户 + 作家专区 + 平台运营后台 + 爬虫采集** 四个子系统组成，支持小说阅读、书架、书评（含审核）、会员充值、VIP 章节订阅、作家收益结算、新闻发布和实时统计。

**规模数字**（可以背下来，面试很有用）：

| 维度 | 数字 |
|---|---|
| Maven 模块 | 4 个业务模块 + 1 个前端模版目录（`templates`） |
| Java 文件 | 340 个 |
| 数据库表 | 39 张逻辑表 + 10 张章节分表 |
| 前台页面入口 | 10 个 Controller + 1 个页面路由控制器（`PageController`） |
| 定时任务 | 5 个（ES 同步、图片转存、日结、月结、采集线程监控） |
| 内容存储 | 2 套（数据库分表 / TXT 文本）可配置切换 |
| 缓存实现 | 2 套（EhCache 进程内 / Redis 分布式）可切换 |
| 搜索实现 | 2 套（MySQL LIKE / ElasticSearch）可开关 |
| 部署端口 | 前台 8083、后台 80、爬虫 8081 |

**技术栈**：

| 层 | 技术 | 用在哪 |
|---|---|---|
| 框架 | Spring Boot 2.1.8 / Java 8 | 全部模块 |
| 持久层 | MyBatis 2.1.4 + **MyBatis Dynamic SQL 1.1.4** | 全部查询（类型安全的 SQL DSL，不写 XML） |
| 分页 | PageHelper | 列表页 |
| 分库分表 | **Sharding-JDBC** | 章节内容表 `book_content0~9` |
| 鉴权 | **JJWT**（前台）、**Shiro**（后台） | 前台 JWT 无状态登录；后台 Session + RBAC |
| 缓存 | EhCache（默认）/ **Redis + Redisson** | 首页榜单、书籍设置、分布式锁 |
| 搜索 | **ElasticSearch 7.9.3**（jest 客户端） | 小说搜索，ik 分词 |
| 消息 | **RabbitMQ**（默认关闭） | 阅读点击量削峰 |
| 文件 | 本地 / 阿里云 OSS / FastDFS（三选一） | 封面、上传图片 |
| 模板 | Thymeleaf + 多套主题（blue/dark/orange） | 前台 PC/WAP |
| 后台 UI | Layui | 平台后台 |
| 工具 | Lombok、Swagger2（后台）、Druid（后台）、Hutool 风格自研工具 | — |

**系统全景图**：

```
                    ┌──────────────────────────────────────────────┐
   浏览器(PC/WAP) ──▶│ novel-front :8083                            │
                    │  页面路由 PageController → Thymeleaf 主题     │
                    │  REST /author/* /user/* /book/* (RestResult) │
                    │  JWT(Cookie/Header) + XSS Filter             │
                    └───────┬───────────────┬──────────────────────┘
                            │               │
                    ┌───────▼──────┐  ┌─────▼─────────┐
                    │ MySQL        │  │ Redis         │
                    │ novel_plus   │  │ 缓存/锁/验证码 │
                    │ book_content0-9（分表）          │
                    └───────▲──────┘  └─────▲─────────┘
                            │               │
   ┌────────────────────────┴───────────────┴──────────────────────┐
   │ novel-admin :80（运营后台）    novel-crawl :8081（采集）        │
   │  Shiro + RBAC + 菜单/数据权限  7 线程/类目 + 正则规则 + 定时监控 │
   └────────────────────────────────────────────────────────────────┘
                            │
                    ┌───────▼──────┐
                    │ ElasticSearch │  novel 索引（搜索增强）
                    └──────────────┘
```

---

## 1. 面试时怎么介绍这个项目（重要，先看这节）

### 1.1 两分钟版本（照着说）

> "我做的是一套原创文学 CMS，叫小说精品屋-plus，四个模块：前台门户（PC+WAP 自适应）、作家专区、平台运营后台、爬虫采集。
> 前台是 Spring Boot + Thymeleaf 的多主题站点，读者可以看书、进书架、写书评（审核后展示）、充值购买 VIP 章节；作家后台可以发书、发章节、看收益；运营后台做书籍/新闻/会员/订单的 CRUD 管理和统计报表；爬虫子系统用可配置的正则规则采集小说站点，自动入库和更新。
> 技术上比较特别的点：章节内容用 Sharding-JDBC 按 `index_id % 10` 分了 10 张表，内容支持存库或存 TXT 两种模式；首页和阅读页用 CompletableFuture 并行加载多个数据源；搜索接 ElasticSearch，用 ik 分词并按字段加权；点击量走 RabbitMQ 聚批更新，避免每读一章就写一次库；缓存做了 EhCache/Redis 可切换的抽象。"

### 1.2 关于"总负责人"的诚实建议（务必看）

这个项目是 GitHub 上的开源项目 `201206030/novel-plus`（**4758 star**，你的是 fork）。面试官搜一下就能看到原始仓库。所以：

- ❌ 不要说"从 0 设计并开发了这套系统"——一搜就穿帮，而且会被追问设计细节到崩。
- ✅ 可以说"**这个项目是我基于开源版落地的，我负责 X**"（X = 部署上线 / 二次开发 / 性能优化 / 数据迁移 / 定制需求）。
- ✅ 更适合的定位：**"我负责把它从源码跑通、部署到生产、做业务定制和运维"**——这个身份能合理回答大部分细节问题，而且不会被质疑原创性。

三个可用的表述模板：

| 你的真实情况 | 建议说法 |
|---|---|
| 只跑通过、改过一点 | "我基于 novel-plus 做了一次完整的本地/服务器落地：环境搭建、数据库初始化、Redis/ES 配置、爬虫规则调试、Nginx 部署，期间修了若干兼容问题" |
| 做过功能改动 | 上面 + "另外改了 XX（比如加了一个新分类页/改了结算规则/接了另一个支付）"——**先真的改一个小功能再讲** |
| 想讲架构能力 | "我把它当架构案例拆过：分表策略、缓存一致性、支付回调幂等、爬虫并发控制，我做了压测和优化对比"——这条最安全也最加分 |

### 1.3 万一被问"这项目是你写的吗"

直说："是基于开源项目 novel-plus 的落地和二次开发"。然后立刻把话题引到你**真正做过**的部分（部署、排错、改造、优化）。**能讲清楚细节**比声称原创有价值得多。

---

## 2. 业务全景

### 2.1 参与者与子系统

| 参与者 | 入口 | 能做什么 |
|---|---|---|
| 游客 | 前台 PC/WAP | 浏览首页、分类、排行、搜索、看书（免费章节）、看新闻 |
| 读者（会员） | 前台 | 注册登录、书架、阅读历史、书评、充值、购买 VIP 章节、个人中心 |
| 作家 | 前台 `/author/*` 作家专区 | 申请成为作者（笔名）、发书、发章节、改章节、作品上下架、查看日/月收益 |
| 运营/管理员 | 后台 `/novel/book` 等 | 书籍/分类/新闻/会员/订单管理、审核上下架、统计报表、爬虫规则管理、系统权限管理 |
| 系统（定时任务） | 后台进程 | ES 增量同步、章节点击量落库、图片转存、日结/月结、采集线程监控 |

### 2.2 核心业务闭环

```
注册登录 ──▶ 找书（首页榜单/分类/搜索）──▶ 详情页 ──▶ 阅读
                                            │              │
                                            │              ├─ 免费章节：直接看
                                            │              └─ VIP 章节：需要购买
                                            │
                                            ├─ 加入书架 / 记阅读历史
                                            ├─ 写书评（审核后展示）
                                            └─ 充值（支付宝）──▶ 余额 ──▶ 购买章节

作家：申请笔名 ──▶ 发书（审核/上架）──▶ 发章节（免费/VIP）──▶ 读者付费阅读 ──▶ 日结/月结算收益
运营：审核内容 / 管理分类新闻 / 看报表 / 配爬虫采集规则
```

### 2.3 名词对齐（别在面试里叫错）

| 名词 | 含义 | 对应字段/表 |
|---|---|---|
| 书币/屋币 | 站内虚拟货币，1 元 = 100 币（充值回调里 `totalAmount * 100`） | `user.account_balance` |
| VIP 章节 | 需要购买才能读的章节 | `book_index.is_vip = 1` |
| 订阅/购买 | 单章购买记录 | `user_buy_record` |
| 书单 | 用户收藏的书单 | **本版本没有书单表**（上游 v5+ 才有） |
| 书评 | 对整本书的评论，需要审核 | `book_comment`（`audit_status` 0 待审/1 通过/2 不通过） |
| 段落评论 | 对章节某一段落的评论 | **本版本没有**（上游 v5+ 才有，别讲错） |
| 作品方向 | 男频/女频 | `book.work_direction`（0 男 1 女） |
| 点击量 | 书籍累计阅读数 | `book.visit_count` |

---

## 3. 系统架构

### 3.1 模块职责

| 模块 | 职责 | 关键包 |
|---|---|---|
| `novel-common` | 公共实体、Mapper（MyBatis 动态 SQL 生成）、缓存抽象、异常与统一返回、工具类 | `com.java2nb.novel.core.*`、`entity`、`mapper` |
| `novel-front` | PC/WAP 前台门户 + 作家专区 + 会员/支付/阅读接口 | `controller`、`page`（页面路由）、`service.impl`、`core.config/filter/listener/schedule` |
| `novel-admin` | 平台运营后台：RBAC、内容/会员/订单管理、统计、代码生成器 | `com.java2nb.system.*`（权限）、`com.java2nb.novel.*`（业务）、`com.java2nb.common.*`（基础） |
| `novel-crawl` | 爬虫采集：规则配置、采集线程、入库 | `core.crawl`（解析器）、`service.impl` |
| `templates/` | 前台多套主题模版（blue / dark / orange），生产环境外置 | — |

依赖方向：`front / admin / crawl` → `common`，模块之间不直接调用（采集入库通过 common 的 entity/mapper 复用同一套表）。

### 3.2 一次请求的链路（讲架构时用）

**页面请求（阅读页为例）**：

```
浏览器 GET /book/1/1001.html
  → NovelFilter（PC/WAP 识别，写模板前缀；静态图片映射）
  → PageController.bookContent()
      ├─ CompletableFuture 并行：
      │    ├─ queryBookDetail(bookId)          → book 表
      │    ├─ queryBookIndex(bookIndexId)      → book_index 表
      │    ├─ queryPre/NextBookIndexId(...)    → book_index 表（依赖上一步，thenApplyAsync）
      │    └─ queryBookContent(...)            → book_content{index_id%10}（Sharding-JDBC 路由）
      ├─ 校验：是否登录（JWT）、章节是否 VIP、用户是否已购买
      └─ 返回模板路径：ThreadLocalUtil.getTemplateDir() + "book/book_content"
  → Thymeleaf 渲染（生产环境从外部 templates/blue/html 读）
  → 响应 HTML（含静态资源，生产走 Nginx/静态目录）
```

**页面路由机制（这个设计很特别，面试可以讲）**：

`PageController` 只有 **3 条通配路由** + 模板同名约定，绝大多数页面没有单独的 `@RequestMapping`：

| URL 模式 | 处理 | 返回视图 |
|---|---|---|
| `/{url}.html` | `module()` | `url` |
| `/{module}/{url}.html` | `module2()` | `module/url`（`/user/login.html`→`user/login`） |
| `/{module}/{classify}/{url}.html` | `module3()` | `module/classify/url` |

- 所以 `/user/login.html`、`/pay/index.html`、`/about/news.html`、`/author/index.html` 都"不用写路由"，只要模板文件存在即可 → **加页面不用改 Java 代码**
- `/author/**` 的鉴权就写在这条通配路由里：未登录重定向登录页、已登录非作者重定向入驻页
- 视图名统一拼 `ThreadLocalUtil.getTemplateDir()` 前缀（`""`=PC / `"mobile/"`=WAP）
- 代价：编译期无法发现拼错的 URL、IDE 跳转困难，属于"约定优于配置"的取舍

**接口请求（作家发章节）**：

```
POST /author/addBookContent
  → BaseController.getUserDetails()：Cookie 或 Header 取 Authorization，JWT 解出 userId
  → AuthorController → 校验该用户是作者且书属于自己 → BookService.addBookContent
  → 写 book_index（章节索引）+ book_content{index_id%10}（内容）+ 更新 book 的 last_index 字段
  → 返回 RestResult
```

### 3.3 部署拓扑（面试问"怎么上线"）

| 服务 | 端口 | 说明 |
|---|---|---|
| novel-front | 8083 | 前台 + 作家专区，可前置 Nginx 做静态资源/HTTPS |
| novel-admin | 80 | 运营后台（Layui 静态页 + 接口） |
| novel-crawl | 8081 | 采集子系统，可单独部署，也可与后台部署在一起 |
| MySQL | 3306 | 库名 `novel_plus`（分表在库内） |
| Redis | 6379 | 缓存、验证码、分布式锁、采集线程集合 |
| ElasticSearch | 9200 | 可选，`spring.elasticsearch.enable=1` 时启用 |
| RabbitMQ | 5672 | 可选，`spring.rabbitmq.enable=1` 时启用点击量削峰 |
| OSS/FastDFS | — | 可选，图片存储三选一 |

---

## 4. 数据模型

### 4.1 表清单（按业务域分组）

**书籍域**：`book`（书籍主表，含 `audit_status` 审核状态）、`book_index`（章节目录/索引）、`book_content0~9`（章节正文，分表）、`book_category`（分类）、`book_setting`（首页各推荐位配置）、`book_author`（书-作者关系）、`book_comment`（书评，带 `audit_status` 审核）、`book_comment_reply`（评论回复）、`book_screen_bullet`（弹幕，历史遗留表）、`author`（作者笔名）、`author_code`（作者邀请码）

**用户域**：`user`（会员，含余额）、`user_bookshelf`（书架）、`user_read_history`（阅读历史）、`user_buy_record`（章节购买记录）、`user_feedback`（意见反馈）

**交易域**：`order_pay`（充值订单）、`author_income_detail`（作者日收益明细）、`author_income`（作者月收益）

**内容运营**：`news` / `news_category`（新闻）、`friend_link`（友情链接）

**系统权限（后台）**：`sys_user`、`sys_role`、`sys_menu`、`sys_user_role`、`sys_role_menu`、`sys_dept`（部门）、`sys_data_perm`（数据权限）、`sys_role_data_perm`、`sys_dict`（字典）、`sys_log`（操作日志）、`sys_file`（文件）

**代码生成器**：`sys_gen_table`、`sys_gen_table_column`、`sys_gen_columns`

**爬虫域**：`crawl_source`（采集源 + 规则 JSON）、`crawl_batch_task`（批量采集任务）、`crawl_single_task`（单本采集任务）

### 4.2 核心 ER 关系

```
book_category 1 ──── n book 1 ──── n book_index 1 ──── 1 book_content（按 index_id%10 分表）
                       │  │
                       │  └── n book_comment（书评/段评）
                       └── n book_author ── 1 author ── 1 user（写作账号）

user 1 ── n user_bookshelf ── 1 book
user 1 ── n user_read_history ── 1 book
user 1 ── n user_buy_record ── 1 book_index
user 1 ── n order_pay（充值订单）

author 1 ── n author_income_detail（日）
author 1 ── n author_income（月）

sys_user n ── n sys_role（sys_user_role）n ── n sys_menu（sys_role_menu）
sys_role n ── n sys_data_perm（sys_role_data_perm）
sys_dept 1 ── n sys_user
```

### 4.3 关键表要点（面试常被追问）

| 表 | 关键字段 | 说明 |
|---|---|---|
| `book` | id, book_name, author_name, cat_id, cat_name, work_direction, book_status, visit_count, word_count, last_index_id/name/update_time, pic_url, crawl_source_id, crawl_book_id | 书籍主表；`last_index_*` 冗余存最新章节，避免详情页 join 章节表 |
| `book_index` | id, book_id, index_num（第几章）, index_name, word_count, is_vip, **book_price**（本章售价）, **storage_type**（db/file）, update_time | 章节目录；`book_price` 由"字数 × 单价"算出来（见 5.9）；`storage_type` 决定正文从库里还是 TXT 读（20210913 增量脚本加的列） |
| `book_content` | id, index_id, content | 正文；**分表键是 `index_id % 10`**，不是 book_id |
| `user` | id, username, password(MD5), nick_name, account_balance, status | 会员；余额单位是"币" |
| `user_buy_record` | user_id, book_id, book_name, book_index_id, book_index_name, buy_amount, create_time | 购买流水（冗余书名/章节名做快照，避免后续改名影响历史订单） |
| `order_pay` | out_trade_no, trade_no, pay_channel, total_amount, pay_status, user_id | 充值订单；`pay_status=1` 成功 |
| `author_income_detail` | user_id, author_id, book_id, income_date, income_account, income_count, income_number | 日结明细（某书某天的账户余额/订阅次数/人数） |
| `author_income` | user_id, author_id, book_id, income_month, pre_tax_income（税前）, after_tax_income（税后）, pay_status（结算状态）, confirm_status（确认状态）, detail | 月结汇总 |
| `crawl_source` | source_name, source_status, crawl_rule(JSON) | 采集源；规则是 **JSON 存的 RuleBean** |
| `sys_menu` | menu_id, parent_id, name, perms, type（目录/菜单/按钮） | 菜单+按钮权限；`perms` 对应 `@RequiresPermissions("novel:book:add")` |

### 4.4 章节正文分表设计（重点，必考）

`novel-common/src/main/resources/application-common-dev.yml`：

```yaml
sharding:
  jdbc:
    datasource:
      names: ds0
      ds0: { jdbc-url: jdbc:mysql://localhost:3306/novel_plus ... }
    config:
      sharding:
        tables:
          book_content:
            key-generator-column-name: id
            actual-data-nodes: ds${0}.book_content${0..9}
            table-strategy:
              inline:
                shardingColumn: index_id
                algorithm-expression: book_content${index_id % 10}
```

要点（面试可讲）：

1. **分表键选了 `index_id` 而不是 `book_id`**：因为阅读时总是按"具体章节"查，按 index_id 取模能直接定位到一张表（单表查询）；按 book_id 分表则一章一章分散在不同表里，查目录反而要扫多表。
2. 分 10 张表，单表数据量可控（写作 `book_content${index_id % 10}`）。
3. 已知坑（代码注释里写了）：分表后 `jdbcType` 不能用 `LONGVARCHAR`，否则会抛 `NotSerializableException: StringReader`，必须全部换成 `VARCHAR`。
4. 代价：**跨章节的全表统计/模糊搜索会广播到 10 张表**；所以搜索走了 ES，统计走 `book_index`/业务表而不是正文表。

### 4.5 章节内容双存储（可扩展设计）

`application-common-dev.yml`：

```yaml
content:
  save:
    storage: db      # db：存数据库分表；file：存 TXT 文本
    path: /Users/xxx/books
```

对应两个实现（Strategy 模式，按 `book_index.storage_type` 从 Map 里选）：

- `DbBookContentServiceImpl` → 走分表的 `book_content`
- `FileBookContentServiceImpl` → 读 `{path}/{bookId}/{indexId}.txt`

面试点：**为什么做两套？** 正文是最大的数据量（一本书几十 MB），全放 MySQL 会撑爆磁盘和备份；TXT 存储适合大体量、冷数据，数据库只存章节元信息。代价是备份/迁移变复杂，且 TXT 要处理编码。

---

## 5. 核心业务流程（面试主战场）

> 每条流程都按「入口 → 步骤 → 涉及表 → 关键代码」写，方便你复述成故事。

### 5.1 打开首页（`GET /`）

**入口**：`PageController.index()`（`novel-front/.../page/PageController.java`）

**步骤**：

1. 用 `CompletableFuture.supplyAsync(..., threadPoolExecutor)` **并行**跑两个任务：
   - `BookService.listBookSettingVO()`：查 `book_setting` 表（首页推荐位配置：轮播、点击榜、新书榜、更新榜、分类推荐）
   - `NewsService.listIndexNews()`：查首页新闻
2. `model.addAttribute("bookMap" / "newsList")`，返回模板 `index`
3. 榜单数据有缓存（见 6.2）：点击榜 5000s、新书榜 3600s、更新榜 600s、新闻 12h

**为什么并行**：首页要聚合 5~6 块数据，串行执行 RT 叠加；并行后 RT 取决于最慢的那个。

### 5.2 搜索

**两条路径**（`BookServiceImpl.searchByPage`）：

- `spring.elasticsearch.enable=0`（默认）→ **MySQL LIKE 模糊查询**（按书名/作者/分类拼动态 SQL）
- `=1` → `SearchServiceImpl.searchBook()` 走 ES：索引 `novel`、type `book`，`bookName` / `authorName` / `bookDesc` / `catName` 都用 `ik_smart` 分词，并带 `boost`（书名 2.0 > 作者 1.9 > 分类 1.0 > 简介 0.1），命中越靠前

**索引怎么建**：`doc/es/index_create.txt`，执行 `PUT /novel {...}` 建索引。

**ES 数据怎么同步**：

- 全量：`SearchServiceImpl.importToEs(book)` 单条写入
- 增量：`BookToEsSchedule`（`@Scheduled(fixedRate = 60_000)` 每分钟）按 `lastIndexUpdateTime` 拉新增/更新的书批量导入；用缓存 `esTransLock`（20 分钟）做运行锁，防止多实例重复跑
- 点击量：`UPDATE-ES-QUEUE` 消费，同一本书 **1 小时最多同步一次**（`esIsUpdateVisit+bookId`，TTL 1h）

### 5.3 书籍详情页（`GET /book/{bookId}.html`）

**步骤**：`PageController.bookDetail()` 并行加载「书籍信息」+「评论列表」，然后渲染 `book/book_detail`。

**点击量**（`BookController.addVisitCount`，前端阅读时异步上报）：

- 开了 MQ（`spring.rabbitmq.enable=1`）→ 发到 fanout 交换机 `ADD-BOOK-VISIT-EXCHANGE`
  - `UPDATE-DB-QUEUE`：**攒够 10 次**（`Constants.ADD_MAX_VISIT_COUNT`）才写一次库，写后清缓存 → 这就是"削峰"
  - `UPDATE-ES-QUEUE`：同步点击量到 ES（每书每小时一次）
- 没开 MQ → 直接 `bookService.addVisitCount(bookId, 1)` 同步更新

**代码里留下的坑（面试可以说"我知道这里有隐患"）**：`BookVisitAddListener.updateDb` 里读改写 `visitCount` 没有加锁，代码注释明确写了 TODO——多实例/并发时计数会丢；作者原话是"点击量不重要，可丢"，所以先用 Redisson 分布式锁（依赖已引入）留了注释。

### 5.4 阅读章节（`GET /book/{bookId}/{bookIndexId}.html`）★ 最值得讲

**步骤**（`PageController.bookContent`）：

1. 并行：查书籍 `queryBookDetail`、查章节索引 `queryBookIndex`
2. 依赖章节的两条链路用 `thenApplyAsync` 串起来（并行且不阻塞）：
   - 上一章 ID、下一章 ID（按 `index_num` 查）
   - **章节正文**：`bookContentServiceMap.get(bookIndex.getStorageType()).queryBookContent(...)`
     即根据 `storage_type` 选「数据库分表实现」或「TXT 文件实现」（策略模式）
3. 并行判断是否需要购买：`is_vip == 1` → 未登录或没买过（`queryIsBuyBookIndex`）→ `needBuy = true`
4. 全部 `future.get()` 后塞进 Model，渲染 `book/book_content` 模板

**分表路由**：查正文时 Sharding-JDBC 按 `index_id % 10` 路由到 `book_contentN`，单表查询，不需要扫全部章节。

**页面上的交互**：`needBuy` 为 true 时模板渲染购买按钮；购买走 5.9。

### 5.5 注册与登录（前台）

**注册**（`UserController`）：

1. 校验图形验证码：`cacheService.get(RandomValidateCodeUtil.RANDOM_CODE_KEY)`（Redis/EhCache 存的验证码）
2. 密码 `MD5Util.MD5Encode(password, UTF-8)` 后入库（**无盐**，这是可以主动说的改进点）
3. 生成 `UserDetails{id, username, nickName}` → `JwtTokenUtil.generateToken`

**JWT 设计**（`core/utils/JwtTokenUtil.java`）：

- 签名算法 **HS512**，密钥 `jwt.secret`（代码默认 `novel!#20191230`），有效期 `jwt.expiration=604800` 秒 = **7 天**
- payload 的 `sub` 字段不是用户名，而是 **`UserDetails` 序列化成的 JSON**（所以解 token 后直接拿到用户信息，不用查库）
- token 下发到 **Cookie `Authorization`**；接口调用也支持请求头 `Authorization`（`BaseController.getToken` 先取 Cookie 再取 Header）
- 每个需要登录的接口通过 `BaseController.getUserDetails(request)` 手动解析 → **没有全局拦截器强制鉴权**，是"在方法里取，取不到就是未登录"

**面试点**：无状态、跨域友好、不用 Session；但缺点是不可主动失效（改密码/封号不能立刻踢下线）、token 里信息不能太敏感、需要 HTTPS 防窃取。

**配套细节（被追问时用）**：

- **续期**：`POST /user/refreshToken`，`canRefresh` 判断未过期 → 重置 `created` 重新签发、过期时间顺延；前端**每次页面加载都会调一次**并回写 cookie
- **token 存哪里**：非 HttpOnly 的 cookie（JS 可读，方便前端拼 header），勾选"自动登录"才给 7 天过期
- **权限边界**：`WebMvcConfig` 只注册了日期转换器，**没有登录拦截器**；每个 Controller 自己调 `getUserDetails()`，未登录返回 `RestResult.fail(NO_LOGIN)`（**code 1001**），前端看到 1001 就跳登录
- **退出登录**：前端删 cookie 而已，服务端没有黑名单（JWT 的固有问题）

### 5.6 书架与阅读历史

- 书架：`user_bookshelf(user_id, book_id, pre_content_id)`；`addToBookShelf` / `removeFromBookShelf` / `listBookShelfByPage`；`pre_content_id` 记录上次读到的章节，用于"继续阅读"
- 阅读历史：`user_read_history`，`addReadHistory` 带 `@Transactional`，进入章节时记录
- 详情页会调 `queryIsInShelf` 决定按钮显示"加入书架/已在书架"

### 5.7 书评（本版本没有段落评论）

- 表：`book_comment`（`book_id`、`create_user_id`、`comment_content`、`reply_count`、**`audit_status`**、`create_time`）+ `book_comment_reply`（回复）
- **书评有审核流**：`audit_status` 0 待审核 / 1 通过 / 2 不通过，只有通过的书评才会展示（后台审核入口在书籍管理里，本版本没有独立 CommentController）
- 接口：`BookController.addBookComment`（前端 `/book/addBookComment`，XSS 过滤器专门放行了这个 URL）
- 列表：`listCommentByPage` 分页，`BookCommentVO` 里用户名做了脱敏序列化（`core/serialize/CommentUserNameSerialize`）
- 详情页并行加载评论列表

> ⚠️ **别讲错**：段落评论、书单广场是上游 v5/v6 才有的功能；你这个版本只有**书评 + 审核**。面试官如果按最新版问，就答"那是新版本的功能，我基于的 v3.6 只有书评"。

### 5.8 充值（支付宝）

**下单** `POST /pay/aliPay`（未登录直接重定向登录页）：

1. `OrderServiceImpl.createPayOrder(payChannel=1, payAmount, userId)`
2. 生成 `out_trade_no = yyyyMMddHHmmssSSS + 随机数`，落 `order_pay`（**`pay_status` 默认 2 = 待支付**；DDL 注释：0 失败 / 1 成功 / 2 待支付）
3. 拼 `AlipayTradePagePayRequest`（`product_code=FAST_INSTANT_TRADE_PAY`、`total_amount` 单位是**元**、`notify_url`/`return_url` 来自 `AlipayProperties`）
4. `pageExecute().getBody()` 把支付宝表单 HTML 直接写回响应，浏览器自动跳转

**回调** `POST /pay/aliPay/notify`：

1. `AlipaySignature.rsaCheckV1` **验签**，通过后取 `out_trade_no` / `trade_no` / `trade_status`
2. `updatePayOrder`：`if (payStatus != 1)` 才处理；`trade_status ∈ {TRADE_SUCCESS, TRADE_FINISHED}` → 订单置 `pay_status=1`，**用户余额 + `totalAmount * 100`**（1 元 = 100 屋币）
3. 返回纯文本 `success` / `fail` 给支付宝

**代码里明确存在的短板（面试可以主动讲，体现你读过代码）：**

- ⚠️ 回调**只验签，没有比对金额/`seller_id`/`app_id`**——代码注释里自己列了"建议添加"，说明作者也知道没做全
- 幂等只靠 `pay_status != 1` 判断，并发回调不是原子操作（改进：`update ... where out_trade_no=? and pay_status=2` 判断影响行数）
- 微信支付只有前端图标（点击提示"暂未开通"），后端只有支付宝一种渠道
- 订单状态：`2 待支付 → 1 支付成功`，`0 支付失败` 在代码里没有写入路径

### 5.9 购买 VIP 章节

`POST /user/buyBookIndex`（`UserBuyRecord`：bookId/bookName/bookIndexId/bookIndexName）→ `UserServiceImpl.buyBookIndex`，`@Transactional`：

1. **价格以服务端为准**：Controller 用 `bookService.queryBookIndex(...).getBookPrice()` **覆盖**前端传来的 `buyAmount`（防篡改价格，这点做得对）
2. 查 `user.account_balance`，余额 < 价格 → 抛 `BusinessException(USER_NO_BALANCE 1007)`
3. 插入 `user_buy_record`（**唯一键 `user_id + book_index_id`**，同一章买不了第二次，DB 层兜底）
4. 把余额改成 `balance - buyAmount`（`update user set account_balance = ?`）

**价格来源**：作者发章节时按「字数 × 单价」算出 `book_index.book_price`（见 5.10 公式），下单时直接读这个字段。

**面试追问「并发买同一章会不会扣两次钱/余额扣穿」**：

- 重复购买：唯一键会拦下来（第二次插入失败 → 事务回滚 → 不会扣钱）✅
- 但**余额扣减是"先查后改"**，同一用户并发买**两本不同书**时可能扣穿（两个事务都读到同一个余额）——这是真实缺陷。改进：`update user set account_balance = account_balance - ? where id=? and account_balance >= ?`（原子扣减 + 判断影响行数）、或 `SELECT ... FOR UPDATE`、或 Redisson 分布式锁（依赖已引入）

**面试追问「并发买同一章会不会扣两次钱/余额扣穿」**：会——这是**先查后改**的经典竞态（代码里没有行锁、没有乐观锁）。改进方向：`update user set account_balance = account_balance - ? where id=? and account_balance >= ?`（原子扣减 + 判断影响行数）、或 Redisson 分布式锁（依赖已有）、或给 `user_buy_record` 加 `(user_id, book_index_id)` 唯一索引防重复购买。

### 5.10 作家入驻与创作

**入驻（需要邀请码）**：`/author/register.html`（普通表单 POST，不是 ajax）

- 前置：必须已登录会员
- 校验 `author_code` 表邀请码：`is_use=0` 且 `validity_time > now`
- 通过 → `author` 表写笔名 + 关联 `user_id`，邀请码置为已用；`@Transactional`
- 笔名唯一性 `checkPenName`

**准入两道关**（作家没有独立登录，复用会员 JWT）：

1. 页面级：`PageController.module2`（`/author/**`）未登录 → 重定向登录页；已登录非作者 → 重定向入驻页
2. 接口级：每个写接口调 `checkAuthor()`，未登录抛 `NO_LOGIN`，作者被封禁（`author.status==1`）抛 `AUTHOR_STATUS_FORBIDDEN 4002`

**发书** `POST /author/addBook`：

- 校验同笔名下书名唯一（重复抛 `BOOKNAME_EXISTS 4003`）
- `bookDesc` 单独用 `@RequestParam` 接收（避免 Spring 自动去首尾空白），落库前 `\n→<br>`、空格→`&nbsp;`
- 强制初始化 `visit_count=0`、`word_count=0`、`score=6.5`、`last_index_name=""`
- 封面上传：`POST /file/picUpload` → `POST /author/updateBookPic`

**发章节** `POST /author/addBookContent {bookId, indexName, content, isVip}`（`@Transactional`）：

1. 校验书属于本人（**注意：不属于时是静默 return，不报错**）
2. `IdWorker.INSTANCE.nextId()` 生成章节 ID
3. 更新 `book`：`last_index_id/name/update_time`、`word_count += 新增字数`（`StringUtil.getStrValidWordCount` 计算有效字数）
4. 算价：`bookPrice = 字数 × value / word-count 规则`（`BigDecimal` + `RoundingMode.DOWN`，即 5 币/千字）
5. `index_num = 上一章 index_num + 1` → 插 `book_index`（含 `book_price`、`storage_type` 默认 `db`）→ 插 `book_content{index_id%10}`
6. 改章节 `updateBookContent`（**只重算章节字数/价格，没有回写 `book.word_count`，会不一致**）、改章节名 `updateIndexName`、删章节 `deleteIndex`

**上下架**：`POST /author/updateBookStatus(bookId, status)`

### 5.11 作者收益结算（数据一致性话题）

**配置**（`application.yml` + `AuthorIncomeProperties`）：

| 配置 | 值 | 含义 |
|---|---|---|
| `author.income.tax-rate` | 0.9 | 扣税后所得比例 |
| `author.income.share-proportion` | 0.7 | 平台与作者分成比例（作者 70%） |
| `author.income.exchange-proportion` | 0.01 | 币兑换人民币比例 |

**日结**：`DailyIncomeStaSchedule`，`@Scheduled(cron = "0 0 0 * * ?")` 每天 00:00

- 以 `create_time` 为游标**分批**处理作家（每批 10 个，`do-while` 直到不足一批）
- 按作品统计前一天：订阅人数（`count distinct user`）、订阅次数、消费金额
- 写 `author_income_detail`，`book_id=0` 的那条表示"作家当日汇总"
- 幂等：`queryIsStatisticsDaily(bookId, date)` 先查是否已统计

**月结**：`MonthIncomeStaSchedule`，`@Scheduled(cron = "0 0 2 1 * ?")` 每月 1 号 02:00

- 汇总上月 `author_income_detail.income_account`，按配置计算：`× share-proportion(0.7)`、`× tax-rate(0.9)`、`× exchange-proportion(0.01)`，代码里还有一次 `×100`
- 写 `author_income`（`pre_tax_income` 税前 / `after_tax_income` 税后 / `pay_status` 结算状态 / `confirm_status` 确认状态）

**面试点**：定时任务 + 幂等判断 + "先明细后汇总"的分层思想；分批游标避免一次加载全量作家。

### 5.12 平台后台（运营侧）

**登录**：`/login`（`LoginController`）

1. 图形验证码（Session 存 `RANDOMCODEKEY`）
2. 密码：**Shiro `SimpleHash("md5", 密码, 盐=username+"1qazxsw2", 2 次迭代)`**（不是 BCrypt）→ `UsernamePasswordToken` → `subject.login`
3. Shiro 认证成功写 Session；**Session 存 EhCache（默认，重启掉登录）或 Redis（`spring.cache.type=redis` 时）**，`server.session-timeout=18000` 秒 ≈ 5 小时
4. 预置账号：`sys_user` 里 seeded 的 `admin`，密码就是 **`admin`**（已用该算法验证 hash 匹配），首次登录后记得改

**权限模型（RBAC + 数据权限）**：

| 表 | 作用 |
|---|---|
| `sys_user` / `sys_role` / `sys_user_role` | 用户-角色 |
| `sys_menu` / `sys_role_menu` | 菜单 + 按钮权限，`perms` 字段如 `novel:book:add` |
| `sys_dept` | 部门/组织 |
| `sys_data_perm` / `sys_role_data_perm` | 数据权限（哪些部门的数据可见） |

- 接口鉴权：`@RequiresPermissions("novel:book:add")`（Shiro 注解），每个 Controller 的增删改查都有独立权限点
- 菜单渲染：登录后 `menuService.listMenuTree(userId)` 返回树，前端 Layui 渲染
- 数据权限：**演示性质**——`DataPermInterceptor`（MyBatis 插件）改写 SQL 字符串，且只对方法名以 `ByPerm` 结尾的语句生效；全仓库只有 `sys_user` 的 `listByPerm/countByPerm` 命中，**book/order_pay 等业务表根本没接入**。面试可主动指出这一点（"框架搭好了但业务没用起来"）

**业务功能**（按 Controller）：

| 功能 | 权限前缀 | 真实情况（重要） |
|---|---|---|
| 书籍管理 | `novel:book:*` | 标准 CRUD（`/list`、`/add`、`/edit`、`/save`、`/update`、`/remove`、`/batchRemove`）——**是代码生成器产物，没有业务校验、没有事务、没有审核动作**；上下架只是改 `book.status`（0 入库 / 1 上架），`book` 表**没有** audit 字段 |
| 分类管理 | `novel:category:*` | ⚠️ `CategoryController` 管的是 **`news_category`（新闻类别）**，不是小说分类 `book_category`——**小说分类在后台没有维护入口**（只能改库） |
| 作家管理 | `novel:author:*` | 作者列表/编辑/删除，没有入驻审核流程（入驻靠邀请码在作家端完成） |
| 邀请码 | `novel:authorCode:*` | 邀请码生成、启用/停用、有效期 |
| 新闻管理 | `novel:news:*` | 新闻 CRUD（发布后**不会自动清前台首页缓存**） |
| 会员管理 | `novel:user:*` | 会员 CRUD、封禁（`user.status`），没有余额调整接口 |
| 订单管理 | `novel:pay:*` | 充值订单查询/编辑，没有退款流程 |
| 统计 | `novel:stat/*` | `countSta`（用户数等）、`tableSta`（按表统计） |
| 字典/文件/日志 | `common:*` | 通用能力 |
| 代码生成器 | `sys:gen:*` | 读 `information_schema` + Velocity 模板生成代码 |

> ⚠️ **初始化 SQL 的坑**：`sys_menu` 只给「作家管理」「新闻管理」建了菜单行，`novel:book / novel:user / novel:pay / novel:stat` **没有对应菜单记录**——接口能调，但后台左侧菜单点不到，需要手工往 `sys_menu` 插数据（面试如果被问"后台怎么加菜单"这就是现成答案）。

**后台技术栈与前台不同**：admin 用**传统 MyBatis XML Mapper**（`${sort} ${order}` 拼接、手动 count+limit 分页）+ Shiro；common/crawl 用 MyBatis Dynamic SQL DSL + PageHelper。

**操作日志**：`@Log("描述")` 注解 + `LogAspect`（`@Around`，`@Async` 写 `sys_log`）。但**覆盖不全**：`novel/*` 的业务 CRUD 基本没加注解，只有部分系统接口有——审计能力有限（面试可主动说）。

**代码生成器**：`GeneratorController` + `sys_gen_table` / `sys_gen_table_column`，读 MySQL `information_schema` 表结构 → 生成 entity / mapper / service / controller（模板在 `novel-admin/src/main/resources` 下，未逐一确认）。

### 5.13 爬虫采集（novel-crawl）★ 这个项目的特色

**配置阶段**（运营在后台配）：

- `crawl_source`：采集源（名称、状态、`crawl_rule` JSON）
- 规则是 `RuleBean` 的 JSON 序列化，字段全是**正则表达式**：`updateBookListUrl`（更新列表）、`bookListUrl`（分类列表，支持 `{catId}`/`{page}` 占位）、`bookIdPatten`、`totalPagePatten`、`bookDetailUrl`、`bookNamePatten`、`authorNamePatten`、`picUrlPatten`、`statusPatten`、`scorePatten`、`visitCountPatten`、`descStart/descEnd`、`bookIndexUrl`、`indexIdPatten`、`indexNamePatten`、`bookContentUrl`、`contentStart/contentEnd`、`picUrlPrefix`

**启动采集**（`CrawlServiceImpl.openOrCloseCrawl`）：

1. 开启：读规则 → **按分类 1~7 各起一个线程**（`new Thread(() -> parseBookList(catId, rule, sourceId))`）→ 线程 ID 集合存 Redis `runningCrawlTreadDataKeyPrefix + sourceId`
2. 关闭：改状态 → 从 Redis 取线程集合 → **`thread.interrupt()`** 逐个中断 → 线程内用 `Thread.currentThread().isInterrupted()` 检查退出
3. `CrawlThreadMonitor`（`@Scheduled(fixedRate=5min)`）兜底监控线程状态

**采集一本书**（`parseBookList` → `parseBookAndSave`）：

1. 拼分类列表 URL → `HttpUtil.getByHttpClientWithChrome`（Chrome UA 请求）→ 正则找 `bookId`、总页数
2. `CrawlParser.parseBook` 解析详情：书名/作者/分类/简介/封面/状态/评分/点击量
3. 查重：`queryBookByBookNameAndAuthorName`——**只新增不覆盖**；已存在则只更新采集相关字段（`updateCrawlProperties`）
4. 新书：雪花 ID `IdWorker.nextId()` → 设 `crawl_source_id`/`crawl_book_id` → 解析章节目录 + 每章正文 → `saveBookAndIndexAndContent(book, indexList, contentList)` 批量入库

**单本任务**：`crawl_single_task`（`task_status=2` 待处理，`exc_count` 最大 5 次，成功或到 5 次停止）

**调度方式（不是 Quartz）**：

- `novel-crawl` 启动时用 `ServletContextListener` 起后台线程 + `sleep` 循环：**老书增量约 10 分钟一轮、单本任务约 1 分钟一轮**
- `CrawlThreadMonitor`（`@Scheduled(fixedRate=5min)`）做线程/任务状态回收
- `crawl_batch_task` 表**存在但代码零引用**——批量采集任务实际没实现（面试别硬说做了批量采集）

**代码里能指出的问题（加分项）**：

- `PatternFactory` 用普通 `HashMap` 缓存预编译正则，**7 个采集线程并发写没有同步** → 并发下可能丢缓存/结构损坏
- 单本任务重试计数用 `ThreadLocal`，**用完没有清理**，线程复用时会串号（bug）
- **无代理池、无 IP 限频**，纯 `Thread.sleep` 节流
- 正文存储标记：爬虫按 `content.save.storage` 给新章节打 `storage_type`；注意 Bean 名是 `txt`，而 yml 注释写的是 `file`——**配置写错会找不到 Bean**

**失败处理**：单本异常按本捕获、不中断整批；失败次数到 5 次停止任务。

### 5.14 定时任务与缓存刷新清单

| 任务 | 周期 | 作用 | 缓存 |
|---|---|---|---|
| `BookToEsSchedule` | 每 60s | 增量同步书到 ES | `esTransLock`(20min)、`esLastUpdateTime` |
| `CrawlPicTransSchedule` | 每 10min | 爬虫图片转存到自己的存储 | — |
| `DailyIncomeStaSchedule` | 每天 00:00 | 作者日收益统计 | 幂等查重 |
| `MonthIncomeStaSchedule` | 每月 1 号 02:00 | 作者月收益汇总 | 幂等查重 |
| `CrawlThreadMonitor` | 每 5min | 采集线程存活监控 | Redis 线程集合 |

**手动清缓存**：`CacheController`（后台/运维用），清 `indexBookSettingsKey`、`indexNewsKey`、`indexLinkKey` 等首页缓存。

---

## 6. 技术实现细节（被追问时用）

### 6.1 鉴权与安全

| 位置 | 机制 | 细节 |
|---|---|---|
| 前台 | **JWT**（JJWT） | HS512，7 天，`sub` 存 UserDetails JSON，Cookie/Header 双通道 |
| 后台 | **Shiro** + Session | 用户名加盐 MD5，验证码，`@RequiresPermissions` 权限点，Session 存 Redis 可集群 |
| 防 XSS | `XssFilter` + `XssHttpServletRequestWrapper` | 只拦截配置的 `xss.urlPatterns`（评论、发书、发章等），排除 `xss.excludes` |
| 密码 | 前台 MD5 无盐 / 后台 MD5(username+password) | 都是弱方案，面试可主动说"应升级 BCrypt + 随机盐" |
| 静态资源 | `NovelFilter` | 把图片路径映射到本地存储目录；同时做 **PC/WAP 识别** |

**PC/WAP 识别**（`NovelFilter` + `BrowserUtil`）：

- 请求进来判断 UA 是否手机 → `cacheService.set("templateDirKey"+clientId, "mobile/" 或 "", 1 天)`
- 渲染时 `ThreadLocalUtil.getTemplateDir()` 读缓存前缀 → 拼接模板名（`mobile/xxx` vs `xxx`）
- 同一个 HTML 模板名，PC/WAP 两套目录，业务代码无感知

### 6.2 缓存体系

**抽象层**：`CacheService` 接口 + 两个实现 `EhCacheServiceImpl` / `RedisServiceImpl`，通过配置切换（默认 EhCache，一行配置换 Redis）。

**Key 清单**（`CacheKey.java`）：

| Key | 内容 | TTL | 更新时机 |
|---|---|---|---|
| `indexBookSettingsKey` | 首页推荐位配置 | — | 后台改配置后手动删 |
| `indexClickBankBookKey` | 点击榜 | 5000s | 过期重建 |
| `indexNewBookKey` | 新书榜 | 3600s | 过期重建 |
| `indexUpdateBookKey` | 更新榜 | 600s | 过期重建 |
| `indexNewsKey` | 首页新闻 | 12h | 后台发新闻后手动删 |
| `indexLinkKey` | 友链 | 24h | 过期 |
| `templateDirKey+clientId` | PC/WAP 模板前缀 | 24h | 过滤器写入 |
| `bookAddVisitCount+bookId` | 点击量累加器 | 无（手动删） | 满 10 次写库后删 |
| `esIsUpdateVisit+bookId` | ES 点击量节流 | 1h | 消费后 |
| `esLastUpdateTime` | ES 增量同步水位 | 无 | 同步后更新 |
| `esTransLock` | ES 同步互斥锁 | 20min | 同步结束删 |
| `randomValidateCodeKey` | 图形验证码 | 5min | 校验后删（**全局单 key，不区分会话**） |
| `runningCrawlTreadDataKeyPrefix+sourceId` | 采集线程集合 | 无 | 开关采集时 |
| `testParse` | 爬虫规则测试缓存 | — | 规则测试 |

**面试点**：典型 Cache-Aside；一致性问题用"短 TTL + 后台手动清缓存"兜底；首页这类读多写极少的数据最适合缓存。

### 6.3 分库分表（Sharding-JDBC）

- 依赖：`sharding-jdbc-spring-boot-starter`
- 配置在 `novel-common/src/main/resources/application-common-*.yml`
- 规则：`book_content` → `ds0.book_content${index_id % 10}`，分片键 `index_id`，主键生成列 `id`
- 原理（面试可讲）：JDBC 层拦截 SQL → **解析 SQL 拿到分片键 → 路由到目标表 → 改写表名 → 执行 → 结果归并**
- 限制：不支持跨库 JOIN、分页/排序/聚合要归并；`LONGVARCHAR` 类型不兼容（源码注释里踩过）
- 为什么不用分库：单库单表 10 张足够，分库会增加运维和事务复杂度；配置里 `names: ds0` 只保留一个库，注释里留了 `ds1` 说明预留了水平扩容能力

### 6.4 搜索（ElasticSearch）

- 客户端：**jest**（`io.searchbox`），配置 `spring.elasticsearch.jest.uris`
- 索引：`novel` / type `book`，字段见 `doc/es/index_create.txt`
- 分词：**ik_smart**（中文），`bookName`(boost 2.0)、`authorName`(1.9)、`catName`(1.0)、`bookDesc`(0.1)、`lastIndexName`(0.1)
- 写入：`importToEs` → `Index.Builder(EsBookVO).index("novel").type("book").id(bookId)`
- 读取：`SearchServiceImpl.searchBook` 拼 bool query（关键词 + 分类 + 状态 + 字数范围等），高亮/分页
- 一致性：**最终一致**（增量任务 + 点击量节流同步），允许短暂延迟；找不到就降级回 MySQL

### 6.5 消息队列（RabbitMQ）

- 默认关闭（`spring.rabbitmq.enable: 0`），打开后由 `@ConditionalOnProperty` 装配
- 结构：`FanoutExchange ADD-BOOK-VISIT-EXCHANGE` → `UPDATE-DB-QUEUE`、`UPDATE-ES-QUEUE`
- 削峰逻辑：点击量先攒在缓存，满 10 次批量 `update book set visit_count = visit_count + N`
- 为什么 fanout：同一份"点击事件"要被 DB 和 ES 两个消费者分别处理，解耦

### 6.6 异步与线程池

- `ThreadPoolConfig` + `ThreadPoolProperties`：核心 10、最大 20、队列 100、keepAlive 10s
- 用处：首页并行加载、详情页并行、阅读页并行链路
- 采集：每分类一个裸线程（不是线程池），用 interrupt 控制停止
- `SpringAsyncConfig`（后台模块）提供 `@Async` 线程池

### 6.7 模板与多端

- 开发环境：`classpath:/templates/`（53 个 Thymeleaf 模板）
- 生产环境：`thymeleaf.prefix: file:${user.dir}/templates/${templates.name}/html/`，静态资源 `file:${user.dir}/templates/${templates.name}/static/` → **换主题不用重新打包**
- 内置主题：`templates/blue`、`templates/dark`、`templates/orange`
- 多端：`ThreadLocalUtil.getTemplateDir()` 前缀 `mobile/`，静态资源 `static/mobile`

### 6.8 文件与图片

- 三套实现 + 配置切换：`LocalFileServiceImpl` / `OssFileServiceImpl` / `FastDfsFileServiceImpl`
- 配置：`pic.save.type`（1 不保存用远程图 / 2 存自己的存储）、`storage: local|oss|fastdfs`、`path`
- 爬虫图片转存：`CrawlPicTransSchedule` 每 10 分钟把外链封面下载到本地/OSS
- 上传限制：后台 `multipart.max-file-size: 30Mb`

### 6.9 统一返回、分页、异常

- 返回：前台 `RestResult<T>`（`code/msg/data`），后台 `R`（Layui 风格）。**这两个类来自第三方依赖 `io.github.xxyopen:xxy-model / xxy-web / xxy-util 1.0.0`，源码不在本仓库**——面试如果被追问实现，就说"项目统一用作者封装的 xxyopen 基础库，`RestResult`/`PageBean`/`PageBuilder`/`IdWorker`/`MD5Util` 都在里面"
- 分页：`PageHelper.startPage(page,pageSize)` + `OrderByHelper.orderBy(...)` + `PageBuilder.build(list)` → `PageBean`；接口入参统一 `curr` / `limit`
- 异常：`BusinessException` + `ResponseStatus` 枚举；**REST 异常到 `RestResult` 的转换由 `xxy-web` 提供**（不在仓库）；`PageExceptionHandler` 只覆盖 `com.java2nb.novel.page` 包，异常时返回 404 视图
- 错误码表（背几个常用的，面试问到会说）：

| 码 | 含义 | 码 | 含义 |
|---|---|---|---|
| 1001 | 未登录 | 3001 | 已评价过 |
| 1002 | 验证码错误 | 4001 | 邀请码无效 |
| 1004 | 用户名或密码错误 | 4002 | 作者被封禁 |
| 1007 | 余额不足 | 4003 | 同名小说 |
| 1005 | 两次密码不一致 | 5001 | 小说已存在 |
| 1006 | 旧密码错误 | 9001 | ES 查询异常 |
- 参数日期转换：`DateConverter`

### 6.10 日志

- 前台/后台各自 `logback-spring.xml`，按天滚动
- 后台操作日志：`@Log` 注解 + `LogAspect` 切面写 `sys_log`；`WebLogAspect` 记请求日志

### 6.11 代码生成器

- `GeneratorController`：选表 → 读 `information_schema` → 生成 entity / mapper / service / controller
- 元数据表：`sys_gen_table`、`sys_gen_table_column`、`sys_gen_columns`
- 面试点：本质是模板引擎 + 元数据驱动；能省 70% CRUD 代码，但复杂业务仍要手写

### 6.12 事务与并发（主动暴露问题最加分）

| 场景 | 现状 | 风险/改进 |
|---|---|---|
| 购买章节 | `@Transactional`，先查余额再更新；购买记录有 `(user_id, book_index_id)` 唯一键 | 重复购买被唯一键挡住 ✅，但余额扣减是"先查后改"，并发买不同书可能扣穿 → 原子 SQL/乐观锁/分布式锁 |
| 支付回调 | `@Transactional` + `payStatus != 1` 判断 | 并发回调重复处理 → `where pay_status=2` 条件更新；且**未校验金额/seller_id/app_id** |
| 点击量 | 缓存累加，满 10 次写库 | 多实例计数丢失（代码注释 TODO）→ Redisson 锁；且刷页即 +1、无去重，榜单可刷 |
| 验证码 | `randomValidateCodeKey` **全局单 key** | 不区分会话/客户端，A 的验证码 B 能用 → 应拼 sessionId/deviceId |
| ORDER BY | `sort`/`orderBy` 参数**直接来自客户端**（`OrderByHelper.orderBy(sort+" desc")`） | SQL 注入面（OrderByHelper 是否白名单未确认）→ 服务端枚举映射 |
| 章节修改 | `updateBookContent` 只更新章节字数和价格 | **不回写 `book.word_count`**，全书字数与章节之和不一致 |
| 评论用户名脱敏 | `substring(0,4)+"****"+substring(len-3)` | 用户名 <4 位会 `StringIndexOutOfBoundsException` |
| 富文本输出 | 正文/简介走 `th:utext`，写库只做 `\n→<br>` 转义 | XSS 过滤只覆盖 6 个 URL，正文型 XSS 依赖 `XssHttpServletRequestWrapper` |
| 采集线程 | `Thread.interrupt()` | 阻塞在 HTTP 读时中断不生效 → 设置 connect/read timeout |
| 定时任务 | 无分布式调度 | 多实例会重复执行 → XXL-Job/Elastic-Job + 幂等表 |
| 后台业务 | 7 个 Controller 是生成器产物，**Service 无 `@Transactional`、无业务校验、无审核流** | 改状态/改数据没有事务保护，异常时可能半更新 |
| 数据权限 | `DataPermInterceptor` 只对 `*ByPerm` 生效，仅 `sys_user` 接入 | 业务表（书/订单）数据权限形同虚设 |
| 后台菜单 | `sys_menu` 缺 `novel:book/user/pay/stat` 菜单行 | 接口可用但页面点不到，需手工插数据 |
| 缓存失效 | EhCache 实现 `set()` 把 cache 设为 `eternal=true` | TTL 可能整体失效（待实测），只能靠手动 `/cache/refresh` |
| ES 索引 | 建索引脚本是 ES6 带 type 的写法，写入代码用 `_doc` | 新版 ES 可能不兼容（需实测） |
| 正则缓存 | `PatternFactory` 用 `HashMap` 缓存 Pattern，采集线程并发写无同步 | 并发下缓存可能丢失/损坏 |

---

## 7. 关键代码索引（面试指路用）

| 模块 | 类 | 职责 |
|---|---|---|
| common | `core/cache/CacheService` + `EhCacheServiceImpl` / `RedisServiceImpl` | 缓存抽象与两套实现 |
| common | `core/cache/CacheKey` | 所有缓存 key 常量 |
| common | `core/advice/PageExceptionHandler` | 页面异常统一处理 |
| common | `core/enums/ResponseStatus` | 业务错误码 |
| common | `entity/*` + `mapper/*` | 40+ 表对应的实体与 MyBatis Dynamic SQL Mapper |
| front | `page/PageController` | 所有页面路由（首页/详情/目录/阅读/评论/新闻/作者注册） |
| front | `controller/BookController` | 书籍接口：搜索、榜单、评论、点击量上报 |
| front | `controller/UserController` | 注册/登录/书架/阅读历史/信息/反馈 |
| front | `controller/AuthorController` | 作家：笔名、发书、发章、改章、收益 |
| front | `controller/PayController` | 支付宝下单与异步回调 |
| front | `core/utils/JwtTokenUtil` | JWT 生成/解析/校验 |
| front | `core/filter/NovelFilter` / `XssFilter` | PC/WAP 识别 + 图片映射 / XSS 防护 |
| front | `core/listener/BookVisitAddListener` | MQ 消费：点击量聚合落库 + ES 同步 |
| front | `core/schedule/*` | 4 个定时任务 |
| front | `service/impl/BookServiceImpl` | 书籍/章节/评论/榜单核心逻辑 |
| front | `service/impl/UserServiceImpl` | 用户/书架/余额/购买 |
| front | `service/impl/AuthorServiceImpl` | 作者/收益统计 |
| front | `service/impl/DbBookContentServiceImpl` / `FileBookContentServiceImpl` | 正文双存储策略 |
| front | `service/impl/SearchServiceImpl` | ES 写入与搜索 |
| front | `service/impl/OrderServiceImpl` | 订单创建与支付回调处理 |
| admin | `system/controller/LoginController` | 后台登录/验证码/登出 |
| admin | `common/config/ShiroConfig` / `SecuityConfig` | Shiro 安全配置 |
| admin | `common/aspect/LogAspect` | `@Log` 操作日志切面 |
| admin | `novel/controller/*` | 书籍/分类/作家/邀请码/新闻/会员/订单 |
| admin | `novel/controller/StatController` | 统计接口 |
| admin | `common/controller/GeneratorController` | 代码生成器 |
| admin | `system/*`（Menu/Role/User/Dept/DataPerm） | RBAC 与数据权限 |
| crawl | `core/crawl/CrawlParser` | 页面解析器（正则） |
| crawl | `core/crawl/RuleBean` | 规则模型（JSON 配置） |
| crawl | `core/crawl/PatternFactory` | 正则预编译缓存 |
| crawl | `service/impl/CrawlServiceImpl` | 采集调度、线程管理、入库 |
| crawl | `core/schedule/CrawlThreadMonitor` | 采集线程监控 |

---

## 8. 面试问答（27 题，按组背）

### A. 项目与架构

**1）用一分钟介绍项目？**
→ 抄 1.1 节的两分钟版本，压成 4 句：多端原创文学 CMS → 4 个子系统 → 核心能力（阅读/订阅/作家/后台/采集）→ 技术亮点（分表、ES、MQ 削峰、并行加载）。

**2）为什么拆成 4 个模块而不是单体或微服务？**
→ 按"发布节奏 + 职责"拆：前台/后台/采集的流量特征和发布频率都不同（前台要高可用、后台低频、采集可独立扩容），模块内共享 `common`；但仍是同一个 JVM 部署体系，**没引入分布式事务和注册中心**，成本可控。真要做微服务有 novel-cloud 演进版，会把用户、书籍、内容、订单拆成独立服务。

**3）前后台鉴权为什么用两套？（JWT vs Shiro Session）**
→ 前台面向公网、多端（PC/WAP/未来 App），无状态 JWT 天然适合、易水平扩展；后台是内部系统、有菜单/按钮/数据权限这种**强 RBAC**需求，Shiro 的 Session + 权限模型更成熟，且有验证码、会话超时等企业需求。

**4）项目里你认为最难的三个点？**
→ ① 章节正文分表后的"跨表统计/搜索"取舍（所以搜索交给 ES）；② 点击量高并发写库（MQ + 聚合 + 节流）；③ 支付/购买的并发一致性（现状有缺陷，改进方案见 6.12）——**这题是给你展示深度用的，别只说"业务复杂"**。

### B. 数据与存储

**5）为什么章节正文要分表？为什么按 index_id 分？**
→ 正文是最大数据量（一本书几十 MB，百万级章节），单表会撑爆；按 `index_id % 10` 分 10 张，阅读时按章节取模直接定位单表，避免扫多表；如果按 book_id 分会变成一章一章分散，目录/连载场景查询更差。

**6）分表后遇到什么问题？**
→ ① 不能跨表 JOIN/聚合，要看全文得广播 10 张表（所以搜索走 ES、统计走元数据表）；② Sharding-JDBC 对 `LONGVARCHAR` 不兼容，会抛 `NotSerializableException: StringReader`，必须改成 `VARCHAR`；③ 分页/排序要归并，深分页性能差。

**7）为什么有 MySQL 和 ES 两套搜索？**
→ 默认 LIKE 搜能跑但性能差（`%keyword%` 全表扫），量大后上 ES：ik 中文分词 + 字段 boost + 相关性排序。但 ES 是最终一致（增量任务同步），所以保留 MySQL 降级路径，ES 挂了还能搜。

**8）缓存怎么设计的？会有一致性问题吗？**
→ Cache-Aside：读缓存→没有回源→写缓存；写操作后删缓存（后台手动清 + 短 TTL 兜底）。首页榜单允许"秒级不一致"（TTL 10 分钟~12 小时）；点击量这种用缓存累加 + 批量落库，牺牲实时性换吞吐。真正强一致的数据（余额、订单）**不走缓存**。

**9）图片存储怎么做到三种切换？**
→ 接口 `FileService` + 三个实现，按 `pic.save.storage` 配置 + `@ConditionalOnProperty` 装配；业务只依赖接口。

### C. 关键流程

**10）用户阅读 VIP 章节的完整链路？**
→ 见 5.4：并行加载书籍/章节/正文/上下章 → 判断 `is_vip` → 未登录或未购买则 `needBuy=true` → 前端引导购买 → 购买成功后写 `user_buy_record` 并扣余额 → 再次访问时 `queryIsBuyBookIndex` 命中即可读。

**11）支付回调怎么防重复、防篡改？**
→ 防篡改靠支付宝 RSA 验签；防重复靠 `pay_status` 判断 + 事务；但并发下判断不是原子的，改进是条件更新 `where pay_status=0` 或唯一索引兜底（见 5.8 末）。

**12）作家收益怎么算、什么时候算？**
→ 日结每天 0 点、月结每月 1 号 2 点；按书的购买人数/次数/金额统计，乘分成 0.7、扣税 0.9、按 0.01 换成人民币；先写明细表 `author_income_detail` 再汇总 `author_income`；用 `queryIsStatisticsDaily` 防重跑。

**13）爬虫怎么做到"可配置"而不是写死？**
→ 规则用 JSON（`RuleBean`）存 `crawl_source.crawl_rule`，字段全是正则 + 起止标记；换站点只改配置不改代码；分类列表 URL 用 `{catId}`/`{page}` 占位；解析用预编译 `PatternFactory` 缓存正则。

**14）采集怎么控制并发和停止？**
→ 每个分类一个线程（1~7 共 7 个），线程 ID 存 Redis；停采集时根据 ID 找回线程 `interrupt()`，线程内每轮检查 `isInterrupted()` 退出；另有定时任务监控线程存活。**不足**：HTTP 阻塞时 interrupt 无效，要配超时；无代理池。

### D. 工程与排错

**15）为什么用 MyBatis Dynamic SQL 而不是 XML？**
→ 类型安全（编译期校验字段）、可组合（`where` 条件拼装不容易漏 `and`）、无需维护 XML；缺点是复杂 SQL（多表 join/子查询）写起来啰嗦、可读性不如 XML。

**16）PageHelper 原理？**
→ 基于 MyBatis 拦截器：`startPage` 把分页参数放 ThreadLocal → 执行 SQL 前拦截改写为 `limit`（并查 count）→ 用完清理；**注意线程池复用时要确保用完清理**，否则分页会串。

**17）定时任务多实例部署会重复执行吗？**
→ 会。现状没有分布式调度，靠"先查是否已统计"的幂等逻辑兜底；正规做法：XXL-Job/Elastic-Job 单分片执行 + 数据库唯一键幂等。

**18）怎么排查线上慢请求？**
→ ① 看日志（logback 按天）和 `@Log` 记录的方法耗时；② 阅读页并行加载，慢在哪个 `future.get()` 很明显；③ MySQL 慢查询日志 + `EXPLAIN`（`book` 表按 `book_name`/`author_name` 是否有索引要确认）；④ 缓存命中率（Redis/EhCache）；⑤ ES 查询慢看索引分片和 `ik` 词典。

**19）这个项目你做过什么优化？**（按真实情况挑）
→ 模板：① 首页/详情页从串行改 `CompletableFuture` 并行，RT 从 A 降到 B（**要有自己的实测数字才说**）；② 点击量走 MQ 聚合，DB 写次数降到 1/10；③ 首页榜单加缓存 TTL 分级；④ 章节正文分表避免单表膨胀；⑤ ES 提升搜索相关性。

**20）如果让你重构，你会改什么？**（高价值题）
→ ① 密码哈希升级 BCrypt；② 余额扣减改原子 SQL + 唯一索引；③ 支付回调条件更新；④ 点击量用 Redis INCR + 定时落库（或 Redisson 锁）；⑤ 补单元测试和 CI（现在没有）；⑥ 定时任务接分布式调度；⑦ 前台 JWT 加黑名单/短有效期 + refresh token；⑧ 后台权限粒度细化到数据行。

### E. 陷阱题

**21）这项目是你从零写的吗？**
→ **诚实**："是开源项目 novel-plus，我基于它做落地/二次开发"。然后讲你实际做的部分（部署、排错、改造、优化）。不要硬扛。

**22）你说是负责人，团队几个人？你具体负责哪块？**
→ 提前想好一个**真实且可验证**的答案。建议：小团队 2-3 人，你负责"整体架构落地 + 内容/交易链路 + 部署运维"，并准备 1-2 个你亲手改的代码点（比如新增一个接口、改过结算规则），能贴出代码最好。

**23）这套系统 QPS 能扛多少？**
→ 别编数字。可以说"没做过完整压测；从设计上瓶颈在 MySQL 写和 ES 查询，读多写少，理论上前台读可以靠缓存 + Nginx 静态化扛；要准确数字我会用 JMeter/wrk 压测首页和阅读页"。

**24）为什么不用 Redis 做 Session？为什么不用微服务/DDD？**
→ 后台 Shiro 的 Session 可通过 `redis-shiro` 配置存 Redis（代码里有 `common/redis/shiro` 包），现状默认 EhCache/本地；微服务对这个小团队是过度设计，模块化单体 + 清晰边界已经够用，等团队和流量真的上来再拆。

**25）JWT 怎么续期、怎么退出登录？**
→ 续期：前端每次页面加载调 `POST /user/refreshToken`，服务端 `canRefresh` 判断未过期后重签、过期时间顺延；退出：只删前端 cookie，服务端没有黑名单（所以 token 在有效期内仍可用）——改进方向是加 Redis 黑名单/短有效期 + refresh token 分离。

**26）图形验证码怎么实现的？**
→ `RandomValidateCodeUtil` 生成图片，code 存 `randomValidateCodeKey`（5 分钟）；注册时 `velocityCode` 比对。**问题是它是全局单 key，不区分会话**，多用户并发时 A 的验证码可能被 B 用掉——这是可以主动指出的设计缺陷，改进是按 sessionId/clientId 拼 key。

**27）后台的作品审核/上架是怎么实现的？**
→ **没有独立审核流程**：后台 7 个业务 Controller 都是代码生成器生成的 CRUD，`book` 表也没有 audit 字段，只有 `status`（0 入库 / 1 上架），靠通用 `/novel/book/update` 直接改。面试官如果期待"审核流"，就如实说明现状，并给出改进方案（加 `audit_status` 字段 + 审核记录表 + 状态机）。**这题答"有审核流"会立刻被追问穿帮。**

---

## 9. 三个可以直接讲的 STAR 故事（按你的真实情况选）

**故事 1：把项目完整落地（最安全）**
- S：拿到开源源码，要在一台云服务器上跑起来给运营用
- T：环境/数据库/缓存/采集全部打通，并能对外访问
- A：JDK8 + MySQL8 建库导入 `novel_plus.sql`；改 `application-common-dev.yml` 连 Redis；Nginx 反代 8083；配 ES 并建 `novel` 索引；调爬虫规则采集测试数据；处理了分表 `LONGVARCHAR` 报错、ES 版本兼容、图片路径映射
- R：站点上线，运营可在后台管理书籍/新闻/会员；采集每日自动更新

**故事 2：性能优化（要真实做一次再讲）**
- S：首页/阅读页首屏 1.5s+
- T：把 RT 压下来
- A：首页从串行改并行（`CompletableFuture`）；榜单加分级缓存；点击量从每次写库改为 MQ 聚合 10 次一写；阅读页正文走分表单查
- R：首页 RT 降到 xxx ms（自己压测出数字），DB 写压力下降 90%

**故事 3：二次开发（面试最加分，建议真做一个）**
- S：运营需要"作者收益导出/新增一个分类页/加一个支付渠道"
- T：在不破坏主流程的前提下加功能
- A：复用现有 `ResponseStatus`/`PageBean`/`RestResult` 规范；新增接口 + 权限点 + 菜单；写 SQL 增量脚本
- R：功能上线，且通过了原有回归

> ⚠️ 这三个故事里的数字和细节，**讲之前一定要自己跑一遍/改一遍**，面试官追问实现细节时能答上来才算数。

---

## 10. 本地把它跑起来（自己先跑通，面试才不虚）

1. 环境：**JDK 8**、Maven 3.6+、MySQL 8、Redis 5+（ES/RabbitMQ 可选）
2. 建库：`mysql -uroot -p -e "create database novel_plus default charset utf8mb4"`
3. 导入：直接执行 `doc/sql/novel_plus.sql`（表结构 + 历史 ALTER 都在里面）；如果按版本升级，再按日期顺序执行 `doc/sql/2021xxxx.sql` 增量脚本。**这个版本没有内置测试小说数据**，数据靠爬虫采集或自己造
4. 改配置：`novel-common/src/main/resources/application-common-dev.yml` 的数据源/Redis 密码；`novel-front/src/main/resources/application-dev.yml` 的图片/正文存储路径
5. 打包：`mvn clean package -DskipTests`
   - ⚠️ 项目不是 fat jar，`pom.xml` 用了 shade 的 **ZIP layout**：产物解压后是 `conf/`（配置）+ `lib/`（依赖）结构，启动要带 `-Dloader.path`，例如：
   ```bash
   java -Dloader.path=conf,lib -jar novel-front/target/novel-front-*.jar
   ```
   （直接 `java -jar` 可能因找不到依赖/配置启动失败，视打包产物而定）
6. 启动：
   - 前台 → http://localhost:**8083**
   - 后台 → http://localhost:**80**，默认账号 **`admin` / `admin`**（`sys_user` 初始化数据，密码算法已验证）
   - 爬虫 → http://localhost:**8081**（有自己的 Spring Security 登录，默认单管理员）
7. 常见坑（自己跑的时候一定会遇到）：
   - 后台 80 端口在 Windows 常被占用 → 改 `server.port`
   - **后台图书列表查询的 `BookMapper.xml` 还是旧库结构**（select 里带 `cat_child_id`、`hero_name` 等新库没有的列）→ 按 `novel_plus.sql` 建库后后台图书页可能报 `Unknown column`，需要顺手改 XML 或给库补列（这是真实存在的版本不一致）
   - 后台 "分类管理" 管的是**新闻分类**，小说分类没有入口
   - 首页/新闻缓存不会自动清，改完内容要调前台 `GET /cache/refresh/{密码}/{type}`（密码在 `cache.manager.password`，type 1 书籍 2 新闻 3 友链）
   - `content.save.storage` 只认 `db` / `txt`（Bean 名是 `txt`，注释里的 `file` 是坑）
8. 生产：`--spring.profiles.active=prod`，模板与静态资源走外部 `templates/{主题}/` 目录

---

## 11. 与上游 v6.0.0 的差异（被问到"最新版"时用）

你现在代码是 2022 年的 v3.6 时代，上游 2026-10 已到 **v6.0.0**。**完整内容见 Part B（第 12~19 节）**，这里只给结论：

- **Java 8 → Java 21**、**Spring Boot 2.1.8 → 3.4.0**、接入 **Spring AI 1.0.0**
- **做减法**：移除 Elasticsearch、FastDFS、RabbitMQ，搜索回退 MySQL
- 新增 **AI 长篇创作助手**（方案→章节→校验→确认的完整工作流）
- 移动端重做：书单广场、段落评论、消息系统、新 UI
- 跨端：v6 提供 **uni-app 客户端 API + CORS**
- 工程化：Docker、GitHub Actions 自动发布、外部配置、JWT_SECRET 强制

**如果面试官问"最新版有什么"**：承认你主要基于 v3.6 落地，同时能讲清 v6 的演进方向和关键设计（AI 任务模型、去组件化、跨端改造）——**这比假装熟悉最新版更可信**。

---

# Part B：版本演进与最新版 v6.0.0

> Part B 的所有内容来自 `git show upstream/master:<路径>`（上游 v6.0.0，提交 `e8daac0`，2026-10-21）。
> 面试策略：先讲你手上的 v3.6（Part A），被问到"后来迭代/最新版"再用 Part B——**能说清演进路线本身就说明你了解这个项目**。

## 12. 版本演进史（2022-01 → 2026-10）

**一句话：4.8 年、358 个提交、29 个版本，可以分成四个阶段。**

| 阶段 | 版本区间 | 这一阶段干了什么（面试按这个讲） |
|---|---|---|
| ① 收尾打磨 | v3.6.1 ~ v3.6.2（2022-07） | 优化打包、模版更新、**爬虫支持 HTTP 代理**（为采集可用性） |
| ② 补后台 + 移动端 | v4.0.0（2023-04）~ v4.4.0（2024-11） | 后台补齐：订单/评论/会员/小说推荐/会员反馈/友情链接/网站信息管理；手机端全面适配 + 支付宝手机网站支付；**多模板（绿色主题）**；语音播放；Dockerfile；**移除 Elasticsearch 和 FastDFS**；采集内容过滤 |
| ③ 技术栈换代 + AI | v5.0.0（2025-03）~ v5.3.3（2026-05） | **Java 21 + Spring Boot 3.4.0 + Spring AI 1.0.0** 三连升级；AI 写作 / AI 封面 / AI 创作助手；评论体系（点赞点踩、回复、地理位置）；流式响应；采集增强（进度、监控、**磁盘保护+邮件告警**）；GitHub Actions 自动发布；外部配置；Windows 一键启动 |
| ④ 跨端 + 移动端重构 | v6.0.0（2026-10-13~21） | **跨端客户端 API（uni-app）**；移动端 UI 重做 + 书单广场 + 段落评论 + 消息系统；AI 创作助手正式版；sitemap；作品完结；敏感词过滤；首页统计图表 |

**版本明细（挑重点背）**：

| 版本 | 日期 | 提交数 | 标志性变化 |
|---|---|---|---|
| v3.6.1 / v3.6.2 | 2022-07 | 11 / 12 | HTTP 代理、打包优化 |
| v4.0.0 | 2023-04 | 47 | 后台 7 大管理模块成型（订单/评论/会员…） |
| 4.1.0 | 2023-04 | 8 | 会员反馈、小说推荐管理 |
| 4.2.0 | 2023-10 | 26 | 支付宝手机网站支付、手机端全面适配、**移除 ES/FastDFS** |
| v4.3.0 | 2024-05 | 30 | 语音播放、绿色主题模板、Dockerfile |
| v4.4.0 | 2024-11 | 14 | UI 优化、采集内容过滤 |
| **v5.0.0** | 2025-03 | 19 | **Java 21 + Spring Boot 3.4 + Spring AI**、AI 写作、爬虫编码兼容 |
| v5.0.1 | 2025-03 | 21 | 移出书架、连接池统一创建、首登提速 |
| v5.1.0 | 2025-03 | 10 | AI 生成封面、外部配置文件、**GitHub Actions 自动发布** |
| v5.1.1 | 2025-04 | 7 | AI 流式响应、推荐缓存 |
| v5.2.x | 2025-07~10 | 30+ | 评论点赞点踩/回复/地理位置、采集进度与监控、Spring AI 1.0.0、缓存优化、Windows 启动脚本 |
| v5.3.x | 2025-10~2026-05 | 19 | 小说下载、采集磁盘保护 |
| v5.4.0 | 2026-10 | 13 | 评论敏感词、sitemap、作品完结、动态 User-Agent |
| v5.5.0 | 2026-10 | 27 | 移动端段落评论、书单广场、消息、统计图表 |
| **v6.0.0** | 2026-10 | 25 | 跨端 API、移动端 UI 重做、AI 创作助手、书单/段评/消息 |

**四个"代际"判断（面试可以当观点说）**：

1. **技术栈三连跳**：Boot 2.1.8（Java 8）→ 2.7.18（过渡）→ 3.4.0（Java 21），跨越了 javax→jakarta 的破坏性升级。
2. **做减法**：v4.2.0 移除 Elasticsearch、v4.x 移除 FastDFS，v5 之后前台 pom 里也看不到 RabbitMQ / EhCache——**从"堆组件"转向"降运维成本"**，搜索回退 MySQL、缓存靠 Redis/内存。
3. **AI 从玩具到工作流**：v5.0 只是编辑器里的扩写/润色，到 v6 已经是「创意问答→书名→方案→逐章→校验修订→确认保存→断点续写」的完整创作流水线。
4. **移动端从"适配"到"独立产品"**：v4 是响应式/手机模板适配，v6 是重做 UI + 书单广场 + 段落评论 + 消息系统，并配套跨端 API（uni-app 客户端）。

---

## 13. v6 技术栈与架构变化（v3.6 → v6.0.0）

### 13.1 依赖对照

| 项 | v3.6（你仓库） | v6.0.0（上游） | 影响 |
|---|---|---|---|
| JDK | 8 | **21** | 语言特性（record/switch 表达式/虚拟线程可用）、依赖全面 jakarta |
| Spring Boot | 2.1.8.RELEASE | **3.4.0** | `javax.*` → `jakarta.*`，Shiro/MyBatis 等都要换版本 |
| MyBatis | 2.1.4 + Dynamic SQL 1.1.4 | MyBatis 3.0.4 + **Dynamic SQL 1.5.0** | DSL 升级，写法基本兼容 |
| 分库分表 | Sharding-JDBC 3.x（yml 内嵌） | **ShardingSphere-JDBC 5.5.1（外置 YAML）** | 配置从 application.yml 迁到 `config/shardingsphere-jdbc.yml` |
| 鉴权 | JJWT 0.9.0（前台）+ Shiro/RBAC（后台） | JJWT 0.9.1；**后台重写为 Spring Security 内存单管理员**（`admin.username/admin.password` + BCrypt，csrf 关闭，默认 admin/admin；`sys_user/sys_role/sys_menu` 变遗留表，Shiro 在 v6 全仓库 0 命中） | 后台从"多用户 RBAC 管理台"退化为"单管理员运维台" |
| 搜索 | Elasticsearch 7.9（jest） | **已移除**（依赖 + `EsConfig`/`SearchService`/`BookToEsSchedule` 全删） | 搜索回退 MySQL |
| 消息 | RabbitMQ（可选） | **已删除** | 点击量削峰逻辑一并移除 |
| 文件 | 本地 / OSS / FastDFS | 本地 / OSS（**FastDFS 已移除**） | 少一套分布式文件系统 |
| 缓存 | EhCache（默认）/ Redis 可切换 | **只剩 Redis**（`EhCacheServiceImpl` 与 `cache.type` 开关删除，`CacheService` 仅 Redis 实现） | 实现收敛 |
| AI | 无 | **Spring AI 1.0.0**（`spring-ai-starter-model-openai`） | 接入硅基流动 OpenAI 兼容接口 |
| 新增 | — | `ip2region`（IP 归属地）、`houbb:sensitive-word 0.29.5`（内置词库）、`snakeyaml` | 评论地理位置、敏感词过滤 |
| 数据源 | application.yml 里配 url/账号 | **`jdbc:shardingsphere:absolutepath:${user.dir}/config/shardingsphere-jdbc.yml`**，业务 yml 不再有账号密码，连接池由分片文件创建 | 数据源与分片一起外置 |
| 打包 | shade ZIP layout + `-Dloader.path=conf,lib` | **fat jar** + 外置 `config/`、`templates/`（shade/dependency 插件删除，jar 名去版本号） | 发布更简单 |

### 13.2 分片配置外置（v6 的做法）

`config/shardingsphere-jdbc.yml`（ShardingSphere 5.5.1）：

```yaml
mode:
  type: Standalone          # 单机模式
  repository: { type: JDBC } # 元数据存库
dataSources:
  ds_1: { jdbcUrl: .../novel_plus }
  ds_2: { url: .../information_schema }   # 元数据持久化用
rules:
  - !SINGLE
    tables: ["*.*"]         # 默认单表
  - !SHARDING
    tables:
      book_content:
        actualDataNodes: ds_${1}.book_content${0..9}   # 只分表，不分库
        tableStrategy:
          standard: { shardingColumn: index_id, shardingAlgorithmName: bookContentSharding }
```

**和 v3.6 的区别**：v3.6 写在 `application-common-dev.yml` 里（`sharding.jdbc.*`）；v6 独立成文件，且**数据源整体外置**——业务 yml 里只剩：

```yaml
spring:
  datasource:
    url: jdbc:shardingsphere:absolutepath:${user.dir}/config/shardingsphere-jdbc.yml
```

即"数据源 + 分片"都由 ShardingSphere 从 YAML 接管（账号密码也移到这个文件），业务 yml 里不再有 username/password/druid。分片键仍是 `index_id % 10` 的逻辑（算法名 `bookContentSharding`，`!SINGLE "*.*"` 做非分片表兜底）。

### 13.3 部署与工程化（v6 新增）

- **Dockerfile**：各模块 `src/main/build/docker/Dockerfile`，基于 `eclipse-temurin:21-jre`
- **GitHub Actions**：`.github/workflows/release.yml` 打 tag 自动构建——产出 4 个 zip + 4 个镜像
- **启动脚本**：`novel-*.sh`（四合一，Linux 可任意路径执行）+ `novel-*.bat`（Windows 一键启动）
- **打包形态**：fat jar + 外置 `config/`（配置）+ `templates/`（模板/静态资源），启动不再需要 `-Dloader.path`
- **端口双轨（容易踩）**：源码里 front 8083 / admin 80 / crawl 8081；**部署包默认 front 8085 / admin 8088 / crawl 8083**
- **Boot 3 迁移坑**：`spring.resources.*` → `spring.web.resources.*`，漏改会导致静态资源 404
- **配置外置**：`spring.config.import` 引入链 + 根 `config/shardingsphere-jdbc.yml`（注意：模块 `build/config/` 下还有副本，已出现漂移，见 §16.6 风险）

### 13.4 安全变化

- **JWT 密钥强制外置**：`application.yml` 里 `jwt.secret: ${JWT_SECRET:}`；另有 `core/config/JwtSecretValidator`（`@Profile("prod")` + `ApplicationRunner`）**直接读 `System.getenv("JWT_SECRET")`**，为空直接抛 `IllegalStateException` 终止启动（注意读的是环境变量，不是配置项）
- **后台安全模型换了**：Shiro 8 个文件（ShiroConfig/UserRealm/RedisSessionDAO…）全删，改 Spring Security `InMemoryUserDetailsManager` + BCrypt + 默认 `admin/admin`
- XSS 过滤 URL 从 6 个扩展到 **17 个**（新增评论回复、段落评论、书单创建/修改、AI 助手各保存接口）
- 新增**敏感词过滤**：`houbb:sensitive-word 0.29.5` 内置词库（**不落表**），评论链路过滤
- 评论新增**地理位置**：`ip2region.xdb` + `IpLocationServiceImpl`，结果写 `book_comment.location`

### 13.5 v6 已知风险（面试可以主动提，显得你真读过代码）

| 风险 | 说明 |
|---|---|
| 配置副本漂移 | 根 `config/shardingsphere-jdbc.yml` 与三个模块 `src/main/build/config/` 下的副本不一致（根配置多 `ds_2`、用 `url:` 而非 `jdbcUrl:`、只有根配置带 `allowPublicKeyRetrieval=true`），修复 commit `0e156c04` 未同步 |
| Docker 镜像可能起不来 | Dockerfile 只覆盖 `spring.datasource.driver-class-name`，未改 `url`，容器内也没有 `config/`（未确认实际镜像行为） |
| 密钥明文入库 | AI api-key、支付宝私钥、OSS key-secret、Redis/MySQL 密码、`admin.password: admin` 都在仓库里明文 |
| CORS 配置冲突 | `allowedOriginPatterns("*")` + `allowCredentials(true)`，与 Cookie 鉴权组合存在被任意站点带凭据请求的风险（且浏览器对 `*`+credentials 有约束） |
| 默认口令 | 后台默认 `admin/admin`（生产必须改） |
| 主题不完整 | green 主题是默认，但缺桌面端 `booklist/` 模板（PC 书单页可能 404）；blue/dark 也不完整 |
| AI 编辑接口鉴权缺口 | 编辑器 AI 扩写/缩写/续写/润色的 8 个接口（含 4 个 SSE `/author/ai/stream/*`）**没有调用 `checkAuthor`**，是否被网关兜底未确认 |
| 点赞数据易失 | 赞/踩只存 Redis Set（`like:comment:*`），**Redis 清空/未持久化即归零**；列表回填是 N+1 查询 |

---

## 14. v6 数据模型增量（2023 → 2026 的 SQL 变化）

**新增表**（按引入版本）：

| 表 | 引入 | 用途 | 关键字段（核对过 DDL） |
|---|---|---|---|
| `website_info` | 20230413 | 网站信息（后台可配） | 站点名称、logo、备案号等 |
| `book_comment_reply` | 20250712 | 评论回复 | comment_id、reply_content、location、audit_status、create_user_id |
| `user_book_list` | 20261019 | **书单**（用户创建） | user_id、list_name、description、book_count、status |
| `user_book_list_item` | 20261019 | 书单条目 | list_id、book_id、remark |
| `book_paragraph_comment` | 20261019 | **段落评论** | book_id、book_index_id、paragraph_idx、root_id（楼中楼）、reply_user_name、reply_count、comment_content、location |
| `user_message` | 20261020 | **用户消息** | user_id、send_user_id、msg_type、book_id、book_index_id、target_id、content、read_flag |
| `ai_creation_plan` | 20261020 | **AI 创作方案** | author_id、book_id、stage、creative_params（JSON）、plan_content、outline_version |
| `ai_chapter_plan` | 20261020 | AI 章节规划 | plan_id、chapter_no、index_name、chapter_outline、status、index_id、word_count、summary |
| `ai_creation_task` | 20261020 | **AI 异步任务** | plan_id、author_id、task_type、chapter_no、status、running_flag（唯一索引）、result、error_msg |
| `ai_author_pref` | 20261020 | AI 作者偏好 | author_id、pref_content（JSON，≤4000 字） |

**新增字段**：

| 表.字段 | 版本 | 说明 |
|---|---|---|
| `book_comment.location` | 20250630 | 评论地理位置（IP 归属地） |
| `crawl_single_task.crawl_chapters` | 20250711 | 单本采集的章节数量进度 |
| `book.pic_url` | 20261020 | 默认值改为 `/images/default.gif` |

**v6 数据关系新增部分**：

```
user 1 ── n user_book_list 1 ── n user_book_list_item ── 1 book
book_index 1 ── n book_paragraph_comment
user 1 ── n user_message
author(user) 1 ── 1 ai_creation_plan 1 ── n ai_chapter_plan
                              │
                              └── n ai_creation_task（异步任务）
author 1 ── 1 ai_author_pref（创作偏好/文风约束）
```

**与 Part A 的关系**：v3.6 的表结构里没有书单/段评/消息/AI 这四类表，所以**别用 v6 的功能去讲 v3.6 的库**——面试被追问表结构时先确认对方问的是哪个版本。

**规模数字**：v6 全量脚本 **48 张逻辑表 + 10 张 book_content 分表**（唯一表名 58 个），相对 v3.6 新增 10 张（含 v5.2 的评论回复）。
**注意**：敏感词、sitemap、首页统计图表**都不落表**——敏感词用内置词库、sitemap 由定时任务写 `sitemap.xml` 文件、统计图表用 `AdminStatMapper.dailyCount` 的 `${table}` 动态表名按天聚合。

---

## 15. v6 新增业务与流程

### 15.1 AI 章节编辑（写作助手）

- **入口**：作家后台章节编辑器（`author/content_add.html` / `content_update.html`）工具栏，按钮 `data-type="stream/expand|condense|continue|polish"`
- **能力**：扩写、缩写、续写、润色（4 种模式）
- **实现**：Spring AI `ChatClient` 调硅基流动 OpenAI 兼容接口；**SSE 流式响应**（`text/event-stream`，前端用 `EventSource` 消费，边生成边渲染）
- **模型**：对话 `deepseek-ai/DeepSeek-R1-0528-Qwen3-8B`；生图 `Kwai-Kolors/Kolors`（`OpenAiImageModel` 自动装配，`BookServiceImpl` 注入用于 **AI 生成封面**）
- **接口形态**：共 8 个——4 个同步 POST + 4 个 SSE 流式 `/author/ai/stream/*`（扩写/缩写/续写/润色各一套），提示词在 Controller 里字符串拼接（没有独立 Service/模板）
- ⚠️ **鉴权缺口**：这 8 个接口**没有调用 `checkAuthor`**（不像作家后台其他写接口），是否被网关兜底未确认——面试可以当安全问题主动提
- **AI 封面流程**：发书时异步调 `OpenAiImageModel` → 下载图片到 `/localPic/aiGen/yyyy/MM/dd/{bookId}.png` → 更新 `book.pic_url` → Redis `aiGenPic` 缓存 1 小时 → 前端轮询 `/author/queryAiGenPic`

### 15.2 AI 长篇创作助手（v6 的重头戏）★

**入口**：作家后台「AI创作助手」（`templates/author/ai_assistant.html`），Controller：`AiAssistantController`（`/author/aiAssistant/**`）

**工作流（5 个阶段，对应 `stage` 字段）**：

```
① 创作问答 STAGE_QA(1)
   POST /initPlan  → 创建 ai_creation_plan（可带 planId 恢复）
   POST /saveParams → 保存题材/创意/主角/冲突/世界观/文风/目标读者/章节数/每章字数（JSON）
② 书名建议 → POST /startTask(taskType=1)  → 异步任务 → GET /task/{id} 取结果
③ 创作方案 STAGE_PLAN_DRAFT(2)
   POST /startTask(taskType=2) 生成结构化方案（简介/世界观/人物/总纲/分卷/伏笔/章节规划）
   POST /savePlanContent 编辑保存 → POST /confirmPlan 确认（校验 JSON、重排章节序号）
        └─ 首次确认：调用 bookService.addBook 建书（含同名校验、AI 封面）→ 生成 ai_chapter_plan 章节骨架
        └─ stage=STAGE_PLAN_CONFIRMED(3)，outline_version +1
④ 逐章创作
   POST /startTask(taskType=3, chapterNo=N) → 生成单章正文（自动带总纲+本章规划+人物+世界观+前文摘要+未回收伏笔）
   POST /saveDraft 存草稿 → POST /saveChapter 确认保存（作者确认制，不覆盖已发布章节）
   POST /startTask(taskType=4) 自动校验修订（程序检查 + AI 一致性检查，最多 3 轮）
   （章节保存后系统内部触发 taskType=5 生成章节摘要，供后续章节引用）
⑤ 断点续写
   GET /progress 返回方案进度 + 章节状态（TODO/DRAFT/SAVED），刷新/中断后可继续
   前端每 2.5s 轮询 GET /task/{taskId}，任务完成即取结果
```

**关键设计（面试重点）**：

| 设计 | 实现 | 面试怎么讲 |
|---|---|---|
| 异步任务 | `ai_creation_task` 表 + 线程池 `aiTaskExecutor` + 前端轮询 `GET /task/{id}` | 生成一章要几十秒，不能阻塞 HTTP；用任务表 + 轮询解耦 |
| 防重复提交 | **`running_flag` 唯一索引**，同方案同类型同章节只能有一个进行中 | 并发点击/重试时由 DB 唯一索引兜底，捕获 `DuplicateKeyException` 转业务错误 |
| 超时与崩溃恢复 | 任务超时 10 分钟；`ApplicationReadyEvent` 启动时把遗留 running 置失败（12 分钟陈旧判定） | 单实例部署的取舍，多实例需按启动时间窗口判定（代码注释写了） |
| 只重建未保存章节 | `confirmPlan` 里 `deleteUnsaved` + `batchInsert`，已保存章节不动 | 方案调整不冲掉作者已写内容，这是**内容产品的底线** |
| 作者确认制 | AI 只写草稿，`saveChapter` 才落 `book_index`/`book_content` | 防止 AI 直接覆盖线上内容 |
| 规模限制 | 首次方案最多 40 章、批量规划每批 30 章、修订最多 3 轮、偏好 ≤4000 字 | 控制 token 成本和上下文长度 |
| 输出容错 | `AiJsonUtil.parseJsonFromModel` 从模型输出里抽 JSON | LLM 会带 markdown 代码块/废话，必须容错解析 |
| 程序检查 | `ChapterTextCheckUtil.check(content, targetWords)`：字数、重复段落等 | 先用程序规则过滤，再交 AI 做一致性检查，省 token |

**涉及表**：`ai_creation_plan` / `ai_chapter_plan` / `ai_creation_task` / `ai_author_pref` + `book` / `book_index` / `book_content`

**Prompt 模板**（`novel-front/src/main/resources/prompts/ai-assistant/`）：

`book_name.txt`、`creative_plan.txt`、`chapter_plan_batch.txt`、`chapter_content.txt`、`chapter_check.txt`、`chapter_revise.txt`、`chapter_summary.txt` —— 由 `PromptTemplateUtil` 加载渲染，**把 prompt 放在资源文件而不是硬编码**，方便调优。

### 15.3 书单广场

- 入口：移动端「书单广场」（`templates/mobile/booklist/plaza.html`）+ 书单详情/我的书单
- 接口：`UserBookListController`（`/bookList/**`：create / update / addBook / detail…）
- 表：`user_book_list`（user_id、list_name、description、book_count、status）+ `user_book_list_item`（list_id、book_id、remark）
- 数据流：用户建单 → 加书 → 广场列表（按热度/时间）→ 详情页展示书单内书籍

### 15.4 段落评论

- 入口：移动端阅读页选中段落后评论（`templates/mobile/user/paragraph_comment.html`）
- 表：`book_paragraph_comment`（`book_index_id` + `paragraph_idx` 定位到段，`root_id` 支持楼中楼回复，`location` 地理位置、`reply_count` 回复数）
- Service：`BookParagraphCommentServiceImpl`
- 数据流：阅读页 → 选段落 → 提交评论 → 按章节/段落拉取评论列表 → 审核后展示

### 15.5 消息系统

- 入口：移动端「消息」（`templates/mobile/user/message.html`）
- 接口：`MessageController`，Service：`UserMessageServiceImpl`
- 表：`user_message`（user_id、send_user_id、msg_type、target_id、book_id/book_index_id、content、read_flag）
- `msg_type`：**1 书评 / 2 段评 / 3 系统通知**；`target_id` 定位来源对象
- 接口：`/user/message` 4 个（列表/未读/已读等），移动端首页和个人中心有未读角标；管理端 `/message/userMessage.html` 可发系统通知

### 15.6 评论增强（v5.2 起）

| 能力 | 实现 | 表/类 |
|---|---|---|
| 点赞/点踩 | `LikeServiceImpl`：**Redis Set + Lua 脚本原子切换**（key 前缀 `like:comment:` 等，赞/踩互斥），**不落表**；列表查询逐条回填，**N+1 且 Redis 丢数据就归零** | `LikeServiceImpl` |
| 评论回复 | `book_comment_reply` 表 + `BookCommentReplyMapper.xml` + 模板 `book_comment_reply.html` | 20250712 |
| 地理位置 | `IpLocationServiceImpl` + `ip2region.xdb`（IP→省市） | `book_comment.location` |
| 敏感词 | `sensitive-word` 依赖，评论发布时过滤 | 配置词库路径待确认 |
| 审核 | 评论/回复都有 `audit_status` | 后台审核 |

### 15.7 移动端重做（v5.5 + v6）

- 新 UI：`templates/mobile/**` 整套重写（首页、排行榜、筛选、个人中心、作品评论区）
- 新功能：书单广场、段落评论、消息系统、移动端检索优化
- 技术：仍是 Thymeleaf + 移动端 layui + jQuery（`static/mobile/**`），**不是前后端分离**

### 15.8 其他更新

| 功能 | 版本 | 说明 |
|---|---|---|
| sitemap.xml | v5.4.0 | `SitemapGenSchedule`（**仅 prod**，`0 0 2 * * ?`）生成 `sitemap.xml`，**不落表**；站点根 URL 依赖首页访问写入的 `WEB_SITE_ROOT_URL` |
| 后台统计趋势 | v6.0.0 | 后台首页 ECharts 增长趋势（`/stat/trend`），`AdminStatMapper.dailyCount` 用 `${table}` 动态表名按天聚合，**不落表** |
| 采集磁盘保护 | v5.3.0 | `DiskMonitorSchedule`：**默认关闭**，85/90/95 分级邮件，**≥95% 发信后 sleep 10s 直接 `System.exit(1)`**（熔断），`AtomicBoolean` 防重复 |
| 敏感词 | v5.4.0 | `houbb:sensitive-word` 内置词库，**不落表** |
| 作品完结 | v5.4.0 | 作家专区把书标记完结（具体字段未确认） |
| 语音播放 | v4.3.0 | 移动端**纯前端 Web Speech API** 朗读（无后端 TTS） |
| 小说下载 | v5.3.0 | 接口在 **novel-admin 模块**；移动端按钮相对路径与 novel-front 不一致（部署映射未确认） |
| 动态 User-Agent | v5.4.0 | 采集 **8 条随机 UA 池**，反反爬增强 |
| ~~会员注册随机昵称~~ | v6.0.0 提交但 **已回滚** | `23ec63ef` 加入、`b0c3f4d1` 回滚，v6.0.0 **不含**；当前注册仍是 `nickName = username`（别讲错） |

### 15.9 跨端客户端 API（v6.0.0 最新提交）

**背景**：配合 **uni-app 跨端客户端**（H5/App）直连 REST 接口。

> 注意：**没有新增 api 模块，也没有 BFF 层**——接口直接加在既有的 `BookController` / `NewsController` 上，复用同一套 Service。`.gitignore` 里新增 `/templates/app/`，说明跨端前端模板/产物不进主仓。

| 变化 | 内容 |
|---|---|
| 新增接口 | `GET /book/queryBookIndexContent/{indexId}`：**读者端章节正文**，含 VIP 判断（未登录/未购买 → `needBuy=true`，只返回元信息不返回正文）|
| 新增接口 | `GET /news/detail/{newsId}`：新闻详情（含正文） |
| 跨域 | `WebMvcConfig.addCorsMappings`：`/**` 允许任意来源 + 常用方法 + credentials（供 uni-app H5 调试/独立部署） |
| 错误码 | 新增 `INDEX_NOT_EXISTS(5002)`、`NEWS_NOT_EXISTS(5003)` |
| 复用 | 章节正文仍走 `bookContentServiceMap`（db/txt 双存储），与 PC 页面同一套业务逻辑 |

**面试点**：跨端接口复用了页面端的 VIP 校验逻辑，但**把「是否返回正文」放在服务端判断**（`needBuy=true` 时不返回 content），避免客户端拿到付费内容——这是接口安全的基本要求。

**注意**：这次 CORS 用的是 `allowedOriginPatterns("*")` + `allowCredentials(true)`，配合 Cookie 鉴权存在安全边界问题（任意站点都可能带凭据请求）。面试被问"跨域怎么配的"可以主动指出：生产应改成白名单 + 只用 Header token。

---

## 16. v6 技术实现细节（被追问时用）

### 16.1 AI 任务模型（v6 最值得讲的技术设计）

- **表**：`ai_creation_task`（plan_id、task_type、chapter_no、status、result、error_msg、running_flag）
- **任务类型**：1 书名、2 创作方案、3 章节正文、4 校验修订、5 章节摘要（系统内部）、6 批量章节规划
- **状态**：`TASK_RUNNING(0)` / `TASK_SUCCESS(1)` / `TASK_FAILED(2)`
- **执行**：`startTask` 先 `precheckTask`（按类型校验前置条件）→ 插任务行（`running_flag` 唯一索引防并发）→ 丢线程池 `aiTaskExecutor`（**核心 1 / 最大 2 / 队列 30**，与页面并行用的 `threadPoolExecutor` 隔离，避免长任务挤占页面线程）→ 失败/拒绝分别处理
- **AI 客户端**：`AiConfig` 造 `ChatClient`，连接/读取超时分别 5s/60s；模型配置在 `spring.ai.openai.*`
- **超时**：AI 调用 10 分钟超时；启动时把超过 12 分钟的 running 任务判失败
- **恢复**：`@EventListener(ApplicationReadyEvent)` 把重启后遗留的 running 全部置失败，释放 `running_flag`
- **失败可重试**：任务失败只写 `error_msg`，不污染方案/章节数据；用户可重新发起

### 16.2 Prompt 与输出解析

- Prompt 模板放 `resources/prompts/ai-assistant/*.txt`，`PromptTemplateUtil` 渲染变量
- 模型返回的 JSON 用 `AiJsonUtil.parseJsonFromModel` 抽取（容忍 markdown 代码块、前后废话）
- 章节内容检查：`ChapterTextCheckUtil`（**字数在目标 70%~150%、重复段落占比 >12% 判不合格**）+ AI 责编检查（`chapter_check.txt`）；prompt 里写的是 ±30%，与代码口径不一致（代码更严）
- 修订：最多 3 轮（`MAX_REVISE_ROUNDS=3`），避免无限循环烧 token

### 16.3 一致性与幂等（对比 Part A 的缺陷）

| 场景 | v3.6 | v6 |
|---|---|---|
| 支付回调 | 只验签、无金额校验 | 未确认是否修复（需看 v6 PayController） |
| 余额扣减 | 先查后改 | 未确认 |
| AI 任务并发 | — | `running_flag` 唯一索引兜底 ✅ |
| 方案与已写章节 | — | 只重建未保存章节 ✅ |
| 重启后任务 | — | 启动失败回收 ✅ |

> ⚠️ 被问"新版解决了老版的哪些问题"时，只讲你**确认过**的（AI 任务幂等、章节不覆盖、JWT_SECRET 强制、去组件化），余额/支付等没确认的说"这个我没细看新版实现"。

### 16.4 分片、连接池、定时任务与部署

- 分片：外置 YAML + Standalone + JDBC 元数据库；分片键仍 `index_id`，10 张表（只分表不分库）
- 连接池：v5.0.1 起**统一创建连接池并提前初始化**（Boot 3 默认首次请求才建池，会拖慢首登）
- **定时任务换血（5→5）**：删 `BookToEsSchedule`（ES 没了）和 `CrawlThreadMonitor`（改成按需 `GET /crawl/getTaskProgress/{id}` 查询）；新增 `SitemapGenSchedule`（prod，`0 0 2 * * ?`）和 `DiskMonitorSchedule`（磁盘分级阈值 + 邮件告警 + 熔断，`AtomicBoolean` 防重复告警）
- **异步两条独立线程池**：`threadPoolExecutor`（页面 CompletableFuture 并行装配）与 `aiTaskExecutor`（AI 创作任务隔离，避免长任务挤占页面线程）
- ⚠️ 定时任务**没有分布式锁**，多实例部署会重复执行（和 v3.6 一样的遗留问题）
- 部署：Dockerfile（temurin 21-jre）+ GitHub Actions（4 zip + 4 镜像）+ `novel-*.sh/bat` + 外置 `config/`、`templates/`

### 16.5 v6 前台模块结构（与 Part A 的对应关系）

| v3.6 | v6 | 说明 |
|---|---|---|
| `controller/PageController` | `controller/page/PageController` | 包位置调整 |
| `service/impl/SearchServiceImpl` | 无 | ES 已移除 |
| `service/impl/BookServiceImpl` | 保留 + 新增段落评论/书单/AI 相关 service | — |
| 无 | `controller/AiAssistantController` + `core/ai/*` | AI 创作 |
| 无 | `controller/UserBookListController`、`MessageController` | 书单、消息 |
| 无 | `service/impl/IpLocationServiceImpl`、`LikeServiceImpl` | 地理位置、点赞 |

---

## 17. 面试话术：怎么讲版本演进

### 17.1 十个要点（选 5 个讲就够）

1. 项目从 2022 年 v3.6 演进到 2026 年 v6.0.0，共 358 个提交、29 个版本
2. 技术栈三连跳：Java 8→21、Spring Boot 2.1.8→3.4.0（跨过 javax→jakarta）
3. 做减法降运维：移除 ES、FastDFS、RabbitMQ、EhCache，搜索回退 MySQL、缓存只留 Redis
4. 后台先补齐 7 大管理模块（订单/评论/会员/推荐/反馈/友链/网站信息），v6 又重写成 Spring Security 单管理员运维台（净删 29 万行）
5. 移动端从适配到重做（书单广场、段落评论、消息、新 UI）
6. AI 从编辑器扩写进化到长篇创作工作流（方案→章节→校验→确认）
7. 工程化：Docker、GitHub Actions 自动发布、外部配置、一键启动脚本
8. 安全：JWT_SECRET 强制外置、XSS 范围扩展、评论敏感词
9. 数据：新增 10 张表（书单 2、段评 1、消息 1、AI 4、网站信息 1、评论回复 1）
10. 跨端：v6 提供 uni-app 客户端 API + CORS

### 17.2 三个高频问题的回答模板

**Q：你用的是哪个版本？**
→ "我仓库是从 v3.6 分叉的，主要基于 v3.6 落地；后来我追了上游到 v6.0.0，所以两版的结构和差异我都能讲。"（然后按 Part A 或 Part B 展开）

**Q：最新版有什么新东西？**
→ 讲 §15 的三件套：AI 长篇创作助手、移动端重做（书单/段评/消息）、跨端 API；技术上说 Java 21 + Boot 3.4 + Spring AI。

**Q：为什么从 v3.6 升到 v6？**
→ ① 安全（JWT_SECRET 强制、依赖漏洞）；② 运维成本（去掉 ES/FastDFS/RabbitMQ）；③ 功能需求（AI 创作、移动端）；④ 生态（Java 21/Boot 3.4 才能用 Spring AI 1.0）。

### 17.3 陷阱

- ❌ 别把 v6 的 AI 功能说成"我开发的"——除非你真改过；一追问 prompt 设计和任务表就露馅
- ❌ 别说"新版用 ES 做搜索"——ES 在 v4.2.0 就被移除了
- ✅ 最好的姿势："我读过两版代码，v3.6 我落地过，v6 我研究过它的 AI 任务模型和跨端改造"

---

## 18. 两版速查对照表（一页带走）

| 维度 | v3.6（你的仓库） | v6.0.0（上游最新） |
|---|---|---|
| 版本/日期 | 3.6.1 / 2022-01 | 6.0.0 / 2026-10 |
| JDK / Boot | Java 8 / 2.1.8 | Java 21 / 3.4.0 |
| 持久层 | MyBatis + Dynamic SQL 1.1.4 | MyBatis 3.0.4 + Dynamic SQL 1.5.0 |
| 分片 | Sharding-JDBC 3.x（yml 内嵌） | ShardingSphere 5.5.1（外置 YAML） |
| 搜索 | ES 7.9（可开关） | 无 ES（MySQL） |
| 消息 | RabbitMQ（可开关） | 前台无 amqp |
| 文件 | 本地/OSS/FastDFS | 本地/OSS |
| AI | 无 | Spring AI 1.0.0 + 硅基流动 |
| 移动端 | 模板适配（mobile/） | 重做 + 书单/段评/消息 |
| 跨端 | 无 | uni-app API + CORS |
| 表数量 | 39 + 10 分表 | 48 + 10 分表（新增 10 张） |
| 后台 | Shiro + RBAC + 生成器 CRUD | **Spring Security 内存单管理员**（admin/admin，BCrypt） |
| 缓存 | EhCache / Redis 可切换 | **仅 Redis** |
| 部署 | shade ZIP + conf/lib | fat jar + 外置 config/templates + Docker + CI |
| 安全 | JWT 硬编码密钥 | JWT_SECRET 强制（prod 校验） |
| 定时任务 | ES 同步/图片/日结/月结/线程监控 | 日结/月结 + sitemap + 磁盘监控（去掉 ES/线程监控） |
| 端口 | 8083 / 80 / 8081 | 源码相同；**部署包 8085 / 8088 / 8083** |

---

## 附：必须背下来的 12 个数字

| # | 数字 | 含义 |
|---|---|---|
| 1 | 4 模块 | common / front / admin / crawl |
| 2 | 340 个 Java 文件 | v3.6 代码量 |
| 3 | 39 + 10 张表 | 逻辑表 + 章节分表（v6 是 48 + 10） |
| 4 | 10 张分表 | `book_content0~9`，`index_id % 10` |
| 5 | 5 个定时任务 | ES/图片/日结/月结/采集监控（v6 删了 ES 任务） |
| 6 | 7 线程 | 爬虫按分类并行 |
| 7 | 10 次 | 点击量聚合写入阈值 |
| 8 | 7 天 | JWT 有效期（604800s） |
| 9 | 0.7 / 0.9 / 0.01 | 作者分成 / 扣税系数 / 币兑人民币 |
| 10 | 8083 / 80 / 8081 | front / admin / crawl 端口 |
| 11 | **358 提交 / 29 版本 / 4.8 年** | v3.6 → v6.0.0 的演进量 |
| 12 | **AI：6 类任务 / 10 分钟超时 / 3 轮修订 / 40 章上限** | v6 AI 创作的关键参数 |

