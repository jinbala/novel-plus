# novel-plus 读者端 + 作家端：业务流程与技术实现笔记

> 事实基线：`pom.xml` 版本 `3.6.1`，parent 为 `spring-boot-starter-parent 2.1.8.RELEASE`，`java.version=1.8`，四模块 `novel-common / novel-front / novel-crawl / novel-admin`。下文全部结论来自仓库源码实读，凡未在代码中确认的标「未确认」。

## 0. 版本与关键依赖

- `novel-front` 依赖 `novel-common`，另外引入：`jjwt 0.9.0`、`spring-boot-starter-amqp`、`jest 6.3.1` + `elasticsearch-rest-high-level-client 7.9.3`、`aliyun-sdk-oss`、`fastdfs-client`、`alipay-sdk-java 4.9.153.ALL`。
- 分页/统一返回/工具类来自第三方 `io.github.xxyopen:xxy-model / xxy-web / xxy-util 1.0.0`：`RestResult`、`PageBean`、`PageBuilder`、`IdWorker`、`MD5Util`、`BusinessException`、`SpringUtil`。这些类的源码不在本仓库，字段名只能由前端用法反推（`code/msg/data`、`list/total/pageNum/pageSize`）。
- 数据访问两条腿：**MyBatis Dynamic SQL 1.1.4**（`select/update/delete DSL` 拼 SQL，绝大多数查询）+ **XML Mapper**（`novel-front/src/main/resources/mybatis/mapping/*.xml`，只用于联表查询和自增计数）。
- 生产环境模板与静态资源在 jar 外：`novel-front/src/main/resources/application-prod.yml` 里 `spring.thymeleaf.prefix=file:${user.dir}/templates/${templates.name}/html/`、`spring.resources.static-locations=file:.../templates/orange/static/`；开发环境用 classpath 下的 `templates/`。

## 1. 路由与页面

### 1.1 页面路由（返回 Thymeleaf 视图名，非 JSON）

`novel-front/src/main/java/com/java2nb/novel/page/PageController.java` 是本项目页面路由的核心：**绝大多数页面没有独立 `@RequestMapping`，靠三条通配路由 + 同名模板文件**。

| URL 模式 | 处理方法 | 返回 | 说明 |
|---|---|---|---|
| `/{url}.html` | `module()` | 视图 `url` | 如 `/404.html` |
| `/{module}/{url}.html` | `module2()` | 视图 `module/url` | `/user/login.html`→`user/login`；`/author/**` 先鉴权：未登录 `redirect:/user/login.html?originUrl=...`，已登录非作者 `redirect:/author/register.html` |
| `/{module}/{classify}/{url}.html` | `module3()` | 视图 `module/classify/url` | 三级目录页面 |
| `/`、`/index`、`/index.html` | `index()` | `{templateDir}index` | 并发装配 `bookMap`、`newsList` |
| `/book/bookclass.html` | `bookClass()` | `book/bookclass` | **硬编码，不加模板目录前缀** |
| `/book/book_ranking.html` | `bookRank()` | `{templateDir}book/book_ranking` | |
| `/book/{bookId}.html` | `bookDetail()` | `{templateDir}book/book_detail` | 详情页 |
| `/book/indexList-{bookId}.html` | `indexList()` | `{templateDir}book/book_index` | 目录页 |
| `/book/{bookId}/{bookIndexId}.html` | `bookContent()` | `{templateDir}book/book_content` | 阅读页 |
| `/book/comment-{bookId}.html` | `commentList()` | `book/book_comment` | 书评列表页 |
| `/about/newsInfo-{newsId}.html` | `newsInfo()` | `about/news_info` | 新闻详情 |
| `/author/register.html` | `authorRegister()` | `author/register` 或 `redirect:/author/index.html` | GET 渲染 / POST 提交入驻 |

**双端模板机制**：除 `bookClass()` 外，所有视图名都拼 `ThreadLocalUtil.getTemplateDir()`，返回 `""`（PC）或 `"mobile/"`（WAP），因此 `templates/` 与 `templates/mobile/` 各有一套 `index.html`、`book/book_detail.html`、`book/book_content.html` 等。前缀来源：`NovelFilter`（`novel-front/.../core/filter/NovelFilter.java`）按 `?to=pc|mobile` 写 `CacheKey.TEMPLATE_DIR_KEY+clientId`（TTL 24h），否则用 `BrowserUtil.isMobile(req)` 判定；clientId 是写进 cookie `userClientMarkKey` 的 UUID。

### 1.2 JSON 接口（`@RestController`，统一 `RestResult`）

- `BookController`（`@RequestMapping("book")`）：`GET listBookSetting`、`listClickRank`、`listNewRank`、`listUpdateRank`、`listBookCategory`、`searchByPage`、`queryBookDetail/{id}`、`listRank?type&limit`、`queryBookIndexAbout?bookId&lastBookIndexId`、`listRecBookByCatId`、`listCommentByPage`、`queryNewIndexList`、`queryIndexList`；`POST addVisitCount`、`addBookComment`。
- `UserController`（`user`）：`POST login`、`register`、`refreshToken`、`addToBookShelf`、`addReadHistory`、`addFeedBack`、`updateUserInfo`、`updatePassword`、`buyBookIndex`；`GET queryIsInShelf`、`listBookShelfByPage`、`listReadHistoryByPage`、`listUserFeedBackByPage`、`userInfo`、`listCommentByPage`；`DELETE removeFromBookShelf/{bookId}`。
- `AuthorController`（`author`）：`GET checkPenName`、`listBookByPage`、`queryIndexContent/{indexId}`、`listIncomeDailyByPage`、`listIncomeMonthByPage`；`POST addBook`、`updateBookStatus`、`updateIndexName`、`addBookContent`、`updateBookContent`、`updateBookPic`；`DELETE deleteIndex/{indexId}`。
- `PayController`（`@Controller`，`pay`）：`POST aliPay`、`ANY aliPay/notify` —— **两个方法返回 void，直接往 `HttpServletResponse` 写支付宝表单 HTML / `success`|`fail` 文本**，不是 JSON 也不是视图。
- `NewsController`（`news`）：`listIndexNews`、`listByPage`、`POST addReadCount`。
- `FileController`（`@Controller`，`file`）：`GET getVerify` 输出 `image/jpeg` 验证码；`POST picUpload` 带 `@ResponseBody` 返回 `RestResult<String>`。
- `CacheController`（`cache`）：`GET refresh/{pass}/{type}`，type 1 首页推荐书、2 新闻、3 友链，密码取自 `cache.manager.password`。
- `FriendLinkController`（`friendLink`）：`listIndexLink`。
- `BaseController`（非 Controller）：`getToken()`（先读 cookie `Authorization`，再读请求头 `Authorization`）、`getUserDetails()`（解析 JWT 得 `UserDetails`）、`jwtTokenUtil` setter 注入。

### 1.3 通配路由对应的页面模板（`novel-front/src/main/resources/templates/` 实有文件）

| 请求 URL | 命中的通配路由 | 模板文件 |
|---|---|---|
| `/user/login.html`、`/user/register.html`、`/user/userinfo.html`、`/user/setup.html`、`/user/set_name.html`、`/user/set_sex.html`、`/user/set_password.html`、`/user/favorites.html`、`/user/read_history.html`、`/user/comment.html`、`/user/feedback.html`、`/user/feedback_list.html` | `{module}/{url}.html` | `user/*.html` |
| `/author/index.html`、`/author/book_add.html`、`/author/content_add.html`、`/author/content_update.html`、`/author/index_list.html`、`/author/author_income.html`、`/author/author_income_detail.html` | 同上（额外经 `/author/**` 鉴权） | `author/*.html` |
| `/pay/index.html` | 同上 | `pay/index.html` |
| `/about/contact.html`、`/about/copyright.html`、`/about/news.html`、`/about/submission.html`、`/about/user_agreement.html` | 同上 | `about/*.html` |
| `mobile/index.html`、`mobile/book/*`、`mobile/user/login.html` | 由 `ThreadLocalUtil` 视图前缀切换（`?to=pc|mobile` 只是写缓存标记，不是 URL 路由） | `templates/mobile/**` |

## 2. 读者端核心流程

### 2.1 首页
`PageController.index()` 用 `CompletableFuture.supplyAsync(..., threadPoolExecutor)` 并行取两块数据后 `get()` 汇合：
- `BookServiceImpl.listBookSettingVO()`：先读缓存 `indexBookSettingsKey`；未命中则 `FrontBookSettingMapper.listVO()`，若首页未配置则 `initIndexBookSetting()` 用 `selectIdsByScoreAndRandom(31)` 按分数随机取 31 本，按序号切成 type 0~4（0~3 轮播、4~13 热销、14~18 本周、19~24 图推、25~30 经典）批量插入 `book_setting`；结果按 type 分组序列化 JSON 写缓存（**无 TTL**，靠 `/cache/refresh/1/{pass}` 手动刷）。模板按 `bookMap['0']`…`bookMap['4']` 渲染。
- `NewsServiceImpl.listIndexNews()`：缓存 `indexNewsKey`，TTL 12h，取最新 2 条新闻。

### 2.2 分类 / 搜索（`book/bookclass.html` + `GET /book/searchByPage`）
- 分类项 `GET /book/listBookCategory` → `BookCategoryMapper`（DSL 查询，按 `sort` 排序，无缓存）。
- 搜索：前端把筛选条件拼成 `BookSpVO`（`keyword/workDirection/catId/bookStatus/wordCountMin/wordCountMax/updatePeriod/sort`）+ `curr/limit`。`BookServiceImpl.searchByPage()`：
  1. `updatePeriod`（近 N 天更新）先换算成 `updateTimeMin = now - N*24h`；
  2. `spring.elasticsearch.enable == 1` → 走 `SearchServiceImpl.searchBook()`（ES 索引名 `novel`，`boolQuery`：`queryStringQuery(keyword)` + `term` 过滤 + `wordCount`/`lastIndexUpdateTime` range，Jest 做 count/搜索、`RestHighLevelClient` 做写入，5 字段高亮 `<span style='color:red'>`，`from/size` 分页），异常时**降级**继续走 MySQL；
  3. MySQL 路径：`PageHelper.startPage(page,pageSize)` + `OrderByHelper.orderBy(sort+" desc")` + `FrontBookMapper.searchByPage`（`BookMapper.xml` 里 `word_count>0` + 动态 `<if>` 条件）。
- 模板靠 layui `laypage` 渲染分页，翻页时重复调同一接口。

### 2.3 排行榜（`book/book_ranking.html` + `GET /book/listRank`）
`listRank(type, limit)`：type 0 按 `visit_count`、1 按 `create_time`、2 按 `last_index_update_time`、3 按 `comment_count` 倒序，条件 `word_count > 0`。**只看 MySQL，不查 ES。** 首页三个榜单再包一层缓存：`indexClickBankBookKey`(5000s)、`indexNewBookKey`(3600s)、`indexUpdateBookKey`(600s)。

### 2.4 小说详情页（`/book/{bookId}.html`）
`bookDetail()` 四条并行/链式任务：书信息 `queryBookDetail`（DSL `where id=`）；评论首页 `listCommentByPage(null,bookId,1,5)`；`thenApplyAsync` 依赖书信息查首章 `queryFirstBookIndexId`（按 `index_num` 升序 limit 1，用于「点击阅读」）；同分类随机推荐 `listRecBookByCatId`（XML：`order by RAND() LIMIT 4`）。
- 章节数与最新章节前 42 字：页面加载后 `POST /book/queryBookIndexAbout`，`queryIndexCount`（`count(id)`）+ 取 `last_index_id` 内容截断 42 字。
- **点击量**：详情页与阅读页 `$.post("/book/addVisitCount", {bookId})`，每次刷页 +1，无去重。`addVisitCount` 在 `spring.rabbitmq.enable==1` 时发到 fanout 交换机 `ADD-BOOK-VISIT-EXCHANGE`（两个队列 `UPDATE-DB-QUEUE`/`UPDATE-ES-QUEUE`），否则直接 `bookService.addVisitCount(bookId,1)`。`BookVisitAddListener` 侧累积到 `bookAddVisitCount{bookId}`，满 `Constants.ADD_MAX_VISIT_COUNT=10` 才落库；ES 侧用 `esIsUpdateVisit{bookId}`(1h) 节流。
- 书评在模板 `th:each` 服务端渲染前 5 条，另提供 `POST /book/listCommentByPage` 给「全部评论」页。

### 2.5 目录页（`/book/indexList-{bookId}.html`）
`bookService.queryIndexList(bookId, null, 1, null)`：`page/pageSize` 传 `1/null` ⇒ 不加 PageHelper，**一次查全书章节**（只取 `id/bookId/indexNum/indexName/updateTime/isVip` 六列），模板 `th:each` 全量渲染，VIP 章节加 `vip` 标记。

### 2.6 阅读页（`/book/{bookId}/{bookIndexId}.html`）
六个并行任务，其中 4 个链在「章节信息」之后：
1. 书信息 `queryBookDetail`；
2. 章节 `queryBookIndex(bookIndexId)`（含 `wordCount/bookPrice/isVip/storageType`）；
3. 上一章 `queryPreBookIndexId(bookId,indexNum)`：`index_num < ?` 倒序 limit 1，无则返回 `0L`；
4. 下一章 `queryNextBookIndexId`：`index_num > ?` 升序 limit 1，无则 `0L`（前端 `enterPreIndexPage/enterNextIndexPage` 遇 0 跳目录页）；
5. **正文**：`bookContentServiceMap.get(bookIndex.getStorageType()).queryBookContent(...)` —— 注入的是 `Map<String,BookContentService>`（key=bean 名），两种实现：
   - `@Service("db")` `DbBookContentServiceImpl`：按 `index_id` 查 `book_content`；
   - `@Service("txt")` `FileBookContentServiceImpl`：`BufferedReader` 读 `${content.save.path}/{bookId}/{bookIndexId}.txt` 后拼接。
   `book_index.storage_type` 默认 `'db'`（`doc/sql/20210913.sql` 新增列）。`application-common-dev.yml` 里 `content.save.storage: db`。
6. `needBuy`：`is_vip==1` 且（未登录 或 `queryIsBuyBookIndex` 无记录）→ true。模板 `th:if="${needBuy}"` 走「VIP 章节，需订阅」区块，否则 `th:utext="${bookContent.content}"` 输出正文。
- **分表**：`book_content` 在 `application-common-dev.yml` 配了 ShardingJDBC 3.0.0 分表 `book_content${index_id % 10}`（`doc/sql/novel_plus.sql` 里有 `book_content0..book_content9` 建表）。同一份 profile 里也声明了 `spring.datasource`，实际运行时走哪个 `DataSource` 未在本仓库验证（未确认）。
- **阅读进度/书架**（前端驱动）：进入页面先 `GET /user/queryIsInShelf`，`code==200` 后再 `POST /user/addReadHistory {bookId, preContentId=当前章节id}`。服务端 `addReadHistory` 先删该用户该书旧记录再插入 `user_read_history`（唯一键 `user_id+book_id`），同时把 `user_bookshelf.pre_content_id` 更新为当前章（所以字段名虽叫 pre_content_id，存的其实是「上次读到」的章节 id）。加书架 `POST /user/addToBookShelf`（幂等：先 `queryIsInShelf`），移出 `DELETE /user/removeFromBookShelf/{bookId}`，列表 `GET /user/listBookShelfByPage`（XML 联表 `book`）。
- 阅读偏好（字号/主题/字体）存 `localStorage`（`fonts/colorNum/fontNum`），后端不参与。

### 2.7 书评 / 段落评论 / 书单
- 书评：`book_comment`（唯一键 `book_id+create_user_id`，一人一书一条）。发表 `POST /book/addBookComment` → `@Transactional` 里先 `count` 判重（重复抛 `HAS_COMMENTS 3001`），再插入并 `bookMapper.addCommentCount` 自增 `book.comment_count`。查询 XML：`book_comment t1 inner join user t2`，`OrderByHelper.orderBy("t1.create_time desc")` + PageHelper；`BookCommentVO.createUserName` 用 `CommentUserNameSerialize` 脱敏（`前4位+"****"+后3位`，仅 JSON 输出生效）。
- 段落评论：**不存在**（全文无相关代码）。
- 书单：**不存在**（`novel_plus.sql` 无书单表）。
- 另有 `book_comment_reply`、`book_screen_bullet` 两张表只在 DDL 中存在，Java/模板中**无任何引用**（`book_content.html` 的弹幕区块已被整段注释）。

### 2.8 注册 / 登录 / 鉴权：JWT，不是 Session
- 生成：`JwtTokenUtil.generateToken(UserDetails)` → `claims.sub = new ObjectMapper().writeValueAsString(userDetails)`（`UserDetails` 只有 `id/username/nickName`）、`created`，`signWith(HS512, ${jwt.secret})`，过期 = `now + ${jwt.expiration}`。仓库内配置：`jwt.secret: novel!#20191230`、`jwt.expiration: 604800`（7 天），见 `novel-front/src/main/resources/application.yml`。
- 下发/保存：`POST /user/login`、`/user/register` 返回 `{token}`，前端 `$.cookie('Authorization', token, {path:'/'})`（勾选 `localStorage.autoLogin=1` 时 `expires:7`）。token 存 **非 HttpOnly cookie**，JS 可读。
- 校验：`BaseController.getToken()` 先 cookie 后 header，`JwtTokenUtil.getUserDetailsFromToken()` → 先判过期再 `parseClaimsJws` 取 `sub` 反序列化；解析异常只打日志返回 null。
- **没有拦截器/过滤器做鉴权**：`WebMvcConfig` 只注册了 `DateConverter`；所有鉴权都在 Controller 内手动调 `getUserDetails(request)`，未登录时 `@RestController` 返回 `RestResult.fail(ResponseStatus.NO_LOGIN)`（code **1001**），前端见到 1001 就跳登录。页面侧仅 `PageController.module2`（`/author/**`）做服务端重定向，其余「需登录页面」由 `static/javascript/common.js` 的 `needLoginPath` 数组在前端拦截。
- 续期：`POST /user/refreshToken` → `canRefresh`（未过期）→ `refreshToken`（重置 `created`、重签、过期时间顺延），前端每次页面加载都调一次并回写 cookie。
- 密码：`MD5Util.MD5Encode(password, UTF-8)`（`UserServiceImpl.register/login/updatePassword`），**未见加盐**。

### 2.9 充值 / 订阅（`PayController`）
- 充值页 `pay/index.html`：`form action="/pay/aliPay" method="post"`，隐藏域 `payAmount`（单位**元**，10/30/50/100/200/500 档）；页内展示支付宝、微信两个图标，但微信点选直接 `layer.alert("微信支付暂未开通")`，后端也只有支付宝实现。
- 下单：`POST /pay/aliPay`（未登录 `sendRedirect` 到登录页）→ `OrderServiceImpl.createPayOrder(payChannel=1, payAmount, userId)`：`out_trade_no = yyyyMMddHHmmssSSS + Random().nextInt(10)` 转 `long`，插入 `order_pay`（`pay_status` 由 DDL 默认 `2=待支付`）→ 拼 `AlipayTradePagePayRequest`（`product_code=FAST_INSTANT_TRADE_PAY`、`total_amount=payAmount`、`subject=小说精品屋-plus`、`notify_url/return_url` 来自 `AlipayProperties`）→ `pageExecute(...).getBody()` 直接把表单 HTML 写回响应。
- 回调：`/pay/aliPay/notify` 用 `AlipaySignature.rsaCheckV1` 验签；通过则取 `out_trade_no/trade_no/trade_status` → `updatePayOrder`：仅当 `pay_status != 1` 且 `trade_status ∈ {TRADE_SUCCESS, TRADE_FINISHED}` 时置 `pay_status=1` 并 `userService.addAmount(userId, totalAmount*100)`（**1 元 = 100 屋币**）；返回 `success`/`fail` 文本。
- 订阅（章节购买）：`POST /user/buyBookIndex`（`UserBuyRecord`：bookId/bookName/bookIndexId/bookIndexName）→ Controller 用 `bookService.queryBookIndex(...).getBookPrice()` **覆盖**前端传的 `buyAmount` → `UserServiceImpl.buyBookIndex`：查余额不足抛 `USER_NO_BALANCE 1007`，插入 `user_buy_record`（唯一键 `user_id+book_index_id`）+ 扣减 `user.account_balance`。价格在发布章节时按 `${book.price.value} / ${book.price.word-count}` 算出（5 屋币/千字，向下取整）。
- 订单状态流转：`2 待支付 → 1 支付成功`（DDL 注释另有 `0 支付失败`，代码中未见写入路径）。

### 2.10 三条关键时序（按代码实际调用顺序）

**A. 登录/会话续期**
1. `user/login.html` 提交 `POST /user/login {username, password}` → `UserServiceImpl.login` 用 `username + MD5(password)` 组合查询 `user` 表，无记录抛 `USERNAME_PASS_ERROR 1004`。
2. 命中后组装 `UserDetails{id,username,nickName}` → `jwtTokenUtil.generateToken` → 返回 `{token}` → 前端写 cookie `Authorization`（勾选自动登录则 7 天）。
3. 之后每个页面 `common.js` 启动即 `POST /user/refreshToken`：`canRefresh` → `refreshToken` 续期 → 回写 cookie，同时把右上角换成昵称。
4. 后续所有接口靠 `BaseController.getUserDetails(request)` 现场解析 token；解析不到就返回 1001，前端跳登录。

**B. 充值**
1. `pay/index.html` 选面额 → `pay.js` 填隐藏域 `payAmount` → 表单 `POST /pay/aliPay`。
2. `createPayOrder(1, payAmount, uid)` 插 `order_pay`（`out_trade_no = yyyyMMddHHmmssSSS + 0~9`，`pay_status=2`）。
3. 拼 `AlipayTradePagePayRequest`（`total_amount=payAmount` 元）→ `pageExecute().getBody()` 写成 HTML 表单响应，浏览器自动跳支付宝。
4. 支付宝异步 `POST /pay/aliPay/notify` → `rsaCheckV1` 验签 → `updatePayOrder` → `pay_status=1` + `addAmount(uid, totalAmount*100)` 加屋币 → 输出 `success`。

**C. 阅读 VIP 章节**
1. `book/book_content.html` 隐藏域带 `bookId/bookIndexId/preContentId`，页面加载即 `POST /book/addVisitCount`。
2. 服务端渲染时 `needBuy` 已算好：`is_vip==1 && (未登录 || 未购买)`。
3. 若 `needBuy=true`，模板只显示「此章为 VIP 章节，价格 N 屋币」+「购买」按钮 → `POST /user/buyBookIndex`（价格以服务端 `book_index.book_price` 为准，忽略前端值）。
4. 成功后 `location.reload()`，重新走第 2 步，`needBuy=false` → `th:utext` 输出正文。
5. 同时（未登录则跳过）`GET /user/queryIsInShelf` → `POST /user/addReadHistory` 刷新阅读记录与书架进度。

## 3. 作家端

### 3.1 入驻
`/author/register.html`（`PageController.authorRegister`）：先要求已登录，再校验 `author_code` 表邀请码（`is_use=0 且 validity_time > now`），通过则写 `author` 表并把邀请码置为已用（`AuthorServiceImpl.register`，`@Transactional`），失败回显 `LabErr="邀请码无效！"`。入驻页是普通表单 POST（非 ajax），与非 JWT 接口风格不一致。

### 3.2 登录与准入
作家没有独立登录：复用会员 JWT。准入两道：页面级 `PageController.module2`（`/author/**` 未登录重定向登录页、非作者重定向入驻页）；接口级 `AuthorController.checkAuthor()`（未登录抛 `BusinessException(NO_LOGIN)`，`author.status==1`（封禁）抛 `AUTHOR_STATUS_FORBIDDEN 4002`），每个写操作都调用。

### 3.3 作品管理
- 列表 `GET /author/listBookByPage`：`authorService.queryAuthor(userId)` 取作者 → PageHelper 分页查本人 `book`（按 `create_time` 倒序，投影 `id/bookName/picUrl/catName/visitCount/yesterdayBuy/lastIndexUpdateTime/updateTime/wordCount/lastIndexName/status`）。
- 发布 `POST /author/addBook`：`bookDesc` 单独用 `@RequestParam` 接收（避免 Spring 去首尾空白），落库前 `\n→<br>`、`\s→&nbsp;` 转义；`addBook` 校验同笔名下书名唯一（重复抛 `BOOKNAME_EXISTS 4003`），强制 `visitCount=0、wordCount=0、score=6.5、lastIndexName=""`。
- 上下架 `POST /author/updateBookStatus`；封面上传走 `POST /file/picUpload` 再 `POST /author/updateBookPic`；删章节 `DELETE /author/deleteIndex/{indexId}`。
- 权限校验特征：所有写操作都在 SQL 的 `where` 里带 `author_id = 当前作者id`，操作不属于自己的书时**静默 return 而不是报错**（`addBookContent/deleteIndex/updateIndexName/updateBookContent/queryIndexContent` 均是 `if (book.getAuthorId().equals(authorId))`）。

### 3.4 章节发布 / 修改
- 发布 `POST /author/addBookContent {bookId, indexName, content, isVip}`（`@Transactional`）：校验书属于本人 → `IdWorker.INSTANCE.nextId()` 生成 `lastIndexId` → 更新 `book`（`last_index_id/last_index_name/last_index_update_time`、`word_count += 新增字数`）→ 算价 `wordCount * value / wordCount(1000)`（`RoundingMode.DOWN`）→ `indexNum = 上一章 indexNum + 1` → 插 `book_index` → 插 `book_content`。字数用 `StringUtil.getStrValidWordCount(content)`。
- 读取/修改：`GET /author/queryIndexContent/{indexId}` 返回前把 `<br>→\n`、`&nbsp;→空格` 还原；`POST /author/updateBookContent` 重算字数与价格并更新 `book_index` + `book_content`。
- 章节管理页 `author/index_list.html`、发布页 `author/content_add.html`（wangEditor）、修改页 `author/content_update.html`。

### 3.5 数据统计（收入）
- 每日 `DailyIncomeStaSchedule`（`cron 0 0 0 * * ?`）：以 `create_time` 为游标分批（每批 10 个作家，`do-while` 直到不足一批）统计昨天：按作品查 `user_buy_record` 的**订阅人数（count distinct user）/订阅次数/count 订阅额 sum**，写 `author_income_detail`（`book_id=0` 表示作家当日汇总）；用 `queryIsStatisticsDaily` 做幂等。
- 每月 `MonthIncomeStaSchedule`（`cron 0 0 2 1 * ?`）汇总上月 `author_income_detail.income_account`，按 `author.income` 配置计算：`share-proportion 0.7`、`tax-rate 0.9`、`exchange-proportion 0.01`，代码里还再 `*100`，写 `author_income`（`pre_tax_income/after_tax_income/pay_status/confirm_status`）。提现/结算审批不在这两个模块（未确认）。
- 作家端页面：`author/author_income.html`（`GET /author/listIncomeMonthByPage`）、`author/author_income_detail.html`（`GET /author/listIncomeDailyByPage?bookId&startTime&endTime`，日期默认 `2020-05-01 ~ 2030-01-01`）。

### 3.6 作家端页面清单（均在 `/author/*` 下，全部经页面级鉴权）

| 页面 | 主要接口 | 说明 |
|---|---|---|
| `author/index.html` | `GET /author/listBookByPage`、`POST /author/updateBookStatus`、`POST /file/picUpload` + `POST /author/updateBookPic`、`DELETE /author/deleteIndex/{id}` | 作品列表 + 上下架 + 换封面 + 删章入口 |
| `author/book_add.html` | `POST /author/addBook` | 发布新书（书名、分类、简介、封面） |
| `author/content_add.html` | `POST /author/addBookContent` | wangEditor 写正文 + `isVip` 免费/收费单选 |
| `author/index_list.html` | `GET /book/queryIndexList`（复用前台接口）、`POST /author/updateIndexName`、`DELETE /author/deleteIndex/{id}` | 单书章节管理（`?bookId=` 传入） |
| `author/content_update.html` | `GET /author/queryIndexContent/{indexId}`、`POST /author/updateBookContent` | 修改章节（读时 `<br>/&nbsp;` 还原） |
| `author/register.html` | 表单 `POST /author/register.html` | 邀请码入驻 |
| `author/author_income.html` / `author_income_detail.html` | `listIncomeMonthByPage` / `listIncomeDailyByPage` | 稿费月表 / 日明细 |

## 4. 技术实现细节

### 4.1 主要注解
`@SpringBootApplication + @EnableTransactionManagement + @EnableScheduling + @EnableCaching + @ServletComponentScan + @MapperScan("com.java2nb.novel.mapper") + @Import(FdfsClientConfig.class)`（`FrontNovelApplication`）；`@RestController/@Controller + @RequestMapping/@GetMapping/@PostMapping/@DeleteMapping + @PathVariable/@RequestParam + @ResponseBody`；`@Service/@Component/@Configuration/@Bean + @ConditionalOnProperty`（ES/RabbitMQ/文件存储实现/缓存实现均用条件装配切换）；`@Value`、`@ConfigurationProperties(prefix="alipay")`；`@Transactional(rollbackFor = Exception.class)`（评论、购章、发布/修改章节、下单回调、入驻）；`@Scheduled(cron/fixedRate)`；`@RabbitListener`；lombok `@Data/@Getter/@RequiredArgsConstructor/@Slf4j/@SneakyThrows`；`@Validated(AddGroup/UpdateGroup)`（xxy 校验分组）；`@JsonSerialize/@JsonFormat`。
**没有** `@ControllerAdvice` 处理 REST 异常（`PageExceptionHandler` 只覆盖 `com.java2nb.novel.page` 包，异常统一返回 `"404"` 视图）；`@RestController` 的 `BusinessException → RestResult` 转换由 `xxy-web` 提供（源码不在本仓库，未确认实现细节）。

### 4.2 缓存
`CacheService` 两个实现按 `cache.type` 条件装配：`ehcache`（默认，`EhCacheServiceImpl`，固定 cache 名 `util_cache`，`ehcache.xml` 里 `eternal=true`、`overflowToDisk=true`）与 `redis`（`RedisServiceImpl`，`StringRedisTemplate` + `RedisTemplate` 双模板）。Key 常量集中在 `novel-common/.../core/cache/CacheKey.java`：

| Key | TTL | 内容 |
|---|---|---|
| `indexBookSettingsKey` | 无（永久） | 首页 31 本推荐书，按 type 分组 JSON |
| `indexClickBankBookKey` | 5000s | 点击榜前 10 |
| `indexNewBookKey` | 3600s | 新书榜前 10 |
| `indexUpdateBookKey` | 600s | 更新榜前 23 |
| `indexNewsKey` | 12h | 首页新闻 2 条 |
| `indexLinkKey` | 24h | 友链 |
| `templateDirKey{clientId}` | 24h | PC/WAP 模板前缀 |
| `bookAddVisitCount{bookId}` | 随满 10 落库后删 | 点击量累加 |
| `esIsUpdateVisit{bookId}` | 1h | ES 更新节流 |
| `esTransLock` | 20min | ES 同步任务防重入 |
| `esLastUpdateTime` | 无 | ES 增量游标 |
| `randomValidateCodeKey` | 5min | 图形验证码（**全局单 key**） |

### 4.3 分页
PageHelper 1.2.5（`PageHelper.startPage(page,pageSize)`）+ OrderByHelper 1.0.2（`OrderByHelper.orderBy("...")` 追加 order by）+ xxy `PageBuilder.build(list)` → `PageBean`。接口统一入参 `curr`（默认 1）、`limit`（默认 5/10/20 视接口而定）。

### 4.4 统一返回与错误码
`RestResult.ok(data)` / `RestResult.fail(ResponseStatus)`。`ResponseStatus`（`novel-common/.../core/enums/ResponseStatus.java`）实现 `IResultCode`：`1001 未登录`、`1002 验证码错误`、`1003 手机号已注册`、`1004 手机号或密码错误`、`1005 两次密码不一致`、`1006 旧密码错误`、`1007 余额不足`、`3001 已评价过`、`4001 邀请码无效`、`4002 作者封禁`、`4003 同名小说`、`5001 小说已存在`、`9001 ES 查询错误`、`10001~10003 文件错误`、`88001 密码错误`。

### 4.5 文件上传（本地优先，可切 OSS / FastDFS）
`FileController.upload`：路径 `${Constants.LOCAL_PIC_PREFIX}/yyyy/MM/dd` + `UUID32 + 扩展名`，写到 `${pic.save.path}`，落盘后用 `FileUtil.isImage()` 校验，非图片删文件抛 `FILE_NOT_IMAGE`，返回相对路径（仅 `@ResponseBody` 返回 JSON）。`pic.save.storage` 三选一：`local`（`LocalFileServiceImpl`）、`OSS`（`OssFileServiceImpl`，桶不存在则建桶并设公共读）、`fastDfs`。`NovelFilter` 拦截含 `/localPic/` 的请求，直接把 `${pic.save.path}` 下对应文件流写回并设 10 天 expires（本地图片不进 Spring 静态资源链路）。上传大小限制 `spring.servlet.multipart.max-file-size=1MB`，前端 `checkPicUpload` 也限 1M。

### 4.6 Thymeleaf 模板与静态资源
- 片段化布局：`common/header.html` 提供 `th:fragment="common_head(title,meta,links,script)"`（含百度统计脚本），`common/top.html` 提供 `top(navType)`，`common/footer.html`、`common/js.html`（`js` 片段依次引入 jquery-1.8.0 / layui.all / header.js / common.js）；页面用 `<head th:replace="common/header :: common_head(...)">`、`<div th:replace="common/top :: top('10')">` 组装。
- 目录结构：`templates/{index,404}.html`、`templates/book/*`、`templates/user/*`、`templates/author/*`、`templates/about/*`、`templates/pay/index.html`、`templates/common/*`、`templates/mobile/**`（WAP 整套）。
- 静态资源 `static/` 下分 `css/`、`javascript/`（jquery 1.8、easyui、layui、wangEditor、`common.js/bookdetail.js/bookclass.js/pay.js+user.js`）、`images/`、`layui/`、`wangEditor/`、`mobile/`（含独立 `mobile/js/read.js`、`mobile/layui`）；模板里以 `/css/...`、`/javascript/...` 绝对路径引用（Boot 默认 `classpath:/static`）。
- 前端交互全部 jQuery + `$.ajax` 调 JSON 接口再拼 HTML 字符串（`$("#bookList").html(...)`），没有前后端分离、没有模板局部刷新；分页用 layui `laypage`。

### 4.7 其它机制
- 线程池：`ThreadPoolConfig` 按 `thread.pool.*`（dev 核心 10/最大 20/队列 100，prod 队列 1000）建 `ThreadPoolExecutor`，`AbortPolicy`；页面层用它跑 `CompletableFuture`。
- 定时任务：`@EnableScheduling` + `TaskScheduler` 池大小 5（避免定时任务串行）；任务见 §3.5、`BookToEsSchedule`（`fixedRate=60s`，`enable=1` 时增量导 ES，每次 `Thread.sleep(5000)` 控速）、`CrawlPicTransSchedule`。
- MQ：`spring.rabbitmq.enable=0` 默认关闭；开启后 fanout 交换机 `ADD-BOOK-VISIT-EXCHANGE` 同时绑 `UPDATE-DB-QUEUE`（每满 10 次点击落库）、`UPDATE-ES-QUEUE`（1 小时节流更新 ES）。
- 过滤器链：`NovelFilter`（`/*`，本地图片直出、clientId 生成、PC/WAP 判定）+ `XssFilter`（`xss.urlPatterns` 仅 6 个 URL：`/book/addBookComment,/user/addFeedBack,/author/addBook,/author/addBookContent,/author/updateBookContent,/author/register.html`，`order=Integer.MAX_VALUE`）。

### 4.8 代码里能确认的风险点（面试可讲）
1. `BookServiceImpl.searchByPage` 里 `OrderByHelper.orderBy(params.getSort()+" desc")`、`BookController./queryIndexList` 的 `orderBy` 直接来自客户端参数，ORDER BY 注入面（OrderByHelper 是否白名单未确认，外部 jar）。
2. `BookMapper.xml` 的 `addVisitCount` 用 `${visitCount}` 拼接（值来自服务端累加，非用户输入，但仍是拼接写法）。
3. JWT：无服务端黑名单/吊销，退出只删 cookie；token 存非 HttpOnly cookie；`sub` 里塞整个用户 JSON（体积/可读性）。
4. 图形验证码用**单一全局 key** `randomValidateCodeKey`，不区分会话/客户端，A 生成的验证码 B 也能用（并发注册场景）。
5. 支付回调只验签，未校验 `total_amount`/`seller_id`/`app_id`（`PayController` 注释里自己列出「建议添加」）；订单幂等仅靠 `pay_status != 1`，无锁。
6. 正文/简介/章节名走 `th:utext`，写库前只做 `\n→<br>`、`\s→&nbsp;` 替换，XSS 过滤只覆盖 6 个 URL —— 正文型 XSS 防护依赖 `XssHttpServletRequestWrapper`（其转义范围未逐行确认）。
7. 修改章节 `updateBookContent` 只更新 `book_index.word_count/book_price` 与 `book_content`，**没有回写 `book.word_count`**，全书字数会与章节字数之和不一致。
8. 详情页评论列表 `CommentUserNameSerialize` 用 `substring(0,4)+"****"+substring(len-3)`，用户名短于 4 位会抛 `StringIndexOutOfBoundsException`。
9. 点击量每次刷页 +1，无去重/限流，榜单易被刷。
10. 页面并行任务用 `CompletableFuture.get()` 串行汇合，池满（`AbortPolicy`）抛 `RejectedExecutionException`，页面侧统一被 `PageExceptionHandler` 兜成 404。

### 4.9 关键配置项速查（`novel-front/src/main/resources/*.yml` + `novel-common/.../*.yml`）

| 配置 | 值（仓库内） | 影响 |
|---|---|---|
| `server.port` | 8083 | 前台端口 |
| `spring.profiles.active/include` | `dev` + `website,alipay,oss,fastdfs` | 再经 `common-dev` → `common` 逐层 include |
| `jwt.secret` / `jwt.expiration` | `novel!#20191230` / `604800` 秒 | HS512 签名密钥与 7 天有效期 |
| `cache.type` | `ehcache`（可切 `redis`） | 决定 `CacheService` 实现 |
| `cache.manager.password` | `novel@2020117` | `/cache/refresh/{pass}/{type}` 的弱口令保护 |
| `spring.elasticsearch.enable` | `0` | 0 时搜索走 MySQL；开启后还需 `spring.elasticsearch.jest.uris` |
| `spring.rabbitmq.enable` | `0` | 0 时点击量同步落库；开启后走 fanout 削峰 |
| `xss.enabled` / `xss.urlPatterns` / `xss.excludes` | `true` / 6 个 POST 接口 / `/system/notice/*` | 只对列出的 URL 做 XSS 包装 |
| `book.price.word-count` / `book.price.value` | `1000` / `5` | 章节定价：5 屋币/千字（向下取整） |
| `author.income.tax-rate` / `share-proportion` / `exchange-proportion` | `0.9` / `0.7` / `0.01` | 月收入分佣与结算换算 |
| `thread.pool.*` | dev 10/20/10s/100，prod 10/20/10s/1000 | 页面异步任务池 |
| `content.save.storage` / `content.save.path` | `db` / `/Users/xiongxiaoyang/books` | 正文存储介质（`db` 或 `file`）与 txt 根目录 |
| `pic.save.type` / `pic.save.storage` / `pic.save.path` | dev `1/local`，prod `2/local` | 封面是网络图还是转存自建存储 |
| `spring.servlet.multipart.max-file-size` | `1048576`（1MB） | 上传上限 |
| `spring.jackson.generator.write-numbers-as-strings` | `true` | 所有数字被序列化成字符串（前端比较时用 `==`，如 `data.code == 200`） |
| `spring.thymeleaf.mode` / `cache` | `LEGACYHTML5` / `false` | 关闭严格校验、关闭模板缓存 |

> `write-numbers-as-strings=true` 是一个容易踩坑的点：按该 Jackson 配置，`RestResult.code` 等数字字段会被序列化成字符串（"200" 而非 200），这也解释了前端为何统一用 `data.code == 200` 这种松散比较；若改成 `===` 会集体失效（此结论为按配置推断，未跑接口实测）。

## 5. 关键类清单

| # | 包.类 | 职责 | 路径（相对仓库根） |
|---|---|---|---|
| 1 | `com.java2nb.novel.page.PageController` | 全部页面路由 + 首页/详情/目录/阅读页数据装配 + author 区页面鉴权 | `novel-front/src/main/java/com/java2nb/novel/page/PageController.java` |
| 2 | `com.java2nb.novel.controller.BaseController` | 从 cookie/header 取 JWT 并解析 `UserDetails` | `novel-front/src/main/java/com/java2nb/novel/controller/BaseController.java` |
| 3 | `...controller.BookController` | 书籍/分类/榜单/搜索/评论/点击量 JSON 接口 | `novel-front/src/main/java/com/java2nb/novel/controller/BookController.java` |
| 4 | `...controller.UserController` | 登录注册、书架、阅读记录、反馈、购章 | `novel-front/src/main/java/com/java2nb/novel/controller/UserController.java` |
| 5 | `...controller.AuthorController` | 作家作品/章节/收入接口 + `checkAuthor` 准入 | `novel-front/src/main/java/com/java2nb/novel/controller/AuthorController.java` |
| 6 | `...controller.PayController` | 支付宝下单 + 异步通知 | `novel-front/src/main/java/com/java2nb/novel/controller/PayController.java` |
| 7 | `...controller.FileController` | 图形验证码输出 + 图片上传 | `novel-front/src/main/java/com/java2nb/novel/controller/FileController.java` |
| 8 | `...controller.CacheController` | 密码保护的首页缓存刷新入口 | `novel-front/src/main/java/com/java2nb/novel/controller/CacheController.java` |
| 9 | `...controller.NewsController` / `FriendLinkController` | 新闻/友链 JSON | `novel-front/src/main/java/com/java2nb/novel/controller/NewsController.java` |
| 10 | `...core.utils.JwtTokenUtil` | HS512 生成/解析/刷新 token | `novel-front/src/main/java/com/java2nb/novel/core/utils/JwtTokenUtil.java` |
| 11 | `...core.filter.NovelFilter` | 本地图片直出 + clientId + PC/WAP 模板选择 | `novel-front/src/main/java/com/java2nb/novel/core/filter/NovelFilter.java` |
| 12 | `...core.filter.XssFilter` | XSS 过滤入口（按 urlPatterns 生效） | `novel-front/src/main/java/com/java2nb/novel/core/filter/XssFilter.java` |
| 13 | `...core.config.FilterConfig` | 注册两个 Filter 及初始化参数 | `novel-front/src/main/java/com/java2nb/novel/core/config/FilterConfig.java` |
| 14 | `...core.utils.ThreadLocalUtil` | 线程级模板目录 + clientId | `novel-front/src/main/java/com/java2nb/novel/core/utils/ThreadLocalUtil.java` |
| 15 | `...core.config.ThreadPoolConfig` / `ThreadPoolProperties` | 页面异步任务线程池 | `novel-front/src/main/java/com/java2nb/novel/core/config/ThreadPoolConfig.java` |
| 16 | `...service.impl.BookServiceImpl` | 首页设置/榜单/搜索/详情/目录/章节/评论/发布修改章节的核心业务 | `novel-front/src/main/java/com/java2nb/novel/service/impl/BookServiceImpl.java` |
| 17 | `...service.impl.UserServiceImpl` | 注册登录（MD5）、书架、阅读记录、购章、日统计查询 | `novel-front/src/main/java/com/java2nb/novel/service/impl/UserServiceImpl.java` |
| 18 | `...service.impl.AuthorServiceImpl` | 邀请码入驻、作者查询、日/月收入查询 | `novel-front/src/main/java/com/java2nb/novel/service/impl/AuthorServiceImpl.java` |
| 19 | `...service.impl.OrderServiceImpl` | 生成充值订单、回调改状态并加余额 | `novel-front/src/main/java/com/java2nb/novel/service/impl/OrderServiceImpl.java` |
| 20 | `...service.impl.SearchServiceImpl` | ES 索引 `novel` 的写入与搜索（Jest + RestHighLevelClient） | `novel-front/src/main/java/com/java2nb/novel/service/impl/SearchServiceImpl.java` |
| 21 | `...service.impl.DbBookContentServiceImpl` | `storage_type=db` 的正文读取 | `novel-front/src/main/java/com/java2nb/novel/service/impl/DbBookContentServiceImpl.java` |
| 22 | `...service.impl.FileBookContentServiceImpl` | `storage_type=txt` 从文本文件读正文 | `novel-front/src/main/java/com/java2nb/novel/service/impl/FileBookContentServiceImpl.java` |
| 23 | `...service.impl.LocalFileServiceImpl` / `OssFileServiceImpl` / `FastDfsFileServiceImpl` | 三种图片存储实现（`pic.save.storage` 条件装配） | `novel-front/src/main/java/com/java2nb/novel/service/impl/` |
| 24 | `...core.listener.BookVisitAddListener` | MQ 削峰：点击量批量落库 + ES 节流更新 | `novel-front/src/main/java/com/java2nb/novel/core/listener/BookVisitAddListener.java` |
| 25 | `...core.schedule.BookToEsSchedule` | 每分钟增量把书导入 ES | `novel-front/src/main/java/com/java2nb/novel/core/schedule/BookToEsSchedule.java` |
| 26 | `...core.schedule.DailyIncomeStaSchedule` | 每日 0 点统计作家日收入 | `novel-front/src/main/java/com/java2nb/novel/core/schedule/DailyIncomeStaSchedule.java` |
| 27 | `...core.schedule.MonthIncomeStaSchedule` | 每月 1 日 2 点统计月收入（分佣/税） | `novel-front/src/main/java/com/java2nb/novel/core/schedule/MonthIncomeStaSchedule.java` |
| 28 | `...core.serialize.CommentUserNameSerialize` | 书评用户名脱敏序列化器 | `novel-front/src/main/java/com/java2nb/novel/core/serialize/CommentUserNameSerialize.java` |
| 29 | `...core.config.AlipayProperties` | 支付宝参数绑定（appId/私钥/公钥/回调地址） | `novel-front/src/main/java/com/java2nb/novel/core/config/AlipayProperties.java` |
| 30 | `...core.config.RabbitConfig` / `EsConfig` | MQ 交换机队列绑定 / ES 客户端 | `novel-front/src/main/java/com/java2nb/novel/core/config/RabbitConfig.java` |
| 31 | `...core.enums.ResponseStatus` | 全站错误码枚举 | `novel-common/src/main/java/com/java2nb/novel/core/enums/ResponseStatus.java` |
| 32 | `...core.cache.CacheKey` | 全部缓存 key 常量 | `novel-common/src/main/java/com/java2nb/novel/core/cache/CacheKey.java` |
| 33 | `...core.cache.impl.EhCacheServiceImpl` / `RedisServiceImpl` | 两套缓存实现（条件装配） | `novel-common/src/main/java/com/java2nb/novel/core/cache/impl/` |
| 34 | `...core.advice.PageExceptionHandler` | 仅 `com.java2nb.novel.page` 包的异常 → 404 视图 | `novel-common/src/main/java/com/java2nb/novel/core/advice/PageExceptionHandler.java` |
| 35 | `...core.utils.RandomValidateCodeUtil` | 图形验证码生成（全局单 key，TTL 5min） | `novel-common/src/main/java/com/java2nb/novel/core/utils/RandomValidateCodeUtil.java` |
| 36 | `FrontBookMapper` + `BookMapper.xml` | `searchByPage`/`addVisitCount`/`addCommentCount`/`listRecBookByCatId` 等 XML SQL | `novel-front/src/main/resources/mybatis/mapping/BookMapper.xml` |

### 数据模型速查（`doc/sql/novel_plus.sql` + 增量脚本）
`book`（点击/字数/评论数/最新章/`yesterday_buy` 昨日订阅）、`book_index`（`index_num` 唯一键 `book_id+index_num`、`is_vip`、`book_price` 由 `doc/sql/20201122.sql` 增列、`storage_type` 由 `doc/sql/20210913.sql` 增列）、`book_content` + `book_content0..9`（分表）、`book_comment`（唯一键 `book_id+create_user_id`）、`user`（`account_balance` 屋币）、`user_bookshelf` / `user_read_history`（均唯一键 `user_id+book_id`，字段 `pre_content_id` 存上次阅读章节）、`user_buy_record`（唯一键 `user_id+book_index_id`）、`order_pay`（`pay_status` 0 失败/1 成功/2 待支付）、`author`（`status` 0 正常/1 封禁）、`author_code`（邀请码）、`author_income` / `author_income_detail`、`book_setting`（首页位）、`news` / `friend_link`。
