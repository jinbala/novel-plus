# novel-plus v6.0.0 架构调研笔记：跨端接口、模块演进、与 v3.6 的差异

> 调研基线（可用 `git log -1` 复核）：
> - 上游最新 `upstream/master` = `e8daac0a`（2026-10-21 22:52，`feat(api): 提交跨端客户端相关接口`），其父提交 `537027cd` 为「v6.0.0 发布」。
> - 对照基线 `906e7762`（2022-01-17，v3.6.1 时代的合并提交）。
> - 两者之间共 **358** 个提交（`git log --oneline 906e7762..upstream/master | wc -l`）。
> - 根 `pom.xml`：`version=6.0.0`、`spring-boot-starter-parent 3.4.0`、`java.version=21`。
>
> 全文只写从代码/配置读到的事实；推断项一律标「未确认」。为避免污染工作区，本笔记未修改任何仓库文件，也未切换分支。

## 1. 跨端客户端接口

### 1.1 先说结论：没有新增 api 模块

`git ls-tree -r --name-only upstream/master | grep api` 只命中一个第三方文档文件
`templates/orange/static/wangEditor/docs/usage/05-other/08-api.md`，**v6 不存在 `novel-api` / `*-api` 之类的模块或包**。
所谓「跨端客户端接口」，实际做法是在已有 `novel-front` 的 REST 控制器上补两个 JSON 接口 + 打开 CORS + 预留 App 模板目录。

最新提交 `e8daac0a` 的完整改动只有 7 个文件（+90/−5），可 `git show e8daac0a` 复核：

| 文件 | 改动性质 |
|---|---|
| `.gitignore` | 新增 `/templates/app/`（App 端模板/产物不入库） |
| `novel-common/.../core/enums/ResponseStatus.java` | 新增错误码 `INDEX_NOT_EXISTS(5002)`、`NEWS_NOT_EXISTS(5003)` |
| `novel-front/.../controller/BookController.java` | 新增 `GET book/queryBookIndexContent/{indexId}` |
| `novel-front/.../controller/NewsController.java` | 新增 `GET news/detail/{newsId}` |
| `novel-front/.../core/config/WebMvcConfig.java` | 新增 `addCorsMappings`（供 uni-app 直连） |
| `novel-front/.../service/impl/NewsServiceImpl.java` | 新闻分页查询多查 `read_count` 字段 |
| `novel-front/src/main/resources/mybatis/mapping/FrontUserBookListMapper.xml` | 三个查询的 `create_user_name` 改为 `IFNULL(NULLIF(nick_name,''),username)` |

### 1.2 新增接口一：章节正文（阅读页的 JSON 孪生）

`novel-front/src/main/java/com/java2nb/novel/controller/BookController.java`（`@RequestMapping("book")`）：

- `GET /book/queryBookIndexContent/{indexId}`，无请求体，鉴权可选（见 1.5）。
- 实现要点：`bookService.queryBookIndex(indexId)` 外层 try/catch 兜成业务错误，查不到返回 `RestResult.fail(INDEX_NOT_EXISTS)`（code 5002）。
- 计费判断与页面端同构：`isVip==1` 且未登录 → `needBuy=true`；已登录则 `userService.queryIsBuyBookIndex(userId, indexId)` 取反。
- 返回 `data` 字段（`Map<String,Object>`，`HashMap(10)`）：`bookId`、`indexId`、`indexNum`、`indexName`、`isVip`、`bookPrice`、`preBookIndexId`、`nextBookIndexId`、`needBuy`、以及 `content`（**仅 `needBuy=false` 时才有该键**，取 `bookContentServiceMap.get(bookIndex.getStorageType()).queryBookContent(bookId,indexId)`，兼容 DB 分表与 TXT 两种内容存储）。
- 对照页面通道：`novel-front/.../controller/page/PageController.java#bookContent()` 用 `CompletableFuture` 并发查书籍/目录/正文/needBuy 后塞进 `Model` 渲染 `book/book_content`。**这条渲染链此前没有 JSON 出口**，因此 App 端不得不新增该接口。

### 1.3 新增接口二：新闻详情

`novel-front/src/main/java/com/java2nb/novel/controller/NewsController.java`（`@RequestMapping("news")`）：

- `GET /news/detail/{newsId}` → 返回整个 `News` 实体（含正文），查不到 → `NEWS_NOT_EXISTS`（5003）。
- 同提交把 `NewsServiceImpl.listByPage` 的字段列表补上 `readCount`，使列表接口能直接显示阅读量（此前页面靠模板另行取）。
- 页面通道 /news 的渲染在 `PageController#newsInfo()`（`/about/newsInfo-{newsId}.html`，返回视图 `about/news_info`）。

### 1.4 CORS：面向 uni-app 的显式放行

`novel-front/src/main/java/com/java2nb/novel/core/config/WebMvcConfig.java`，注释原文「供 uni-app 跨端客户端（H5 开发调试/独立部署）直连 REST 接口」：

```java
registry.addMapping("/**")
    .allowedOriginPatterns("*")          // 注意：patterns 而非 allowedOrigins("*")
    .allowedMethods("GET","POST","PUT","DELETE","OPTIONS")
    .allowedHeaders("*")
    .allowCredentials(true)              // 允许带 Cookie
    .maxAge(3600);
```

因为用的是 `allowedOriginPatterns`，Spring 会把任意 `Origin` 反射回响应头，配合 `allowCredentials(true)` 等于「任意站点可带凭证访问」——见第 4.3 节风险。

### 1.5 鉴权方式（前端 JWT，与后台表单登录是两套体系）

- `novel-front/.../controller/BaseController.java#getToken()`：**先取 Cookie `Authorization`，取不到再取请求头 `Authorization`**。这就是跨端的关键：浏览器页面靠 Cookie，原生/小程序客户端靠 Header。
- `novel-front/.../core/utils/JwtTokenUtil.java`：`Jwts.builder().signWith(SignatureAlgorithm.HS512, secret)`，`sub` 存 `UserDetails` 的 JSON 序列化；密钥 `${jwt.secret}`，有效期 `${jwt.expiration}=604800`（秒，即 7 天）。
- 登录/续期：`POST /user/login`（表单参数 username/password，返回 `{token}`）；`POST /user/refreshToken`（依赖 `jwtTokenUtil.canRefresh(token)`，失败返回 `NO_LOGIN=1001`）。
- 需要登录的接口手动判空并 `RestResult.fail(ResponseStatus.NO_LOGIN)`，**没有拦截器/过滤器统一鉴权**（`novel-front` 未引入 Spring Security，`pom.xml` 里也没有）。
- 注册接口额外要求图形验证码 `velCode`，用 `cacheService` 以 `RANDOM_CODE_KEY+真实IP` 校验；验证码图片出口是 `GET /file/getVerify`。**因此 App 若要走注册，必须先取验证码并回填**。

### 1.6 返回格式

- 统一 `io.github.xxyopen.model.resp.RestResult`（外部依赖 `xxy-model 1.0.0`，源码不在本仓库）：`code` / `msg` / `data`。成功码由页面 JS 反证为 **200**（`templates/green/html/user/login.html`：`if (data.code == 200)`，失败分支读 `data.msg`）。
- 业务错误码集中在 `novel-common/.../core/enums/ResponseStatus.java`：用户 1xxx、评论 3xxx、作者 4xxx、小说 5xxx（新增 5002/5003）、书单 6xxx、AI 7xxx、搜索 9001、文件 10xxx、`PASSWORD_ERROR=88001`。
- `novel-common/.../core/advice/CustomResponseBodyAdvice.java` 对**所有** `@RestController` 响应重序列化，把 `Long/long` 全部转字符串（防前端精度丢失），并注释说明它取代了 `spring.jackson.generator.write-numbers-as-strings=true`。

### 1.7 与 PC/WAP 页面接口的关系

同一批控制器同时服务两条通道：**`.html` 路由做服务端渲染，JSON 路由供页面 JS 与 App**。

- 页面也直接调这些 JSON 接口：`templates/green/html/user/login.html` 里 `$.post('/user/login', …)` 成功后 `$.cookie('Authorization', data.data.token, {expires:7})`；`book_detail.html`/`book_content.html`/`book_comment.html` 调 `listCommentByPage`、`addVisitCount`、`book/queryBookIndexAbout` 等（`git grep -l "listCommentByPage" upstream/master -- templates/green`）。
- 因此「跨端新增」只有两处真正的新能力：**章节正文 JSON**、**新闻详情 JSON**；其余阅读链路 App 直接复用既有接口。

从代码可确认的「App 主链路」候选（均为 JSON、无 `.html` 依赖）：

| 环节 | 接口 | 说明 |
|---|---|---|
| 首页配置/榜单 | `GET /book/listBookSetting`、`/book/listClickRank`、`/book/listNewRank`、`/book/listUpdateRank`、`/book/listRank?type&limit` | 均返回 `List` |
| 分类/检索 | `GET /book/listBookCategory`、`/book/searchByPage`（`BookSpVO`+`curr/limit`，返回 `PageBean`） | 检索已改为 SQL 查询（见 2.5） |
| 详情/目录 | `GET /book/queryBookDetail/{id}`、`/book/queryIndexList?bookId&curr&limit`、`/book/queryNewIndexList?bookId` | |
| 阅读 | `GET /book/queryBookIndexAbout?bookId&lastBookIndexId`（章节总数 + 上章开头 42 字）、`GET /book/queryBookIndexContent/{indexId}` | 后者本次新增 |
| 互动 | `GET /book/listCommentByPage`、`listCommentReplyByPage`、`listParagraphCommentCounts`、`listParagraphComment`；`POST /book/addBookComment`、`addParagraphComment`、`addCommentReply`、`toggleCommentLike/UnLike`、`toggleReplyLike/UnLike` | 段评接口另需 `bookIndexId` |
| 用户 | `POST /user/login`、`/user/register`、`/user/refreshToken`、`GET /user/userInfo`、`/user/listBookShelfByPage`、`/user/listReadHistoryByPage`、`POST /user/addToBookShelf`、`/user/addReadHistory`、`/user/buyBookIndex` | |
| 书单 | `GET /bookList/plaza`、`/bookList/mine`、`/bookList/detail?listId`；`POST /bookList/create`、`/bookList/update`、`/bookList/addBook`、`/bookList/removeBook` | 书单是 v6 新增业务 |
| 消息 | `GET /user/message/listByPage`、`/user/message/unreadCount`；`POST /user/message/read`、`/user/message/readAll` | v6 新增 |
| 新闻/其它 | `GET /news/listIndexNews`、`/news/listByPage`、`/news/detail/{newsId}`、`/friendLink/listIndexLink` | |

### 1.8 本节「未确认」项

- 客户端工程本体（uni-app 项目）不在本仓库，仅在 `WebMvcConfig` 注释里出现；仓库内没有任何 `.vue`/`manifest.json`，`templates/app/` 被 `.gitignore` 忽略但目录不存在。
- App 是「H5 套壳」还是「原生直连 + Header 传 token」：`BaseController` 两种都支持，具体取舍未确认。
- 是否另有网关/统一前缀（如 `/api`）：`application.yml` 无 `server.servlet.context-path`，接口就是 `http://host:8083/book/...` 形态。

## 2. 模块与包结构变化

### 2.1 顶层对比

| 项 | v3.6（906e7762） | v6（e8daac0a） |
|---|---|---|
| 根版本 | `3.6.1` | `6.0.0` |
| Spring Boot | `2.1.8.RELEASE` | `3.4.0` |
| Java | `1.8` | `21`（Servlet 6 / `jakarta.*`） |
| 模块 | common / front / crawl / admin | 同上（模块数未变） |
| 顶层目录 | `assets/ doc/ novel-* pom.xml templates/` | `config/ doc/ novel-* pom.xml templates/ .github/`，`assets/` 整目录删除 |
| 文件数 | 3398 | 3098 |

### 2.2 v6 各模块目录树（3 层，`git ls-tree` 实取）

```
novel-common/src/main/
├── java/com/java2nb/novel/core/{advice,cache,config,converter,enums,utils}
├── java/com/java2nb/novel/{entity,mapper}
└── resources/{application-common*.yml, mybatis/generatorConfig.xml, banner.txt}
novel-front/src/main/
├── java/com/java2nb/novel/controller/{page/}
├── java/com/java2nb/novel/core/{ai,bean,config,filter,listener,schedule,serialize,utils,wrapper}
├── java/com/java2nb/novel/{mapper,service,service/impl,vo}
├── resources/{application*.yml, mybatis/mapping, prompts/ai-assistant, static, templates}
└── build/{config,docker,scripts}   # application.yml、shardingsphere-jdbc.yml、Dockerfile、novel-front.sh/.bat
novel-crawl/src/main/java/com/java2nb/novel/
├── controller/{page/}
├── core/{bean,crawl,config,listener,schedule}
└── {mapper,service,service/impl,utils,vo} + resources/{application*.yml, mybatis/mapping}
novel-admin/src/main/
├── java/com/java2nb/novel/{controller,controller/page,core/config,core/utils,mapper,service,vo}
└── resources/{application*.yml, mybatis/mapping, templates/{admin,author,book,bookList,comment,member,message,news,order,website}, static}
```

### 2.3 体量变化（`git ls-tree` 计数）

| 模块 | v3.6 文件 / java | v6 文件 / java | 观察 |
|---|---|---|---|
| novel-common | 89 / 82 | 108 / 101 | 实体与 Mapper 扩张（AI、书单、段评、消息、新闻分类） |
| novel-front | 649 / 76 | 778 / 108 | 新增 AI、段评、书单、消息、定时任务 |
| novel-crawl | 170 / 24 | 181 / 29 | 新增磁盘监控、邮件、HttpClient |
| novel-admin | 1270 / 158 | **224 / 43** | 重写瘦身，-29 万行（`git show --stat 4787f113`：1557 files，+14859/−292583） |
| templates | 1138 | 1770 | 新增 green 主题 + 2026 新 UI |

### 2.4 结构性迁移（可逐条 `git diff --name-status 906e7762 upstream/master` 验证）

1. `page/PageController` 归位到 `controller/page/PageController`（front / crawl / admin 三处都改了，见各模块目录树）；admin 与 crawl 的 `PageController` 同一处理。
2. `novel-front` 新增 `core/ai/{AiJsonUtil,ChapterTextCheckUtil,PromptTemplateUtil}` + `resources/prompts/ai-assistant/*.txt`（7 个提示词模板：书名、章节规划、章节正文、检查、修订、摘要、创作方案）。
3. `novel-common` 新增实体：`AiAuthorPref/AiChapterPlan/AiCreationPlan/AiCreationTask`、`BookCommentReply`、`BookParagraphComment`、`NewsCategory`、`UserBookList/UserBookListItem`、`UserMessage`（对应 `doc/sql/20261019.sql`、`20261020.sql` 建表语句）。
4. 缓存与基础设施收敛：v3.6 有 `core/cache/impl/EhCacheServiceImpl`，v6 只剩 `RedisServiceImpl`（提交「refactor: 移除 Ehcache，默认缓存设置为 Redis」）；异常/响应链重构为 `PageExceptionHandler` → `core/advice/CommonExceptionHandler`，新增 `CustomResponseBodyAdvice`，`RestTemplateUtil` → `RestTemplates`，并新增 `SpringUtil`、`HttpProxyProperties`、`NameMaskUtil`、`IpLocationConfig`（+`resources/ip2region.xdb`，v3.6 无该文件）。
5. 配置外置：v3.6 无顶层 `config/`；v6 新增 `config/shardingsphere-jdbc.yml`（ShardingSphere 5.5.1 Standalone + JDBC 元数据仓，`book_content` 按 `index_id % 10` 分 10 表），并由 `application-common.yml` 的 `jdbc:shardingsphere:absolutepath:${user.dir}/config/shardingsphere-jdbc.yml` 加载；同时 `novel-front/src/main/build/config/shardingsphere-jdbc.yml` 作为发行包副本。
6. 三方依赖增减（`pom.xml`）：out — `jest 6.3.1`/ES、`spring-boot-starter-amqp`、`fastdfs-client`、`ehcache`、`shiro`、`druid`；in — `spring-ai-bom 1.0.0` + `spring-ai-starter-model-openai`、`shardingsphere-jdbc 5.5.1`、`ip2region 2.7.0`、`sensitive-word 0.29.5`、`snakeyaml 2.2`（根 pom 仍保留 `jest.version` 属性，属残留，实际无引用）。

## 3. 模板系统

### 3.1 `templates` 仍然独立在仓库顶层

v6 顶层依旧有 `templates/`（与 maven 模块同级，不在 jar 内）。四个主题：`blue`、`dark`、`green`、`orange`，**v6 新增 `green`**（提交「feat(templates): 新增绿色主题模版，并设置为默认模版」），并在 `application-prod.yml` 里 `templates.name: green`（v3.6 为 `orange`）。

主题完整度并不齐（`git ls-tree -d upstream/master:templates/<t>/html`）：

| 主题 | html 子目录 | 文件数 |
|---|---|---|
| blue | 仅 `common` | 174 |
| dark | `book, common, mobile, user` | 412 |
| orange | `about, author, book, common, mobile, pay, user` | 555 |
| green | `about, author, book, common, mobile, pay, user` | 631 |

即：**blue/dark 是历史遗留的不完整主题**，可切换但页面会缺失（未确认是否在文档中被声明为废弃）。

### 3.2 模板与静态资源的位置 / 构建期复制

`novel-front/pom.xml` 的 `maven-antrun-plugin`（package 阶段）是模板分发的关键，可确认的复制关系：

- `novel-front/src/main/resources/templates/**` → `../templates/green/html/`
- `novel-front/src/main/resources/static/**` → `../templates/green/static/`
- `../templates/**` → `target/build/templates/`（发行包内），再与 `target/build/config`、`build/bin/*.sh|bat`、`Dockerfile` 一起打 `novel-front.zip`。也就是说：**`novel-front/src/main/resources/templates` 是 green 主题的「源」**（69 个文件），构建时被覆盖写进 `templates/green/html`（631 个文件，含 layui 等静态资源）。

### 3.3 运行期取模板：dev 用 classpath，prod 用外置目录

- prod（`novel-front/src/main/resources/application-prod.yml`）：`spring.thymeleaf.prefix=file:${user.dir}/templates/${templates.name}/html/`（`suffix=.html`）+ `spring.web.resources.static-locations=file:${user.dir}/templates/${templates.name}/static/`。
- `application-dev.yml` 只覆盖 jwt 与线程池，**没有 thymeleaf/static-locations 配置** → 走 Boot 默认 classpath（`classpath:/templates/`、`/static`），即改 `resources/templates` 立即生效（`application-common.yml` 里 `thymeleaf.cache=false` 配合）。
- 与 v3.6 的差异：v3.6 用 `spring.resources.static-locations`（Boot 2 键名），v6 改为 `spring.web.resources.static-locations`（Boot 3 键名）——**升级 Boot 3 必须同步迁移的配置点**，漏改静态资源 404。
- 该键还被业务代码读取：`novel-front/.../core/schedule/SitemapGenSchedule.java` 注入 `${spring.web.resources.static-locations}`，把 `sitemap.xml` 写到外置静态目录根（`@Profile("prod")`）。

### 3.4 移动端模板怎么组织的

- **同主题下用 `mobile/` 子目录**：`templates/green/html/mobile/{index.html, book/, booklist/, common/, pay/, user/}`，静态资源在 `templates/green/static/mobile/{js,layui}`。不存在独立的 wap 主题目录。
- 视图名拼前缀：`PageController` 每个方法返回 `ThreadLocalUtil.getTemplateDir() + "xxx"`。
- 前缀来源：`novel-front/.../core/filter/NovelFilter.java` —— 先按 cookie `userClientMarkKey`（UUID）取 Redis 里的 `TEMPLATE_DIR_KEY+clientId`（写入 TTL 24h），命中即用；未命中时看 `?to=pc|mobile` 强制写入 `""` 或 `"mobile/"`，否则用 `BrowserUtil.isMobile(req)` 现场判定。
- 未确认：green 主题**没有桌面端 `booklist/` 模板**（`PageController#bookListPlaza/Mine/Detail` 返回 `booklist/plaza|mine|detail`），仓库内只有 `mobile/booklist/*`；PC 访问书单广场会命中不存在的视图（是否由外部模板包补发，未确认）。

### 3.5 `templates/app/`

`.gitignore` 新增 `/templates/app/`，而仓库中该目录不存在 → 结论：**为 App 端模板/产物预留的外置目录，内容不随开源仓库分发**（内容与用途未确认）。

## 4. 安全变化

### 4.1 JWT_SECRET 强制（prod 启动即校验）

三处证据互相印证：

1. `novel-front/.../core/config/JwtSecretValidator.java`：`@Component @Profile("prod") implements ApplicationRunner`，读环境变量 `JWT_SECRET`，空白则 `log.error(...)` 后 `throw new IllegalStateException("Missing required environment variable: JWT_SECRET")` —— 应用启动失败，不是降级。
2. `application.yml`：`jwt.secret: ${JWT_SECRET:}`（默认为空）；`application-dev.yml`：`jwt.secret: ${JWT_SECRET:novel!#20191230}` 并注释「Development only; production requires an explicit JWT_SECRET」。
3. `README.md`「前台 JWT 签名密钥」章节：给出 `export JWT_SECRET="$(openssl rand -base64 64 | tr -d '\n')"`，说明更换密钥会使旧 token 全失效。
   对应提交：`Require an external JWT signing secret` + `Validate production JWT secret and isolate development fallback`（2026-10-18 合并 PR #138）。

### 4.2 后台鉴权：Shiro 已彻底移除，改用 Spring Security 内存单管理员

- 全仓库 `shiro` 命中数：v3.6 有 8 个文件（`novel-admin/.../common/config/ShiroConfig.java`、`system/shiro/UserRealm.java`、`common/redis/shiro/{RedisCache,RedisCacheManager,RedisManager,RedisSessionDAO,SerializeUtils}.java`、`common/utils/ShiroUtils.java`）；**v6 为 0**。
- v6 只有两份 `SecurityConfiguration`：`novel-admin/.../core/config/SecurityConfiguration.java` 与 `novel-crawl/.../core/config/SecurityConfiguration.java`（内容同构），要点：
  - `InMemoryUserDetailsManager` 单个用户，用户名/密码取 `${admin.username}` / `${admin.password}`（`novel-admin/src/main/resources/application.yml` 里默认 `admin/admin`；crawl 的 `application.yml` 同一组键，默认也是 `admin/admin`）。
  - `BCryptPasswordEncoder`，`User.builder().roles("ADMIN")`。
  - `csrf(csrf -> csrf.disable())`；`requestMatchers("/css/**","/favicon.ico").permitAll()`，`anyRequest().hasRole("ADMIN")`。
  - `formLogin().loginPage("/login.html").loginProcessingUrl("/login")` + `logout().logoutUrl("/logout")` + `httpBasic()`。
  - 会话：`server.servlet.session.timeout: 1D`，端口 80（admin）/ 8081（crawl）。
- 对比 v3.6：admin 是「bootdo 风格脚手架 + Shiro + Redis 分布式 Session + 菜单/角色/字典/日志/代码生成器」；`refactor: 重构管理后台`（4787f113）把 `common/*`、`system/*` 整个删掉（含 `ShiroConfig`、`DictController`、`GeneratorController`、`LogController`、`LogAspect` 等）。**结论：v6 后台从 RBAC 多用户降级为单管理员内置账号**——面试可讲「以运维简单换掉了一套通用权限体系」。

### 4.3 安全风险/技术债（均可定位）

- 后台默认口令 `admin/admin` 写在仓库配置里（`novel-admin/src/main/resources/application.yml`、`novel-crawl/src/main/resources/application.yml`），且 `csrf` 全局关闭并启用 `httpBasic`。
- 前台 CORS `allowedOriginPatterns("*") + allowCredentials(true)`（`WebMvcConfig`）：任意站点可发起带 Cookie 的跨域请求，而前台鉴权恰恰依赖 Cookie `Authorization` → 等价于放弃同源保护。若只为 App 服务，应限制白名单或改为仅 Header 传 token。
- AI 密钥明文入库：`novel-front/src/main/resources/application.yml` 的 `spring.ai.openai.api-key`（siliconflow）为字面量。
- XSS 过滤是「白名单式」：`xss.urlPatterns` 逐条列举需要过滤的 POST 接口（含新增的 `/author/aiAssistant/*`、`/bookList/*`、`/book/addParagraphComment`），**漏列即不过滤**——新增接口必须同步维护该列表，属易漏点。
- 未确认：`JwtSecretValidator` 只校验 front；admin/crawl 不依赖 JWT，故无同类校验。

### 4.4 内容安全（新增能力）

`novel-front` 引入 `com.github.houbb:sensitive-word 0.29.5`，在写库前替换敏感词：`BookServiceImpl#addBookComment/addCommentReply`、`BookParagraphCommentServiceImpl`、`UserBookListServiceImpl`（书单名、推荐语）均调用 `SensitiveWordHelper.replace(...)`。

## 5. 定时任务与异步

### 5.1 v6 全量 schedule（`git grep -n "@Scheduled" upstream/master`）

| 类 | 触发 | 条件/Profile | 作用 |
|---|---|---|---|
| `novel-front/.../core/schedule/CrawlPicTransSchedule` | `fixedRate = 10min` | `pic.save.type=2` | 把爬取的外链图片转存本地/OSS（每轮 100 本） |
| `novel-front/.../core/schedule/DailyIncomeStaSchedule` | `cron = "0 0 0 * * ?"` | 无 | 统计作者昨日收入 |
| `novel-front/.../core/schedule/MonthIncomeStaSchedule` | `cron = "0 0 2 1 * ?"` | 无 | 每月 1 日 2 点统计作者月收入 |
| `novel-front/.../core/schedule/SitemapGenSchedule` | `cron = "0 0 2 * * ?"` | `@Profile("prod")` | 生成/更新 `sitemap.xml` 到外置静态目录 |
| `novel-crawl/.../core/schedule/DiskMonitorSchedule` | `fixedDelayString = "#{1000*60*${disk-monitor.interval-minutes}}"` | `disk-monitor.enabled=true` | 磁盘占用检查，超阈值邮件告警 + 采集熔断 |

### 5.2 与 v3.6 的差异

| v3.6 | v6 | 说明 |
|---|---|---|
| `BookToEsSchedule`（front） | **删除** | ES 全链路移除，随之删除 `core/config/EsConfig`、`service/SearchService`、`SearchServiceImpl`、`core/listener/BookVisitAddListener`（MQ 消费）、`core/config/RabbitConfig` |
| — | `SitemapGenSchedule`（front，新增） | SEO 站点地图（2026-10-10 提交） |
| `CrawlThreadMonitor`（crawl） | **删除** | 改为按需查询 `GET /crawl/getTaskProgress/{id}`（`CrawlController`），不再靠常驻监控线程 |
| — | `DiskMonitorSchedule` + `DiskMonitorProperties` + `DiskInfo` + `EmailService`（crawl，新增） | 磁盘保护/邮件告警/自动熔断（2025-10-24） |

新增的 `DiskMonitorProperties` 字段可确认设计意图：`enabled / intervalMinutes / warningThreshold / severeThreshold / criticalThreshold / recipients`，用 `AtomicBoolean criticalAlertSent` 去重告警，即「分级阈值 + 临界只告警一次 + 触发熔断」。

### 5.3 调度/异步基础设施

- `novel-front/.../FrontNovelApplication.java`：`@EnableScheduling`、`@EnableCaching`、`@EnableTransactionManagement`、`@ServletComponentScan`、`@MapperScan("com.java2nb.novel.mapper")`，并显式声明 `TaskScheduler`（`ThreadPoolTaskScheduler`，poolSize=5，注释「解决同一时间只能一个定时任务执行的问题」）。
- 业务线程池 `novel-front/.../core/config/ThreadPoolConfig.java`：
  - `threadPoolExecutor`：参数来自 `thread.pool.*`（dev 10/20/10s/queue 100，prod queue 1000），拒绝策略 `AbortPolicy`。
  - `aiTaskExecutor`：固定 `1~2` 线程、queue 30、`AbortPolicy`，注释「长耗时模型调用与页面渲染线程隔离，避免阻塞前台页面加载」；`AiAssistantServiceImpl` 用 `aiTaskExecutor.execute(() -> runTask(taskId))` 异步跑生成任务，前端用 `GET /author/aiAssistant/progress?planId=`、`GET /author/aiAssistant/task/{taskId}` 轮询。
- 页面渲染并行化：`PageController#index/bookDetail/bookContent` 用 `CompletableFuture.supplyAsync(..., threadPoolExecutor)` 并发装配数据（书籍、目录、正文、needBuy 四条链）。未确认：定时任务无分布式锁（未见 ShedLock/Redisson 锁调用），多实例部署会重复执行。

## 6. 给面试官讲「从 v3.6 到 v6 做了什么」的 10 条

1. **（架构）运行时底座整体换代**：`pom.xml` 从 Boot 2.1.8 + Java 8 升到 Boot 3.4.0 + Java 21，`javax.*`→`jakarta.*`，`spring.resources.*`→`spring.web.resources.*`，模板/静态资源外置路径沿用 `${user.dir}/templates/${templates.name}/`。一次升级换来 Spring AI、仍在维护的依赖树。
2. **（架构）「去中间件化」的收敛**：提交「refactor: 移除 RabbitMQ 和 Elasticsearch 相关功能」「移除 Ehcache，默认缓存设置为 Redis」「移除 FastDFS 模块」——运行期依赖从 MySQL+Redis+RabbitMQ+ES+FastDFS 收敛到 **MySQL（ShardingSphere 分表）+ Redis**，`novel-common` 只留 `RedisServiceImpl`，检索改走 `bookMapper.searchByPage`。典型的「运维成本优先」取舍。
3. **（架构）后台重写**：`refactor: 重构管理后台`（4787f113）把 Shiro + RBAC 脚手架（1.27k 文件 / 158 java）删成 224 文件 / 43 java，鉴权换成 Spring Security `InMemoryUserDetailsManager` + BCrypt + 单管理员，页面收敛到 12 个 Controller（`book/member/website/stat/bookList/comment/message/news/order/author/file`）。净删约 29 万行。
4. **（架构）接口双通道 + 跨端**：页面 `.html` 服务端渲染与 JSON 接口共用同一批 Service；v6 补齐「正文/新闻详情」两个 JSON 出口（`/book/queryBookIndexContent/{indexId}`、`/news/detail/{newsId}`），加 CORS 与 `templates/app/` 预留，App/uni-app 复用读者端接口与 JWT（Cookie 或 Header 二选一，`BaseController#getToken`）。
5. **（功能）AI 能力闭环**：Spring AI 1.0.0（`spring-ai-starter-model-openai`）+ 7 个外置提示词模板（`resources/prompts/ai-assistant/`）+ 完整任务模型（`ai_creation_plan` 四阶段 `stage`、`ai_creation_task`、`ai_chapter_plan`、`ai_author_pref`），覆盖创作问答→方案→章节规划→正文生成/检查/修订，另有扩写/缩写/续写/润色 SSE 流式接口（`author/ai/stream/*`）和 AI 生成封面（`OpenAiImageModel`）。
6. **（功能）移动端（WAP）整体重做 + 社交化**：2026-10 集中提交「重新设计移动端 UI」「新增书单广场」「新增小说段落评论」「新增消息系统」，配套 `user_book_list(_item)`、`book_paragraph_comment`、`user_message` 建表（`doc/sql/20261019.sql`、`20261020.sql`），消息类型区分「书评被回复/段评被回复」并带跳转定位字段。
7. **（功能）互动与运营**：评论点赞/点踩与回复、敏感词替换、IP 地理位置显示（`ip2region` + `IpLocationService`）、首页统计图表（`stat/trend`）、会员注册自动生成昵称、作品完结、书单运营位。
8. **（功能）SEO 与内容分发**：`SitemapGenSchedule` 定时把 `sitemap.xml` 写到外置静态根（依赖 `spring.web.resources.static-locations`），属「非功能性需求也能落到代码」的例子。
9. **（工程化）爬虫工程化**：磁盘保护（分级阈值 + 邮件告警 + 自动熔断）、HTTP 代理（含用户名密码，`HttpProxyProperties`）、动态 UA、非 UTF-8 站点采集、采集规则在线编辑与测试、单本采集进度、`CrawlHttpClient` 统一请求层。
10. **（工程化）交付自动化与配置安全**：`.github/workflows/release.yml`（push `v*` tag → JDK 21 + `mvn -Pcentral-repo` → 自动建 Release 上传 zip）、`src/main/build/{docker,scripts}` 提供 Dockerfile 与 `.sh/.bat` 一键脚本、Windows 生产启动脚本；同时把 JWT 密钥从「写死在 yml」改为 `JWT_SECRET` 环境变量并在 prod 启动时强校验（`JwtSecretValidator`）。

## 7. 复现与核对命令

```powershell
cd C:\Users\Chen\Documents\deepseek-harness\default-workspace
git show --stat --no-renames e8daac0a                        # 跨端提交的 7 个文件
git show upstream/master:novel-front/src/main/java/com/java2nb/novel/controller/BookController.java
git show upstream/master:novel-front/src/main/java/com/java2nb/novel/core/config/WebMvcConfig.java
git show upstream/master:novel-front/src/main/resources/application-prod.yml
git show upstream/master:novel-admin/src/main/java/com/java2nb/novel/core/config/SecurityConfiguration.java
git ls-tree -r --name-only upstream/master | Select-String 'shiro'   # v6 无输出
git ls-tree -r --name-only 906e7762 | Select-String 'shiro'          # v3.6 有 8 个文件
git grep -n '@Scheduled' upstream/master -- novel-front novel-crawl
git diff --no-renames --stat 906e7762 upstream/master -- templates novel-admin
```

### 待补（本次未确认）

1. `templates/app/` 的实际内容与 App 模板渲染方式（仓库内无文件）。
2. PC 端书单页模板缺失（green 无桌面 `booklist/`）是有意只做移动端，还是待补。
3. 定时任务在多实例部署下的幂等性（未见分布式锁）。
4. 客户端工程（uni-app）的请求封装、token 刷新与验证码处理策略。
