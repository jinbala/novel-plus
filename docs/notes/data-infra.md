# novel-plus v3.6 数据模型 / 基础设施 / 部署 调研笔记

> 代码基线：当前仓库 `906e7762`（pom 版本 `3.6.1`，Java 8 + Spring Boot 2.1.8）。只写代码/脚本能确认的事实；标「未确认」的是仓库内找不到闭环证据的点。取证位置：`doc/sql/novel_plus.sql`、`doc/es/index_create.txt`、`novel-common/src/main/java`、各模块 `src/main/resources/application*.yml`、各模块 `pom.xml`、`README.md`。

## 0. 速览（面试口径）

- 三个可部署进程 + 一个普通 jar：`novel-front`（门户 + 作家后台，8083）、`novel-admin`（平台后台，80）、`novel-crawl`（爬虫管理，8081）；`novel-common` 只是被依赖的普通 jar，**没有** `META-INF/spring.factories`，不是 Spring Boot Starter。
- 39 张逻辑表 + `book_content` 的 10 张分表；**全库没有物理外键**，关系全部靠应用层维护。
- 章节正文双存储：数据库分表 或 TXT 文件，由 `book_index.storage_type` 逐章决定，运行时用 `Map<String, BookContentService>` 做策略选择。
- 缓存默认 Ehcache（`cache.type: ehcache`），Redis 是替换方案；ES、RabbitMQ 默认关闭，靠 `enable: 0/1` 开关。
- 打包**不是** fat jar：Spring Boot `ZIP` layout + `-Dloader.path=conf,lib`，配置在 `conf/`、三方依赖在 `lib/`。

## 1. 数据库模型

### 1.1 全表清单（`doc/sql/novel_plus.sql`）

| 表名 | 中文含义 | 所属子系统 |
| --- | --- | --- |
| `book` | 小说主表（含分类/作者冗余、点击量、最新章节、爬虫字段） | 书库 |
| `book_index` | 章节目录（章节号、字数、收费、单价、存储方式） | 书库 |
| `book_content` | 章节正文逻辑表（实际落到 `book_content0..9`） | 书库 |
| `book_category` | 小说分类（7 条种子数据，男频 6 + 女频 1） | 书库 |
| `author` | 作家账户（绑 `user_id`，邀请码入驻） | 书库/会员 |
| `author_code` | 作家邀请码（唯一、有效期、是否已用） | 书库/会员 |
| `book_author` | 作者名录（按笔名去重，爬虫占位作者） | 书库 |
| `book_setting` | 首页推荐位（type 0 轮播/1 顶部/2 本周强推/3 热门/4 精品） | 书库/运营 |
| `book_screen_bullet` | 弹幕表（漫画模块历史遗留，代码未引用） | 书库 |
| `book_comment` | 书评（`book_id` + `create_user_id` 唯一） | 会员 |
| `book_comment_reply` | 书评回复 | 会员 |
| `user` | 前台会员（用户名唯一、屋币余额） | 会员 |
| `user_bookshelf` | 书架（`user_id`+`book_id` 唯一） | 会员 |
| `user_read_history` | 阅读历史（`user_id`+`book_id` 唯一） | 会员 |
| `user_buy_record` | 章节订阅记录（`user_id`+`book_index_id` 唯一） | 订单 |
| `user_feedback` | 用户反馈 | 会员 |
| `order_pay` | 充值订单（支付宝/微信） | 订单 |
| `author_income` | 作家月稿费（税前/税后，单位分） | 统计 |
| `author_income_detail` | 作家日订阅明细（`book_id=0` 表示全部作品） | 统计 |
| `news` / `news_category` | 新闻 / 新闻分类 | 运营 |
| `friend_link` | 友情链接（无表注释） | 运营 |
| `crawl_source` | 爬虫源 + `crawl_rule` JSON 规则 | 爬虫 |
| `crawl_batch_task` | 批量抓取任务 | 爬虫 |
| `crawl_single_task` | 单本抓取任务（SQL 里定义了新旧两版，后者覆盖前者） | 爬虫 |
| `sys_user` | 后台用户（无表注释，密码为 MD5+salt 摘要） | 系统权限 |
| `sys_role` | 角色 | 系统权限 |
| `sys_menu` | 菜单/按钮（type 0 目录/1 菜单/2 按钮，`perms` 授权串） | 系统权限 |
| `sys_user_role` | 用户-角色 | 系统权限 |
| `sys_role_menu` | 角色-菜单 | 系统权限 |
| `sys_dept` | 部门树（一级 `parent_id=0`） | 系统权限 |
| `sys_data_perm` | 数据权限定义（`all_`/`sup_`/`own_` 前缀 + 控制列） | 系统权限 |
| `sys_role_data_perm` | 角色-数据权限 | 系统权限 |
| `sys_dict` | 字典（utf8_bin 排序规则，与其它表 utf8mb4 不一致） | 系统权限 |
| `sys_log` | 操作日志（AOP 异步写） | 系统权限/统计 |
| `sys_file` | 上传文件记录（url 形如 `/files/...`） | 系统权限 |
| `sys_gen_table` / `sys_gen_table_column` / `sys_gen_columns` | 代码生成元数据 | 系统权限 |

物理表共 49 张：38 张普通表 + `book_content` 基表 + `book_content0..9`（基表也建了，但 ShardingSphere 只路由到 0..9）。

### 1.2 核心表关键字段 / 主键 / 索引

- `book`：PK `id`；**UQ `(book_name, author_name)`**（爬虫入库前也按这两列判重）；普通索引 `last_index_update_time`（ES/榜单增量）、`create_time`（新书榜）。状态字段易混：`status` 0 入库/1 上架，`book_status` 0 连载/1 完结，`is_vip` 整本书是否收费；`author_id` 可空，`author_name`、`cat_name` 是冗余列（避免列表页 join）。爬虫字段 `crawl_source_id/crawl_book_id/crawl_last_time/crawl_is_stop` 直接挂在 `book` 上。
- `book_index`：PK `id`；UQ `(book_id, index_num)`；索引 `book_id`、`index_num`。除 `index_name/word_count/is_vip` 外，后期追加 `book_price`（屋币/章）和 `storage_type`（`db`/`txt`，默认 `db`）——**章节粒度的存储路由就靠这一列**。
- `book_content`：PK `id`（分表后由 ShardingSphere 生成），UQ `index_id`，正文 `mediumtext`。单表只有 3 列，分表后 UQ 只在单分片内成立，但因为按 `index_id` 分片，全局仍唯一。
- `user`：PK `id`（雪花，19 位），**UQ `username`**（手机号当用户名），`password` 单次 MD5（无盐，32 位），`account_balance` 单位「屋币」（1 元 = 100 屋币，见 `OrderServiceImpl` 回调 `totalAmount*100`）。
- `user_bookshelf` / `user_read_history`：PK `id`；UQ `(user_id, book_id)`；`pre_content_id` 注释写「章节内容表 ID」，但模板里直接拼 `/book/{bookId}/{preContentId}.html`，实际存的是 **`book_index.id`**（命名有坑）。
- `book_comment`：PK `id`；UQ `(book_id, create_user_id)`，即一人一书只能评一次；`reply_count` 冗余计数。
- `user_buy_record`：PK `id`；UQ `(user_id, book_index_id)` 保证同一章不重复扣费；`buy_amount` 记屋币数。
- `order_pay`：PK `id`；`out_trade_no` 商户单号（**无唯一约束、无 user_id 索引**），`pay_channel` 1 支付宝/2 微信，`pay_status` 0 失败/1 成功/2 待支付，`total_amount` 单位元（int）。
- `author_code`：PK `id`；UQ `invite_code`；`validity_time` + `is_use` 控制一次性入驻。
- 权限四张关联表（`sys_user_role`/`sys_role_menu`/`sys_role_data_perm`）都只有自增 PK，**没有联合唯一约束**，重复绑定只能靠业务代码避免。

### 1.3 逻辑关系（无物理外键，ASCII ER）

```
【书库/内容】
 book_category 1 ──N book 1 ──N book_index 1 ──1 book_content(index_id)
      (cat_id)          │            (book_id)         └ 物理表 book_content0..9
                        │  author_id(可空)                  │
 author 1 ──N book ─────┘                                   │
 (id=book.author_id)                                        │
 book_author 1 ──N book(author_id)  ← 仅爬虫/占位作者，当前代码未写入
 book 1 ──N book_setting(book_id,type,sort)                 │
 book 1 ──N book_comment ──1 user(create_user_id)           │
 book_comment 1 ──N book_comment_reply(comment_id)          │
 book 1 ──N book_screen_bullet(content_id→book_content.id)  │
                                                            │
【会员/互动】                                                │
 user 1 ──N user_bookshelf(book_id) ────────────────────────┤ pre_content_id→book_index.id
 user 1 ──N user_read_history(book_id) ─────────────────────┘
 user 1 ──N user_feedback
 user 1 ──N book_comment / book_comment_reply

【订单/充值/订阅】
 user.account_balance(屋币) ← order_pay(pay_status=1, +total_amount*100)
 user 1 ──N order_pay(user_id, out_trade_no)
 user 1 ──N user_buy_record(user_id, book_index_id) ──N book_index
 book_index.book_price × user_buy_record.buy_amount ──→ author_income_detail(daily)
      └─ 月汇总 → author_income(book_id=0 为作家合计，pre/after_tax_income 单位分)

【后台权限】
 sys_dept 1 ──N sys_user(dept_id)
 sys_user N ──N sys_role        via sys_user_role
 sys_role N ──N sys_menu        via sys_role_menu (perms: novel:book:add ...)
 sys_role N ──N sys_data_perm   via sys_role_data_perm
      └─ DataPermInterceptor 把 perm 拼成 WHERE 条件（all_/sup_/own_）
```

要点：`book.author_id` 指向 `author.id`（作家账户），但爬虫入库只写 `author_name`、不写 `author_id`（`CrawlParser` 未 set），因此爬来的书 `author_id` 为 NULL；`book_author` + `BookService.getOrCreateAuthorIdByName()` 存在但**全仓库无调用方**，属于半废弃设计。

### 1.4 分表：按 `index_id % 10`，不是按 `book_id`

- 表名规则 `book_content${index_id % 10}`，即 `book_content0` … `book_content9`。
- 配置位置：`novel-common/src/main/resources/application-common-dev.yml` 与 `application-common-prod.yml` 的 `sharding.jdbc.config.sharding.tables.book_content`：
  `actual-data-nodes: ds${0}.book_content${0..9}`、`table-strategy.inline.shardingColumn: index_id`、`algorithm-expression: book_content${index_id % 10}`、`key-generator-column-name: id`。
- 库策略被注释掉（`ds1`、`database-strategy` 都在注释里），所以是**只分表不分库**；数据源 `ds0` 走 HikariCP。
- 建表位置：`doc/sql/novel_plus.sql` 第 1628–1743 行显式 `CREATE TABLE book_content0..9`。
- 中间件版本 `io.shardingsphere:sharding-jdbc-spring-boot-starter:3.0.0`（`pom.xml`），配置前缀仍是旧的 `sharding.jdbc.*`。写入统一走逻辑表 `book_content`，由中间件改写路由。
- 正文读取路由在 `novel-front` / `novel-crawl` 的 `DbBookContentServiceImpl(@Service("db"))` 与 `FileBookContentServiceImpl(@Service("txt"))`，调用方用 `bookContentServiceMap.get(bookIndex.getStorageType())`；TXT 模式文件路径 `{content.save.path}/{bookId}/{indexId}.txt`。
- `content.save.storage` 决定**爬虫写入**时给新章节打的 `storage_type`（`novel-crawl/.../BookServiceImpl` 里直接读该配置），历史章节可混存。

### 1.5 统计 / 日志类表

- `author_income_detail`：按「日 + 作品」统计订阅人数/次数/总额，`book_id=0` 为作家全部作品合计；`DailyIncomeStaSchedule`（每天 0 点，cron `0 0 0 * * ?`）回填昨天。
- `author_income`：按「月 + 作品」汇总，`MonthIncomeStaSchedule`（每月 1 号 2 点）按 `author.income.share-proportion=0.7`、`tax-rate=0.9`、`exchange-proportion=0.01` 换算成「分」，落 `pre_tax_income/after_tax_income`，带 `pay_status/confirm_status`（0 待支付/待确认）。
- `sys_log`：`@Log` 注解 + `LogAspect` 环绕，`LogServiceImpl.save()` 标了 `@Async`，字段含操作、方法、参数（截断 4999）、IP、耗时。
- `sys_file`：后台文件上传记录（`url` 为 `/files/xxx`），`WebConfigurer` 把 `/files/**` 映射到 `java2nb.uploadPath`。
- 轻量计数器：`book.visit_count/comment_count/yesterday_buy`、`news.read_count`（`NewsMapper.xml` 里 `read_count = read_count + 1`）。

### 1.6 数据模型层的已知不一致（面试可讲）

- `novel-admin` 的 `BookDO` / `mybatis/novel/BookMapper.xml` 仍是**旧库结构**：select 里带 `cat_child_id, cat_child_name, hero_name, lady_name, book_style, book_label`，而 `novel_plus.sql` 的 `book` 表没有这些列，按此脚本建库后台图书查询会报 Unknown column（生产库是否补过列：**未确认**）。
- `book.yesterday_buy` 只有读/排序，全仓库**未发现写入代码**（是否有外部统计任务：未确认）。
- `book_comment_reply` 的 `create_time`/`create_user_id` 注释写反了；`user_*` 的 `pre_content_id` 命名与真实语义（`book_index.id`）不符。
- 无任何 `FOREIGN KEY`；`sys_*` 关联表无联合唯一键；`order_pay` 的商户单号不唯一。
- `book_content` 的 `id` 在原表是自增，分表后由 ShardingSphere 雪花生成，与历史自增值（百万级）混用。

## 2. 缓存设计（`novel-common`）

接口 `novel-common/src/main/java/com/java2nb/novel/core/cache/CacheService.java`（String/Object 读写 + TTL 秒 + del/contains/expire），两个实现按 `cache.type` 条件装配：

- `EhCacheServiceImpl`：`@ConditionalOnProperty(prefix="cache", name="type", havingValue="ehcache")`，共用 cache 名 `util_cache`，配置 `ehcache.xml`（`diskStore user.dir/cachedata`，`util_cache` 为 `eternal=true, overflowToDisk=true, diskPersistent=true`）。
- `RedisServiceImpl`：`havingValue="redis"`，同时注入 `StringRedisTemplate` 与 `RedisTemplate<Object,Object>`，`del/contains/expire` 两个 template 都操作。

`CacheKey`（`novel-common/.../core/cache/CacheKey.java`）全部 key：

| Key 常量 / 实际 key | 含义 | TTL | 写入 / 失效时机 |
| --- | --- | --- | --- |
| `INDEX_BOOK_SETTINGS_KEY` = `indexBookSettingsKey` | 首页 31 条推荐（按 type 分组的 JSON 字符串） | **无**（Redis 不设 expire） | `BookServiceImpl.listBookSettingVO()` 写入；仅 `GET /cache/refresh/{pass}/1` 删除后重建 |
| `INDEX_NEWS_KEY` = `indexNewsKey` | 首页新闻列表 | 12h（`60*60*12`） | `NewsServiceImpl.listIndexNews()`；`/cache/refresh/{pass}/2` |
| `INDEX_LINK_KEY` = `indexLinkKey` | 首页友情链接 | 24h | `FriendLinkServiceImpl.listIndexLink()`；`/cache/refresh/{pass}/3` |
| `INDEX_CLICK_BANK_BOOK_KEY` = `indexClickBankBookKey` | 点击榜 | 5000s | `BookServiceImpl.listClickRank()` |
| `INDEX_NEW_BOOK_KEY` = `indexNewBookKey` | 新书榜 | 3600s | `BookServiceImpl.listNewRank()` |
| `INDEX_UPDATE_BOOK_KEY` = `indexUpdateBookKey` | 更新榜 | 600s | `BookServiceImpl.listUpdateRank()` |
| `TEMPLATE_DIR_KEY` + clientId = `templateDirKey{32位UUID}` | PC/移动模板目录（`""` 或 `"mobile/"`） | 24h | `NovelFilter`（`?to=pc/mobile` 或 UA 判断）；`ThreadLocalUtil` 读 |
| `RUNNING_CRAWL_THREAD_KEY_PREFIX` + sourceId | 某爬虫源正在运行的线程 ID 集合 | 无 | `CrawlServiceImpl` 启停爬虫；`CrawlThreadMonitor` 巡检 |
| `ES_LAST_UPDATE_TIME` = `esLastUpdateTime` | ES 增量同步水位（最后同步的 `book.update_time`） | 无 | `BookToEsSchedule` 每轮结束写回 |
| `ES_TRANS_LOCK` = `esTransLock` | ES 同步互斥锁（非严格分布式锁） | 20min | 任务开始 set，结束 del（异常路径也 del） |
| `ES_IS_UPDATE_VISIT` + bookId | 单本书 ES 点击更新的节流标记 | 1h | MQ 监听 `updateEs`；失败时提前 del 允许重试 |
| `BOOK_ADD_VISIT_COUNT` + bookId | 点击量内存累积 | 无 | 每次 +1，累计 ≥ `Constants.ADD_MAX_VISIT_COUNT=10` 写库后 del |
| `BOOK_TEST_PARSE` + url | 爬虫规则测试的页面 HTML | 10min | `CrawlController` 规则测试 |

清缓存只有两条路：**TTL 自然过期** 和 **`novel-front` 的 `CacheController` 手动刷新**（`GET /cache/refresh/{pass}/{type}`，密码来自 `cache.manager.password=novel@2020117`，type 1/2/3 分别对应推荐/新闻/友链）。`novel-admin` 里**没有** `CacheService`/`CacheKey` 调用，后台改数据不会主动清前台缓存——这也是为什么保留这个带密码的刷新接口。

风险点：`EhCacheServiceImpl.set(key,value)` 每次都会 `cache.getCacheConfiguration().setEternal(true)`，而 Ehcache 2.x 中 cache 为 eternal 时 element 的 TTL 不生效；叠加 `util_cache` 本身配置 eternal，Ehcache 模式下的「过期时间」很可能全部失效（实际行为需实测确认）。

## 3. 搜索（Elasticsearch）

### 3.1 索引定义（`doc/es/index_create.txt`）

`PUT /novel`，`mappings.book.properties`（**ES6 带 type 的旧写法**）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | long | `book.id`，同时作为文档 `_id` |
| `authorId` | long | 作者 ID（爬虫书为空） |
| `authorName` | text, ik_smart, boost 1.9 | 高亮字段 |
| `bookName` | text, ik_smart, boost 2 | 权重最高 |
| `bookDesc` | text, ik_smart, boost 0.1 | 简介 |
| `bookStatus` | short | 0 连载/1 完结（filter） |
| `catId` | integer | 分类（filter） |
| `catName` | text, ik_smart, boost 1.0 | 高亮字段 |
| `lastIndexId` | long | 最新章节 ID |
| `lastIndexName` | text, ik_smart, boost 0.1 | 高亮字段 |
| `lastIndexUpdateTime` | **keyword** | 写入格式 `yyyy/MM/dd HH:mm`，范围过滤/排序用字符串比较 |
| `picUrl` | keyword | 封面 |
| `score` | float | 评分 |
| `wordCount` | integer | 字数（range） |
| `workDirection` | short | 0 男频/1 女频（filter） |
| `visitCount` | long | 点击量（排序） |

脚本未设置分片/副本与 settings，依赖集群默认；`ik_smart` 需要安装 IK 插件（仓库不带插件）。

### 3.2 写入 / 查询 / 与 MySQL 的关系

- **写入**：`novel-front/.../SearchServiceImpl.importToEs(Book)`，`RestHighLevelClient.index(IndexRequest("novel").id(book.id))`，文档体是 `EsBookVO`（`BeanUtils.copyProperties` 后把 `lastIndexUpdateTime` 格式化成 `yyyy/MM/dd HH:mm`）。
- **两条触发链**：
  1. `BookToEsSchedule`（`@ConditionalOnProperty(spring.elasticsearch.enable=1)`）每 60s 一轮：拿 `esTransLock`（20min）→ 读水位 `esLastUpdateTime`（无则 2020-01-01）→ `queryBookByUpdateTimeByPage(lastDate, 100)` → 逐本 `importToEs` 且 `Thread.sleep(5000)` → 水位前移 → 释放锁。
  2. RabbitMQ 开启时（`spring.rabbitmq.enable=1`），`BookController.addVisitCount` 发 `ADD-BOOK-VISIT-EXCHANGE`（Fanout），`BookVisitAddListener.updateEs` 消费 `UPDATE-ES-QUEUE`，每本书 1 小时最多刷一次 ES。
- **查询**：`BookServiceImpl.searchByPage` 在 `esEnable==1` 时先走 `SearchServiceImpl.searchBook`，抛异常则 catch 后**回退 MySQL**（PageHelper + `BookMapper.xml` 的 `like` 查询）。ES 侧用 Jest 执行：`bool.must(query_string(keyword))` + `filter(term workDirection/catId/bookStatus)` + `range(wordCount/lastIndexUpdateTime)` + 5 字段高亮（`<span style='color:red'>`，fragmentSize 20000）+ 排序 + `from/size`；总数用 Jest `Count`，再手工拼 `PageBean`。
- **与 MySQL 的关系**：MySQL 是唯一事实源，ES 只是检索副本；同步是「定时 + 近实时」，正常延迟约 1 分钟（单轮 100 本、每本 sleep 5s 会进一步拉长），**不是双写、没有事务**，也**未发现删除同步**（删书/下架不会从 ES 移除）。
- 客户端混用：查询用 `io.searchbox:jest:6.3.1`，写入用 `elasticsearch-rest-high-level-client:7.9.3`；仓库里没有显式 `JestClient` Bean（`EsConfig` 只建 `RestHighLevelClient`，且仅在 `enable=1` 时生效；默认 `RestHighLevelClient` 应由 `spring-boot-starter-data-elasticsearch` 自动配置提供——Bean 来源未在仓库中确认）。
- 潜在坑：建索引脚本是 `mappings.book`（带 type），写入代码不指定 type（落到 `_doc`），在 ES7 上直接执行该脚本需要 `include_type_name=true`，否则 mapping 与写入类型对不上——实际部署版本行为未确认。

## 4. 配置项（`application*.yml` 要点）

| 项 | novel-front | novel-admin | novel-crawl |
| --- | --- | --- | --- |
| 端口 | **8083**（`application.yml`，README 里写的 8080 已过时） | **80** | **8081** |
| 激活 profile | `dev`，`include: website,alipay,oss,fastdfs` | `dev` | `dev` |
| 数据源 | 继承 `application-common-dev.yml` | **独立 Druid**：`jdbc:mysql://127.0.0.1:3306/test`，root/test123456 | 继承 common-dev |
| 连接池 | HikariCP（Sharding `ds0`） | Druid（initial 1 / min 3 / max 20 / maxWait 60s，filters stat,slf4j） | 同 front |
| Redis | common-dev：`127.0.0.1:6379`，password `test`，jedis pool 8/8/0，timeout 30000 | 独立：同址同密码，pool max-active 100、min-idle 10、timeout 10000 | 同 front |
| ES | `spring.elasticsearch.enable: 0`，`jest.uris: http://192.168.0.105:9200` | 无 | 无 |
| RabbitMQ | `enable: 0`，`virtual-host: /novel-plus`，exchange `novel.exchange` | 无 | 无 |
| 上传限制 | 1MB（common） | 30MB | 1MB |
| 文件路径 | `pic.save.type: 1`（dev，直接用源站图）/`2`（prod）、`storage: local`、`path: /Users/xiongxiaoyang/java`（dev）或 `/var/pic`（prod） | `java2nb.uploadPath: /var/pic/` | 无 |
| 正文存储 | `content.save.storage: db`、`path: /Users/xiongxiaoyang/books` | — | 同 front |
| JWT | `jwt.secret: novel!#20191230`、`expiration: 604800`（7 天，HS512） | — | — |
| 线程池 | `thread.pool` core 10 / max 20 / keepAlive 10s / queue 100（dev）、1000（prod），`AbortPolicy` | — | 单本任务线程 1 个 + `crawl.update.thread: 1` |
| 其它 | `cache.manager.password`、`xss.*`、`author.income.*`、`book.price.*`（1000 字 = 5 屋币）、`website.*`、`alipay.*`、`oss.*`、`fdfs.*` | `java2nb.username/password: admin/111111`（仅登录页预填）、`server.session-timeout: 18000` | `admin.username/password: admin/admin`（Security 内存用户） |

需要注意的配置细节：

- **数据源库名不一致**：`application-common-*.yml` 的 `spring.datasource.url` 指向 `novel_biz`，而 ShardingSphere 的 `ds0.jdbc-url` 指向 `novel_plus`；实际生效的应是 Sharding 数据源（`novel_plus`），`spring.datasource` 更像遗留配置（未确认是否被覆盖）。
- `novel-admin` 完全不走 common 配置，`jdbc:mysql://.../test` 必须手改成业务库。
- 分页：`pagehelper-spring-boot-starter:1.2.5` + `orderbyhelper-spring-boot-starter:1.0.2`，无 pagehelper 参数配置；`PageBuilder.build()` 产出 `io.github.xxyopen.model.page.PageBean`。
- `spring.jackson.generator.write-numbers-as-strings: true`（common）：所有数字（含雪花 ID）序列化成字符串，避免 JS 精度丢失；admin 侧另有 `LongToStringSerializer`。
- Redisson 配置 `redisson.singleServerConfig.address` 还在 front 的 `application.yml`，但 `redisson-spring-boot-starter` 依赖在 `novel-front/pom.xml` 中被注释，分布式锁代码也全被注释——**当前版本没有真正的分布式锁**。
- `spring.profiles.include` 链：`dev → common-dev → common`（common-dev 内部 `include: [common]`）。

## 5. 部署与运行

### 5.1 打包（`mvn clean package`，`maven.test.skip=true`）

- 父 `pom.xml` 聚合 4 模块，`novel-common` 是普通 jar；front/crawl/admin 各自用：
  `maven-shade-plugin`（把同 groupId 的 `novel-common` 打进模块 jar）+ `spring-boot-maven-plugin`（`layout=ZIP`，`includes` 一个不存在的 `non-exists`，等于**不把三方依赖打进 jar**）+ `maven-dependency-plugin`（依赖复制到 `target/lib`）+ `maven-antrun-plugin`（拼装 `target/build/` 并打 zip）。
- 产物结构（`target/build/novel-front.zip`）：`novel-front.jar`（应用 + common 类）、`lib/`（三方 jar）、`conf/`（模块 resources + `novel-common` resources，但排除 `mybatis/*/*.xml`，所以 Mapper XML 留在 jar 内）、`bin/`（`start.sh`、`stop.sh`、`windows-start.bat`、`readme.txt`）。
- 启动命令：`java -jar -Dloader.path=conf,lib novel-front.jar`（`start.sh` 还带 G1/GC 日志/HeapDump 参数，Windows bat 用 CMS + 1G 堆）。**必须**带 `loader.path`，否则 `conf/` 与 `lib/` 都不生效。
- 开发态直接跑 `*Application` 主类即可（`dev` 配置在 classpath）。

### 5.2 静态资源 / 模板 / 上传文件

- 模板：`templates/{orange,dark,blue}/{html,static}`（仓库根目录）。prod 通过 `spring.thymeleaf.prefix: file:${user.dir}/templates/${templates.name}/html/`、`spring.resources.static-locations: file:${user.dir}/templates/${templates.name}/static/` 读取，所以 **jar 同级目录必须有 `templates/`**（README 第 4 步）。dev 走 Thymeleaf 默认 `classpath:/templates/`，即 `novel-front/src/main/resources/templates`（含 book/user/pay/mobile/author 等页面）。
- 前台用户上传图片：`FileController` 存到 `pic.save.path`，URL 前缀 `/localPic/yyyy/MM/dd/...`；`NovelFilter` 拦截 `/localPic/` 直接读磁盘并设置 10 天浏览器缓存（不走 Spring 静态资源）。
- 爬虫转存的网络封面：`CrawlPicTransSchedule` + `LocalFileServiceImpl/OSS/FastDFS`，按 `pic.save.storage` 条件装配。
- 后台文件：`/files/**` → `file:///{java2nb.uploadPath}`（`WebConfigurer`），Shiro 对 `/files/**` 放行。
- 前台模板切换：`NovelFilter` 用 Cookie `userClientMarkKey` + `templateDirKey{clientId}` 决定 `""`（PC）或 `"mobile/"`，页面返回 `ThreadLocalUtil.getTemplateDir() + "book/..."`。

### 5.3 nginx 与日志

- 仓库内**没有 nginx 配置**，也不强制：front 自己提供页面/静态资源/`/localPic/`，admin 自己映射 `/files/**`。只有 FastDFS 模式依赖 `fdfs.webUrl: http://127.0.0.1/`（即 nginx 代理 FastDFS）；生产上通常用 nginx 反代 8083/80/8081 并做 HTTPS，但这是运维约定，不是代码要求。
- 日志（logback）：
  - front：`logback-boot.xml`，控制台 + `logs/novel-front.log`，滚动 `logs/debug.%d.%i.log`（10MB/文件，保留 30 天），root INFO、`com.java2nb` DEBUG。
  - crawl：`logs/novel-crawl.log`，只输出文件；admin：`logs/debug.log`，只输出文件，另有 `application-*.yml` 的 `logging.level` 覆盖（dev info/debug，prod error）。
  - `start.sh` 会创建 `logs/` 并传 `-Dlog.home`，同时把 stdout 重定向到 `logs/stdout.log`。
- 运行依赖：MySQL 8（`max_allowed_packet` 建议 100M，utf8mb4）、Redis（common 配置里始终存在）、可选 ES 7.x + IK、RabbitMQ、OSS/FastDFS、支付宝沙箱。

## 6. 公共模块能力清单

`novel-common` 只有 3 个顶级包：`core`（cache/converter/enums/advice/utils）、`entity`、`mapper`（MyBatis Dynamic SQL 生成物）。它**不提供** `Result/Page/异常`——这些来自外部依赖 `io.github.xxyopen:xxy-model / xxy-web / xxy-util:1.0.0`（`novel-common/pom.xml`）。

| 类 / 文件 | 路径 | 职责 |
| --- | --- | --- |
| `CacheService` | `novel-common/.../core/cache/CacheService.java` | 缓存统一接口（String/Object、TTL、del/contains/expire） |
| `CacheKey` | `novel-common/.../core/cache/CacheKey.java` | 全部缓存 key 常量（见第 2 节） |
| `EhCacheServiceImpl` | `novel-common/.../core/cache/impl/EhCacheServiceImpl.java` | Ehcache 实现（默认） |
| `RedisServiceImpl` | `novel-common/.../core/cache/impl/RedisServiceImpl.java` | Redis 实现（`cache.type=redis` 时启用） |
| `PageExceptionHandler` | `novel-common/.../core/advice/PageExceptionHandler.java` | `@ControllerAdvice(basePackages="...page")`，页面异常统一回 `404` 视图 |
| `ResponseStatus` | `novel-common/.../core/enums/ResponseStatus.java` | 业务错误码枚举（1001 未登录 … 9001 ES 查询失败 … 88001 密码错误），实现 `IResultCode` |
| `DateConverter` | `novel-common/.../core/converter/DateConverter.java` | 表单字符串→Date，支持 `yyyy-MM` / `yyyy-MM-dd` / 到秒 4 种格式 |
| `DateUtil` | `novel-common/.../core/utils/DateUtil.java` | 昨天/当天起止/上月起止时间，统计任务用 |
| `FileUtil` | `novel-common/.../core/utils/FileUtil.java` | 网络图转本地（`network2Local`）、写 TXT 章节、图片校验 |
| `HttpUtil` | `novel-common/.../core/utils/HttpUtil.java` | 基于 RestTemplate 的 GET（含伪装 Chrome UA），爬虫抓页 |
| `RestTemplateUtil` | `novel-common/.../core/utils/RestTemplateUtil.java` | 构建连接池 + 信任所有证书的 RestTemplate（抓 https 源站） |
| `IpUtil` | `novel-common/.../core/utils/IpUtil.java` | 从 `X-Real-IP`/`X-Forwarded-For` 等取真实 IP |
| `RandomValidateCodeUtil` | `novel-common/.../core/utils/RandomValidateCodeUtil.java` | 图形验证码，答案存 `CacheService`（`randomValidateCodeKey`） |
| `RandomBookInfoUtil` | `novel-common/.../core/utils/RandomBookInfoUtil.java` | 按评分造点击量（爬虫造数据） |
| `StringUtil` | `novel-common/.../core/utils/StringUtil.java` | 驼峰/下划线转换、正则工具 |
| `Generator` | `novel-common/.../core/utils/Generator.java` | 跑 MyBatis Generator（`mybatis/generatorConfig.xml`，`MyBatis3DynamicSql` 模式） |
| `Book/BookIndex/BookContent…Mapper` | `novel-common/.../mapper/*.java` | 每表一个 Mapper + `*DynamicSqlSupport`（表/列元数据），前端/爬虫共用 |
| `R` | `novel-admin/.../common/utils/R.java` | 后台 `HashMap` 风格响应（`code/msg/data`），与前台 `RestResult` 两套 |
| `PageBean` / `Query` | `novel-admin/.../common/utils/` | 后台表格分页（`total/rows`）与 `offset/limit` 查询封装 |
| `BusinessException` / `CommonExceptionHandler` | `novel-admin/.../common/exception/` | 后台业务异常 + 全局异常处理（返回 R/页面） |
| `LogAspect` + `@Log` | `novel-admin/.../common/aspect/LogAspect.java` | 注解式操作日志，异步写 `sys_log` |
| `DataPermInterceptor` | `novel-admin/.../common/interceptor/DataPermInterceptor.java` | MyBatis `Executor` 插件，解析 SQL 的 where/order/limit 后注入数据权限条件 |
| `ShiroConfig` | `novel-admin/.../common/config/ShiroConfig.java` | Shiro 过滤链、Realm、Session（redis 或内存）、Ehcache/Redis CacheManager |
| `WebConfigurer` / `JnConfig` | `novel-admin/.../common/config/` | `/files/**` 静态映射、`java2nb.*` 配置绑定 |
| `RedisConfig` / `RedisUtil` | `novel-admin/.../common/config` / `utils` | Jackson 序列化的 `RedisTemplate`、通用 Redis 操作 |
| `MD5Utils` | `novel-admin/.../common/utils/MD5Utils.java` | 后台密码摘要：`md5(username + "1qazxsw2")` 迭代 2 次 |
| `XssFilter` | `novel-admin/.../common/xss/XssFilter.java`、`novel-front/.../core/filter/XssFilter.java` | XSS 过滤，front 仅对配置的 `xss.urlPatterns` 生效 |
| `IdWorker` | `novel-admin/.../common/utils/IdWorker.java` | 雪花 ID（前台实际用 `io.github.xxyopen.util.IdWorker`） |

没有自动配置：`novel-common` 无 `@Configuration`、无 `spring.factories`、无 `@ConfigurationProperties` 扫描入口；`application-common*.yml` 是靠各模块 `spring.profiles.include` 引入的普通配置文件，打包时被复制到 `conf/`。

## 7. 面试可讲 / 待确认清单

- 可讲：分表键选 `index_id`（章节）而非 `book_id`——章节读取是「按章节 ID 单条读」，哈希可均摊写放大，代价是按书批量读章节要跨 10 表。
- 可讲：`book_content` 双存储 + `Map<String, Bean>` 消除 if/else，`storage_type` 落在章节维度支持平滑迁移。
- 可讲：缓存分层（页面缓存 / 榜单 TTL / 点击量攒批 / 模板路由）与「后台不清缓存、靠带密码接口手动刷」的取舍。
- 可讲：ES 只做检索副本、失败回退 MySQL，写路径是定时增量 + MQ 节流，接受最终一致。
- 待确认：`JestClient` Bean 来源、`novel_biz` 数据源是否真的被 Sharding 覆盖、ES 索引脚本在 ES7 上的 type 兼容性、Ehcache eternal 下 TTL 是否失效、`yesterday_buy` 的写入方。
