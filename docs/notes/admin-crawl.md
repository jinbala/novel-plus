# novel-plus v3.6 平台后台（novel-admin）+ 爬虫（novel-crawl）调研笔记

> 依据：本仓库实际代码（父 pom 版本 3.6.1），未参考线上新版本文档。所有结论均可回溯到下面的相对路径。
> 标注「未确认」处表示仅看到字段/配置、未在代码中找到完整闭环。

**先给结论（面试最容易踩坑的 5 点）**

1. `novel-admin` 里 7 个业务 Controller（Book/Category/Author/AuthorCode/News/User/Pay）**全部是代码生成器产物**：`/list` 分页 + `/add|/edit|/detail` 页面 + `/save|/update|/remove|/batchRemove`，没有审核动作、没有业务校验、Service 层**没有事务**。
2. `CategoryController` 管的是 **`news_category`（新闻类别）**，不是小说分类 `book_category`；小说分类（7 条）在后台**无维护入口**。而且初始化 SQL 只给「作家管理」「新闻管理」建了菜单，`novel/book`、`novel/user`、`novel/pay`、`novel/stat` **没有 `sys_menu` 记录**，需手工插菜单才能在后台点开。
3. 「作品审核/上架」在后台**不存在独立流程**：只有 `book.status`（0 入库 / 1 上架）字段，靠通用 `/novel/book/update` 改；`book` 表无 audit 字段。
4. 数据权限（`sys_data_perm`）靠一个 **MyBatis 拦截器改写 SQL 字符串**实现，且只对方法名以 `ByPerm` 结尾的语句生效——全仓库只有 `sys_user` 的 `listByPerm/countByPerm` 命中，业务表（book/order_pay）**未接入**。
5. 爬虫**只用正则**（无 jsoup/xpath），规则以 JSON 存 `crawl_source.crawl_rule`；调度不是 Quartz，而是 `ServletContextListener` 里自建 `Thread` + `sleep`，加一个 5 分钟的 `@Scheduled` 做状态回收。

---

## 1. 后台登录与权限

### 1.1 登录链路（`novel-admin`）

- 入口：`novel-admin/src/main/java/com/java2nb/system/controller/LoginController.java`
  - `GET /login`：把 `java2nb.username/password`（`JnConfig`）塞进 model，登录页**预填账号密码**（dev 配置 `admin/111111`，见 `novel-admin/src/main/resources/application-dev.yml:1-4`）。
  - `POST /login`（ajax）：**必须验证码**。先取 session 中的 `RandomValidateCodeUtil.RANDOMCODEKEY` 比对 `verify`（`LoginController.java:74-86`，空/不等/取不到都直接返回错误），再 `password = MD5Utils.encrypt(username, password)`，用 `UsernamePasswordToken` 走 `subject.login(token)`。
  - `GET /getVerify`：输出验证码图片，`ShiroConfig` 里被设为 `anon`。
  - `GET /logout`：`ShiroUtils.logout()` → 重定向 `/login`；`GET /index`：`menuService.listMenuTree(userId)` + 头像文件，渲染 `index`。
  - 认证失败只捕获 `AuthenticationException`，所以「用户不存在」这类路径（`UserRealm` 里 `.get(0)` 会抛 `IndexOutOfBoundsException`）不会被这一层吞掉，落到全局异常处理返回 500（代码事实，实际表现未跑）。
- 密码算法：`novel-admin/src/main/java/com/java2nb/common/utils/MD5Utils.java`
  - `SimpleHash("md5", pwd, ByteSource(username + "1qazxsw2"), 2)`，即 **MD5 + 用户名&固定盐 + 2 次迭代**，输出 32 位 hex。**不是 BCrypt**（BCrypt 只出现在 `novel-crawl` 的 Spring Security 内存用户）。库中 `admin` 的密码为 `d633268afedf209e1e4ea0f5f43228a8`（`doc/sql/novel_plus.sql:1444`）。
  - 改密/重置密码同样走该工具（`SysUserServiceImpl.java:136-159`，重置时会拒绝 `admin` 账号）。

### 1.2 会话 / token（Shiro，无 JWT）

- 配置：`novel-admin/src/main/java/com/java2nb/common/config/ShiroConfig.java`
  - 过滤链：`/login`、`/getVerify`、`/css|js|fonts|img|docs|layuimini|upload|files/**` → `anon`；`/logout` → `logout`；`/**` → `authc`；`loginUrl=/login`，`unauthorizedUrl=/403`。
  - `sessionManager`：`DefaultWebSessionManager`，`globalSessionTimeout = server.session-timeout(18000) * 1000`（≈5 小时）。
  - SessionDAO：`spring.cache.type == "redis"` 时用 `RedisSessionDAO`（`RedisManager` 缓存过期 1800s），否则 `MemorySessionDAO`+EhCache（**默认 ehcache，重启即掉登录**，`application.yml:27-30`）。
  - 注册 `ShiroDialect`（Thymeleaf 标签可用，见 1.4）、`AuthorizationAttributeSourceAdvisor`（开 `@RequiresPermissions` AOP）。
- 认证/授权装配：`novel-admin/src/main/java/com/java2nb/system/shiro/UserRealm.java`
  - `doGetAuthenticationInfo`：查 `sys_user` → 明文比对已加密串 → `status==0` 抛 `LockedAccountException`；成功后把 **下级部门 id 串 `supDeptIds`** 和 **数据权限 `Map<tableName, List<DataPermDO>>`** 塞进 principal（`UserDO`），供拦截器用。
  - `doGetAuthorizationInfo`：`menuService.listPerms(userId)` → `SimpleAuthorizationInfo.setStringPermissions`。
  - Realm 不是 Spring Bean 注入，而是通过 `ApplicationContextRegister.getBean(...)` 手动取 DAO。

### 1.3 RBAC 表结构与关系（`doc/sql/novel_plus.sql`）

| 表 | 关键列 | 说明 |
|---|---|---|
| `sys_user` | `user_id` `username` `password` `dept_id` `status(0禁用/1正常)` `pic_id` | 行 1418-1439 |
| `sys_role` | `role_id` `role_name` `role_sign` `remark` | 行 982-991 |
| `sys_menu` | `menu_id` `parent_id` `name` `url` `perms` `type(0目录/1菜单/2按钮)` `icon` `order_num` | 行 895-907 |
| `sys_user_role` | `user_id` `role_id` | 用户↔角色多对多 |
| `sys_role_menu` | `role_id` `menu_id` | 角色↔菜单多对多（≈4900 行数据） |
| `sys_dept` | `dept_id` `parent_id` `name` `order_num` `del_flag` | 部门树 |
| `sys_data_perm` | `table_name` `module_name` `crl_attr_name` `crl_column_name` `perm_code` | 行 454-466；`perm_code` 前缀 `all_/sup_/own_` |
| `sys_role_data_perm` | `role_id` `perm_id` | 角色↔数据权限多对多 |

关系：`sys_user --sys_user_role--> sys_role --sys_role_menu--> sys_menu`；`sys_role --sys_role_data_perm--> sys_data_perm`；`sys_user.dept_id → sys_dept.dept_id`（数据权限的锚点）。

### 1.4 菜单权限 vs 按钮权限

- 菜单：`novel-admin/src/main/resources/mybatis/system/MenuMapper.xml:113-126` `listMenuByUserId`（三表 join，`m.type in (0,1)`）→ `MenuServiceImpl.listMenuTree` 用 `BuildTree.buildList(trees,"0")` 建树 → `index.html` 左侧菜单。
- 按钮权限：`@RequiresPermissions("novel:book:add")` 这种注解遍布 Controller（全仓库 132 处，见 `grep @RequiresPermissions`）；`sys_menu` 中 `type=2` 的行就是按钮（如 223-227 行 `novel:author:detail/add/edit/remove/batchRemove`）。权限集合来自 `listUserPerms`（`MenuMapper.xml:128-135`），`MenuServiceImpl.listPerms` 会按逗号拆分多条 `perms`。
- 校验入口就是 Shiro 的 `AuthorizationAttributeSourceAdvisor` AOP，异常统一由 `CommonExceptionHandler.handleAuthorizationException` 处理（ajax 返回 `R.error(403,"未授权")`，页面跳 `error/403`）。Thymeleaf 端可用 `shiro:hasPermission`（`ShiroDialect` 已注册），**具体页面是否使用未逐个确认**。

### 1.5 数据权限 DataPerm 怎么生效

- 装配：`UserRealm.java:69-85` → `DataPermDao.selectDataPermsByUserId`（`system/DataPermMapper.xml:142-149`，`sys_data_perm ⋈ sys_role_data_perm ⋈ sys_user_role`，按 `table_name` 分组）。
- 生效：`novel-admin/src/main/java/com/java2nb/common/interceptor/DataPermInterceptor.java`（`@Intercepts` 拦截 `Executor.query` 两个签名）
  1. 取 `MappedStatement.getId()` 的方法名，**只有 `endsWith("ByPerm")` 才处理**；
  2. 用正则 `\s+from\s+([^\s]+)\s*` 抓第一个表名（遇到无 `_` 的 token 时继续找下一个，用于跳过派生表别名）；
  3. 把 ` order ...`、` limit ...` 从 SQL 尾部剥掉；
  4. 按 `perm_code` 前缀拼：`all` → 放弃过滤；`own` → 反射 `UserDO` 上 `crl_attr_name` 属性的值，拼 `or 列=值`；`sup` → 反射 `sup + Attr + "s"`（即 `supDeptIds`，来自 `DeptDao.getDeptIdsByParentId`），拼 `or 列 in (串)`；
  5. 首个别 `or` 去掉，包成 `Where (…)` 追加，再补回 order/limit，**反射写回 `BoundSql.sql`** 后重新 `executor.query`。
- 命中面：只有 `system/UserMapper.xml` 的 `listByPerm`/`countByPerm`。它被刻意写成 `select ... from ( select ... from sys_user <where> ... ) t` 派生表，就是为了让末尾追加的 `WHERE` 落在别名为 `t` 的派生表上（外层 select 也把 `dept_id` 暴露出来）。`SysUserServiceImpl.list` 会先把部门条件下的子部门 id 展开成 `deptIds` 再调 `listByPerm`。**小说/订单等业务表没有任何 `ByPerm` 语句，数据权限对它们不生效**。

### 1.6 后台菜单实际构成（`sys_menu`）与入口缺口

初始化 SQL 里只有六个与业务相关的一级/二级入口：系统管理（`sys:user:*`/`sys:role:*`/`system:sysDept:*`/`system:dataPerm:*`）、基础管理（`common:sysFile:sysFile`、`common:dict:*`）、研发工具（`common:generator`，行 48）、系统监控（`common:log` 行 27、运行监控、在线用户）、作家管理 221（作者列表 222、邀请码 228，行 964-976）、新闻管理 234（类别 235、新闻列表 241，行 1808-1820）。
**缺口**：`novel:book:*`、`novel:user:*`、`novel:pay:*`、`novel:stat` 在全部 `doc/sql/*.sql` 中都查不到对应的 `sys_menu` 行 → `Book/User/Pay/StatController` 初始化后**在后台菜单里点不到**（接口本身可用），推测作者用生成器产出的 `menu.sql` 手工插过、或有意隐藏入口。

---

## 2. 后台业务功能

### 2.0 统一形态（7 个生成器模块）

`BookController`、`CategoryController`、`AuthorController`、`AuthorCodeController`、`NewsController`、`UserController`、`PayController` 同一模板：
`GET /novel/{x}` 返回页面 → `GET /list`（`Query` + `service.list` + `service.count` → `PageBean{total,rows}`）→ `/add` `/edit/{id}` `/detail/{id}` 页面 → `POST /save|/update|/remove|/batchRemove`。权限串统一 `novel:{x}:{x|add|edit|detail|remove|batchRemove}`，返回 `R`（code 0 成功）。
实体 → 表：`BookDO→book`、`CategoryDO→news_category`、`AuthorDO→author`、`AuthorCodeDO→author_code`、`NewsDO→news`、`UserDO→user`、`PayDO→order_pay`。
**Service 实现类无 `@Transactional`**（对比：`MenuServiceImpl`/`RoleServiceImpl`/`SysUserServiceImpl` 有），批删/级联删除全靠 SQL 单语句。

### 2.1 BookController（`novel-admin/src/main/java/com/java2nb/novel/controller/BookController.java`）

- 路径 `/novel/book`，表 `book`（32 个字段）。
- 「上架/审核」相关只有 `status`（0 入库、1 上架，`BookDO.java:91-92`）、`is_vip`、`book_status`（0 连载/1 完结）、`crawl_source_id/crawl_book_id/crawl_last_time/crawl_is_stop`。
- 后台没有审核接口、没有审核日志、没有审核人字段；「上架」= 在编辑页把 `status` 改成 1 走 `/update`。前台是否真的按 `status=1` 过滤——**未确认**（`novel-front` 的 `BookMapper.xml` 中未出现 status 过滤条件）。
- 章节管理：**admin 无章节 Controller**；`book_index`/`book_content` 只由爬虫写入，正文按 `storage_type` 存 DB 或 txt（见 3.5）。

### 2.2 CategoryController

- 路径 `/novel/category`，**实际表是 `news_category`**（`mybatis/novel/CategoryMapper.xml:7,11`），即新闻类别（招募/公告…）。
- 小说分类在 `book_category`（SQL 固定 7 条，行 147-153），后台**没有对应 Controller/菜单**；爬虫按 catId 1..7 写死，新增分类需改代码（`CrawlServiceImpl.openOrCloseCrawl` 循环 `i<8`、`catId==7` 判女频）。

### 2.3 AuthorController / AuthorCodeController

- `/novel/author` → 表 `author`（`pen_name/tel_phone/chat_account/work_direction/status`），`status` 含义 **0 正常 / 1 封禁**（`doc/sql` 行 31；`sys_gen_columns` 同）。
- 作家「入驻审核」在另一张表 `book_author.status`（0 待审核 / 1 通过 / 2 不通过，行 116），**后台无入口**，由前台作家专区写入（`novel-front/.../BookServiceImpl.java:438` 直接置 1）。
- `/novel/authorCode` → `author_code`（`invite_code/validity_time/is_use`），即邀请码发放，无生成/校验逻辑，纯 CRUD。

### 2.4 NewsController

- `/novel/news` → `news`（`cat_id/cat_name/source_name/title/content/read_count`）。只有增删改查，**没有发布/下架状态、没有审核**；`read_count` 由前台累加。
- 后台改新闻后**不会刷新**前台首页新闻缓存（见 4.6）。

### 2.5 UserController（会员）

- `/novel/user` → `user`（`username/password/nick_name/user_photo/user_sex/account_balance/status`）。
- 同样是 CRUD：封禁靠 `/update` 改 `status`，无独立冻结/解冻、无余额调整、无消费记录查看（`user_buy_record` 无后台入口）。

### 2.6 PayController（充值订单）

- `/novel/pay` → `order_pay`：`out_trade_no`、`trade_no`、`pay_channel(1 支付宝/2 微信)`、`total_amount`（元）、`pay_status(0 失败/1 成功/2 待支付)`。后台只能增删改查订单行，**无对账、无补单、无退款**；订单状态实际由前台支付回调写（前台代码，本笔记不展开）。

### 2.7 StatController（统计）

- `novel-admin/src/main/java/com/java2nb/novel/controller/StatController.java`
  - `GET /novel/stat/countSta`：`userService.count / authorService.count / bookService.count / orderPayService.count` 四个总量（会员数、作家数、作品数、订单数）。
  - `GET /novel/stat/tableSta`：`DateUtils.getDateList(7, now)` 近 7 天 + 各表 `tableSta(minDate)`，SQL 是 `DATE_FORMAT(create_time,"%Y-%m-%d") group by` 数当日新增（如 `mybatis/novel/BookMapper.xml:292-304`），Service 再用 `Collectors.toMap(staDate→count)` 组装。
  - 统计只覆盖「新增量/总量」，无 GMV、无充值金额、无阅读量维度。
  - 注意：`StatController` 的方法**没有 `@RequiresPermissions`**，登录即可访问。

### 2.8 GeneratorController（代码生成器）

- `novel-admin/src/main/java/com/java2nb/common/controller/GeneratorController.java`，路径 `/common/generator`
  - `GET /list`：`GeneratorMapper` 查 `information_schema` 表清单；`GET /genColumns/list?tableName=`：列配置清单。
  - `POST /genCode`：**直接写本机磁盘**；`/downLoadCode/{tableName}`、`/batchDownload`：打包 zip 下载；`/batchCode`：批量写盘。
  - `GET /edit` + `POST /update`：编辑并保存 `generator.properties`（作者、包名、表前缀、`srcPath`）。
  - `POST /genColumns/save`：把列配置存 `sys_gen_columns` 后**立即触发生成**。
- 实现：`common/service/impl/GeneratorServiceImpl.java` + `common/utils/GenUtils.java`
  - 列元数据优先取 `sys_gen_columns`，为空则按 `information_schema` 推断：主键 `pageType=11`、`Date→4`、其余 `1`；`tinyint→Integer / bigint→Long / datetime→Date …` 映射表在 `generator.properties`。
  - Velocity（`ClasspathResourceLoader`）渲染 `templates/common/generator/*.vm` 共 14 个模板：`domain/Dao/Mapper.xml/Service/ServiceImpl/Controller` + `list|add|edit|detail.html` + `list|add|edit.js` + `menu.sql`；输出路径由 `GenUtils.getFileName` 决定（Java→`main/java/包/…`，XML→`main/resources/mybatis/{模块}/`，页面→`templates/{模块}/{实体}/`，js→`static/js/appjs/…`）。
  - 目标文件已存在时写入 `xxx+1`；`srcPath` 当前硬编码为 `D:\gitee\admin-base\java2nb\src`（`generator.properties:3`），**换机器即不可用**。
  - 这正是 2.1-2.6 那些 Controller 的来历：生成器的产物被直接用在 `novel` 模块上。

### 2.9 LogController（操作日志）

- 记录方式：注解 + AOP，**不是手写**。
  - `common/annotation/Log.java`（`@Target(METHOD)`，`value()` 描述）
  - `common/aspect/LogAspect.java`：`@Around("@annotation(...Log)")`，执行后收集 `operation=注解 value`、`method=类名.方法()`、`params=JSON(args[0]).substring(0,4999)`（只序列化第一个入参）、`ip=IPUtils.getIpAddr`、当前 Shiro 用户（取不到则 `userId=-1`）、耗时 `time`，写 `sys_log`。
  - `LogServiceImpl.save` 上有 `@Async`（`SpringAsyncConfig` 有 `@EnableAsync`），落库异步。
  - `@Log` 全仓库 23 处，集中在 Login/SysUser/Role/Dept/Menu/DataPerm 等系统模块；**`novel/*` 的业务 CRUD、Log/Dict/File 自身基本没加**，所以业务操作审计是不完整的。另有 `common/aspect/WebLogAspect.java` 切所有 Controller，仅打 log（请求地址/方法/参数/耗时），不落库。
- 查询：`LogController`（`/common/log`）`list` 用 `PageDO`；`remove/batchRemove`。方法上**没有 `@RequiresPermissions`**（`sys_menu` 里虽配了 `common:log`）。

### 2.10 FileController / DictController / SessionController

- `FileController`（`/common/sysFile`）：`POST /upload` 用 UUID 重命名 + `yyyy/MM/dd` 目录 + `java2nb.uploadPath` 落盘，写 `sys_file(type,url)` 返回 url；`/download`、`/remove`（先删记录再删文件，删文件失败会返回「数据库记录删除成功，文件删除失败」）、`/list`。静态映射在 `WebConfigurer`（`/files/** → file:///{uploadPath}`）。账号 `test` 被当作演示账号拒绝写操作。
- `DictController`（`/common/dict`）：`sys_dict` 字典 CRUD，页面用于下拉字典值。`SessionController`（`/sys/online`）：`list` 在线用户、`forceLogout/{sessionId}`、`sessionList`（见 1.2）。

### 2.11 12 个 Controller 的一览与业务缺口

路由/表/权限串：`Book /novel/book→book / novel:book:*`、`Category /novel/category→news_category`、`Author /novel/author→author`、`AuthorCode /novel/authorCode→author_code`（任务清单未列但代码存在）、`News /novel/news→news`、`User /novel/user→user`、`Pay /novel/pay→order_pay`、`Stat /novel/stat→4 表聚合（无权限注解）`、`Generator /common/generator`、`Log /common/log（无权限注解）`、`File /common/sysFile→sys_file`、`Dict /common/dict→sys_dict`、`Session /sys/online→Shiro Session（无权限注解）`。

**业务缺口（重要）**：作品审核流、章节管理、小说分类维护、作家入驻审核（`book_author.status`）、会员冻结/余额调整、订单退款补单——后台**均无接口**，只有最朴素的表 CRUD。面试别把「CMS 审核」讲成系统能力。

---

## 3. 爬虫系统（`novel-crawl`）

### 3.1 模块与入口

- 启动类 `novel-crawl/src/main/java/com/java2nb/novel/CrawlNovelApplication.java`：`@EnableScheduling @EnableCaching @ServletComponentScan @MapperScan("com.java2nb.novel.mapper")`；端口 8081（`application.yml:2-3`）。
- 安全：`novel-crawl/src/main/java/com/java2nb/novel/core/config/SecurityConfiguration.java` —— Spring Security **内存单用户**，账号密码取 `admin.username/admin.password`（默认 `admin/admin`），`BCryptPasswordEncoder`，`/** hasRole("ADMIN")`，关 CSRF，`formLogin + httpBasic`。**没有 RBAC**（和 admin 的 Shiro 完全两套）。
- 页面：`controller/PageController.java` 把 `/{a}.html`、`/{m}/{a}.html`、`/{m}/{c}/{a}.html` 映射成模板名；首页 → `crawl/crawlSource_list`。三个功能页：爬虫源管理、单本采集管理、规则测试（批量采集的菜单在模板里被注释掉了）。
- REST：`controller/CrawlController.java`（`/crawl`）：`addCrawlSource`、`listCrawlByPage`（PageHelper 分页）、`getCrawlSource`、`testParse`、`updateCrawlSource`、`openOrCloseCrawl`、`addCrawlSingleTask`、`listCrawlSingleTaskByPage`、`delCrawlSingleTask`。

### 3.2 开启/停止与线程模型（`service/impl/CrawlServiceImpl.java`）

- **开启**（`openOrCloseCrawl(sourceId, 1)`）：确认库里 `source_status=0` 后置 1，`ObjectMapper` 把 `crawl_rule` 反序列化成 `RuleBean`，对 **catId 1..7 各起一个裸 `Thread`** 跑 `parseBookList(catId, rule, sourceId)`，把 `thread.getId()` 集合写入缓存 `CacheKey.RUNNING_CRAWL_THREAD_KEY_PREFIX + sourceId`。
- **关闭**：先改库为 0，再从缓存取线程 id，`ThreadUtil.findThread(id).interrupt()`；`parseBookList` 每本书前检查 `Thread.currentThread().isInterrupted()` 退出。
- **状态回收**：`core/schedule/CrawlThreadMonitor.java` `@Scheduled(fixedRate = 5min)`，扫 `source_status=1` 的源，若其线程集合全部不 alive 则把库状态改回 0。

### 3.3 采集流程（入口任务 → 列表 → 详情 → 章节 → 入库）

1. `parseBookList`：`bookListUrl` 里替换 `{catId}`/`{page}` → `HttpUtil.getByHttpClientWithChrome(url)`（RestTemplate + 伪 Chrome UA）→ `bookIdPatten` 正则 `while(find)` 逐个取 `group(1)` 作为 bookId → `parseBookAndSave`；本页解析完再用 `totalPagePatten` 更新总页数（首页拿不到就只爬 1 页），逐页递增。
2. `CrawlParser.parseBook`：详情页依次取 `bookName`、`authorName`（二者缺一直接 return）、`picUrl`（可拼 `picUrlPrefix`）、`score`、`visitCount`、`bookDesc`、`bookStatus`（经 `bookStatusRule` 映射）、`lastIndexUpdateTime`（`upadateTimeFormatPatten` 交给 `SimpleDateFormat`）。
   - 清洗：简介用 `descStart/descEnd` 截取后 `replaceAll` 去掉 `<a>`/`<font>`、空 `<p>`，`<p>`→`<br/>`；score/visitCount 互缺时用 `RandomBookInfoUtil` 按分数段随机生成，都缺则 `visitCount=100`、`score=6.5`（`Constants.VISIT_COUNT_DEFAULT`）。
3. `CrawlParser.parseBookIndexAndContent`：目录页 `bookIndexUrl`（可先按 `bookIndexStart` 截断）→ `indexIdPatten` 与 `indexNamePatten` **两个 Matcher 同步 find**，`indexNum` 从 0 递增；逐章抓 `bookContentUrl`（支持 `{bookId}`/`{indexId}` 占位，以及 `{cal_x_y_z}` 计算规则：目前只实现 `calType=1`，取第 x 个 id 的前 `len-y` 位）。
   - 内容：`contentStart/contentEnd` 截取，页面含「正在手打中」则跳过该章；字数用 `StringUtil.getStrValidWordCount`（汉字数 + 英文单词数 + 数字段数）。
   - 成功判定：`indexList.size() == contentList.size() && > 0` 才回调 `CrawlBookChapterHandler` 返回 true；否则回调空列表返回 false。
4. 入库（新书）：`parseBookAndSave` → `bookService.queryBookByBookNameAndAuthorName` 判重 → 不存在则 `id = IdWorker.INSTANCE.nextId()`，补 `catId/catName/workDirection(7→女频,否则男频)/crawlBookId/crawlSourceId/crawlLastTime`，再 `saveBookAndIndexAndContent`。

### 3.4 采集规则（Rule）怎么配、怎么存

- 存储：`crawl_source.crawl_rule`（`text`，JSON 串），随 `source_name/source_status` 一起编辑保存；页面新增/修改源就是整段 JSON 落库，运行时 `new ObjectMapper().readValue(json, RuleBean.class)`。
- 模型：`core/crawl/RuleBean.java`，字段即正则/标记：`bookListUrl`、`catIdRule`（catId1..7 → 源站分类 id）、`bookIdPatten`、`pagePatten`、`totalPagePatten`、`bookDetailUrl`、`bookNamePatten`、`authorNamePatten`、`picUrlPatten`、`picUrlPrefix`、`statusPatten`、`bookStatusRule`、`scorePatten`、`visitCountPatten`、`descStart/descEnd`、`upadateTimePatten(拼写如此)`、`upadateTimeFormatPatten`、`bookIndexUrl`、`bookIndexStart`、`indexIdPatten`、`indexNamePatten`、`bookContentUrl`、`contentStart/contentEnd`。
- 表达式能力：**纯 Java 正则 + 字符串定界截取**，没有 jsoup、XPath、CSS selector。`core/crawl/PatternFactory.java` 用 `HashMap` 做 `Pattern` 缓存（无同步，7 个爬虫线程并发写有风险）。
- 预置站点（SQL 中的 5 条 JSON，含相对/绝对路径差异）：百书斋、书包网、书趣阁、笔趣阁、i笔趣阁；`catIdRule` 逐站不同。
- 规则测试：`POST /crawl/testParse`，url 必须 `http(s)` 开头，抓到的 html 以 `CacheKey.BOOK_TEST_PARSE + url` 缓存 10 分钟（`isRefresh=1` 强制重抓）；`Pattern.compile(rule).matcher(html).find()` → 返回「是否匹配 / 匹配结果(group1)」。

### 3.5 入库表、去重、更新老书

- 表：`book`（主表）、`book_index`（目录，`unique(book_id,index_num)`）、`book_content`（正文，`unique(index_id)`；`application-common-dev.yml` 里用 Sharding-JDBC 按 `index_id % 10` 分到 `book_content0..9`）。
- 去重：`queryIsExistByBookNameAndAuthorName` + `book` 表唯一键 `key_uq_bookName_authorName(book_name,author_name)` 双保险；命中已有书时**不覆盖内容**，只 `updateCrawlProperties`（更新 `crawl_source_id/crawl_book_id`）。
- 状态：爬虫入库**不设 `book.status`**，由表默认值决定（`doc/sql/novel_plus.sql:87` 默认 `0`＝入库），所以采集来的书默认不是「上架」。同理 `crawl_is_stop`、`is_vip` 也不写。
- 事务：`BookServiceImpl.saveBookAndIndexAndContent` / `updateBookAndIndexAndContent` 有 `@Transactional(rollbackFor = Exception.class)`；新书只有在 `bookIndexList` 非空时才写库（避免空章节的书入库）。
- 正文存储可切换：`content.save.storage = db | txt`，通过 `Map<String,BookContentService>` 注入 `@Service("db") DbBookContentServiceImpl`（写 `book_content`）与 `@Service("txt") FileBookContentServiceImpl`（写 `{content.save.path}/{bookId}/{indexId}.txt`），每章把选择的 `storageType` 记到 `book_index.storage_type`（该列由 SQL 末尾 `alter table` 追加）。**配置坑**：`application-common-dev.yml:74-77` 注释写的是 `file：txt文本`，但 Bean 名实际是 `txt`，`Map.get("file")` 会取空 → 只能填 `db`/`txt`。
- 增量更新老书（`core/listener/StarterListener.java`，`@WebListener`）：按 `crawl.update.thread`（默认 1）起线程，循环：
  1. `queryNeedUpdateBook(now-30d, 100)`：`select ... from book where last_index_update_time > #{startDate} and crawl_source_id is not null order by crawl_last_time limit ${limit}`，查完立刻批量 `update crawl_last_time=now` 防重复取（`mybatis/mapping/BookMapper.xml:6-27`）；
  2. 逐本：读规则 → `parseBook`（刷新书名/简介/评分等）→ 本地封面 `/localPic/` 不覆盖 → `queryExistBookIndexMap(bookId)` 得到 `indexNum→BookIndex` → `parseBookIndexAndContent(existMap)`；
  3. 章节级：`indexNum` 不存在则 insert，存在且**章节名（去空白后）不同**才 update（相同则跳过，不重抓正文）；字数按「新章字数 - 旧章字数」增量维护；内容更新用**旧记录的 `storage_type`**；
  4. 主表：`updateByPrimaryKeySelective`，先把 `bookName/authorName` 置 null 防覆盖，`visitCount` 等于默认值 100 时也置 null；
  5. 每轮 `TimeUnit.MINUTES.sleep(10)`。
- 单本采集任务（`crawl_single_task`）：另一条常驻线程每分钟取一条 `task_status=2`（未执行）按 `create_time` 最早的任务 → `parseBookAndSave` → `updateCrawlSingleTask`：`exc_count+1`，成功(1)或 `exc_count==5` 才写最终状态，否则保持 2 等待重试。新增任务时先按书名+作者判重，已存在抛 `BusinessException(ResponseStatus.BOOK_EXISTS)`。

### 3.6 调度、重试、代理

- 调度：没有 Quartz/XXL-Job。只有 `CrawlThreadMonitor` 的 `@Scheduled(fixedRate=5*60*1000)`；其余靠 `ServletContextListener` + 裸线程 + `sleep`（10 分钟 / 1 分钟）。
- 重试：`CrawlParser.getByHttpClientWithChrome` → 返回体长度 < `Constants.INVALID_HTML_LENGTH(1500)` 或异常 → `processErrorHttpResult`：`ThreadLocal<Integer> retryCount`，最多 `HTTP_FAIL_RETRY_COUNT(5)` 次，每次 `sleep(random(10s))` 后重抓；失败返回 null，上层跳过该书/该章。缺陷：`retryCount` **从不清理**，同一线程后续请求会因计数已达 5 直接放弃；重试走的是不带 UA 的 `getByHttpClient`。
- 代理：**没有**。只有 UA 伪装、SSL 信任所有证书、连接池（`maxTotal 1000 / perRoute 300`，connect 3s / read 30s，`novel-common/.../RestTemplateUtil.java`）。无 Cookie 池、无频率限制、无 IP 轮换。
- 遗留：`crawl_batch_task`（批量抓取任务表）在 `novel-crawl` 代码中**零引用**（无 Mapper/Service/Controller 使用），批量采集未实现。

---

## 4. 技术实现细节

### 4.1 MyBatis 两套写法并存

- `novel-admin`：传统 XML Mapper（`mybatis/**/*Mapper.xml`，`map-underscore-to-camel-case: true`），动态条件全靠 `<if>/<where>/<choose>`，排序写 `${sort} ${order}`（**直接字符串拼接**），分页 `limit #{offset},#{limit}`。这些都是生成器模板产出的。
- `novel-common` / `novel-crawl`：MyBatis Dynamic SQL DSL，形如 `select(id, sourceName).from(crawlSource).where(id, isEqualTo(x)).orderBy(updateTime).limit(1).build().render(RenderingStrategies.MYBATIS3)` → `SelectStatementProvider` → `selectMany(...)`；`insertSelective/updateByPrimaryKeySelective/insertMultiple` 由 `*Mapper` 接口（继承 dynamic-sql 生成的 support 类）提供。
- 少数方法仍是「接口 + XML」：`CrawlBookMapper.queryNeedUpdateBook/updateCrawlLastTime`、`CrawlBookIndexMapper.queryLastIndex`（`mybatis/mapping/*.xml`），其中 `limit ${limit}` 是字符串拼接。

### 4.2 分页

- admin：前端 layui 传 `offset/limit`，`Query` 计算 `page = offset/limit + 1`；Controller 手动 `count + list` 装 `PageBean{total,rows}`（日志用 `PageDO`）。crawl：`PageHelper.startPage` + `PageBuilder.build(list)`，再 `BeanUtil.copyList` 转 VO（`CrawlSourceVO`/`CrawlSingleTaskVO`），前端读 `data.pageNum/pageSize/total`。

### 4.3 事务边界

- 有事务：`MenuServiceImpl`（类级 `readOnly=true`，写方法单独 `@Transactional(readOnly=false)`）、`RoleServiceImpl`（角色-菜单-数据权限三表联动）、`SysUserServiceImpl`（类级）、`GeneratorServiceImpl.genColumnsSave`、crawl 的 `BookServiceImpl` 两个写方法。
- 无事务：`novel/*ServiceImpl`（Book/Author/News/Pay/User/Category/AuthorCode），跨表一致性无保护；爬虫写 txt 文件也不回滚（DB 事务管不到文件系统）。

### 4.4 统一异常与返回

- `common/exception/CommonExceptionHandler.java`（`@RestControllerAdvice`）：`BusinessException` → `R.error(code,msg)`；`DuplicateKeyException` → 「数据库中已存在该记录」；`NoHandlerFoundException` → 404；`AuthorizationException` → ajax 返回 403 JSON / 页面 `error/403`；兜底 `Exception` → **写一条 `sys_log`（operation=error）** 再返回 500。
- 返回体统一 `R extends HashMap`：`code`（0 成功，1 失败，500 错误，403 未授权）、`msg`、业务字段。crawl 模块返回 `RestResult`（`io.github.xxyopen`）。

### 4.5 Redis 使用

- admin：默认 `spring.cache.type=ehcache`（EhCache 做 Shiro 权限缓存 + `MemorySessionDAO`）；改 `redis` 才切 `RedisCacheManager`/`RedisSessionDAO`（`ShiroConfig.java:95-99,164-171`），`RedisManager.expire=1800`；`RedisConfig` 定义 `RedisTemplate`（key String / value Jackson2Json，开了 default typing）；`RedisUtil` 为通用封装。
- crawl / common：自研 `CacheService` 抽象（`get/set/setObject/del/contains/expire`），按 `cache.type` 选择 `EhCacheServiceImpl` 或 `RedisServiceImpl`；实际用途只有两处：运行中爬虫线程 id（`runningCrawlTreadDataKeyPrefix{sourceId}`）与规则测试 html（`testParse{url}`，10 分钟）。`CacheKey` 里 `INDEX_*`、`ES_*`、`BOOK_ADD_VISIT_COUNT` 属于前台模块。

### 4.6 类目/首页缓存刷新（注意：不在 admin/crawl）

后台改新闻、改分类、改书都**不主动清缓存**。仓库里唯一的缓存刷新入口在前台模块：
`novel-front/src/main/java/com/java2nb/novel/controller/CacheController.java` `GET /cache/refresh/{pass}/{type}`（`type`：1 首页推荐书、2 首页新闻、3 友情链接），校验 `cache.manager.password` 后 `cacheService.del(key)` 再重新加载触发 `@Cacheable` 回填。所以「后台发布 → 前台生效」中间是**人工刷新**（或缓存过期）。面试若被问「发布后怎么生效」，据实答：靠接口刷新/过期，不是消息广播。

### 4.7 其他横切

- XSS：`common/xss/XssFilter.java`（`@WebFilter("/*")`）用 `XssAndSqlHttpServletRequestWrapper` 包装请求，白名单排除生成器的 `batchCode/batchDownload`（那里要传原始 JSON）。
- 序列化/异步：`LongToStringSerializer` + `spring.jackson.generator.write-numbers-as-strings` 规避 JS 大整数精度丢失（雪花 id）；`SpringAsyncConfig @EnableAsync`（线程池 Bean 被注释，用默认 `SimpleAsyncTaskExecutor`）。

---

## 5. 关键类清单（包名 · 类名 · 一句话职责 · 路径）

| # | 包 | 类 | 职责 | 路径（相对仓库根） |
|---|---|---|---|---|
| 1 | `com.java2nb.system.controller` | `LoginController` | 登录/验证码/登出/首页菜单装配 | `novel-admin/src/main/java/com/java2nb/system/controller/LoginController.java` |
| 2 | `com.java2nb.system.shiro` | `UserRealm` | Shiro 认证 + 权限集合 + 数据权限注入 principal | `novel-admin/src/main/java/com/java2nb/system/shiro/UserRealm.java` |
| 3 | `com.java2nb.common.config` | `ShiroConfig` | 过滤链、会话管理器、缓存（ehcache/redis）切换 | `novel-admin/src/main/java/com/java2nb/common/config/ShiroConfig.java` |
| 4 | `com.java2nb.common.utils` | `MD5Utils` | MD5+盐 2 次迭代的口令哈希 | `novel-admin/src/main/java/com/java2nb/common/utils/MD5Utils.java` |
| 5 | `com.java2nb.common.interceptor` | `DataPermInterceptor` | 拦截 `*ByPerm` SQL 并拼数据权限 WHERE | `novel-admin/src/main/java/com/java2nb/common/interceptor/DataPermInterceptor.java` |
| 6 | `com.java2nb.system.service.impl` | `MenuServiceImpl` | 菜单树、角色菜单树、权限串拆分 | `novel-admin/src/main/java/com/java2nb/system/service/impl/MenuServiceImpl.java` |
| 7 | `com.java2nb.system.service.impl` | `SysUserServiceImpl` | 系统用户 CRUD、角色关联、改密/重置、头像裁剪 | `novel-admin/src/main/java/com/java2nb/system/service/impl/SysUserServiceImpl.java` |
| 8 | `com.java2nb.system.service.impl` | `RoleServiceImpl` | 角色 + 菜单 + 数据权限三表联动（事务） | `novel-admin/src/main/java/com/java2nb/system/service/impl/RoleServiceImpl.java` |
| 9 | `com.java2nb.system.service.impl` | `SessionServiceImpl` | 在线用户列表、强退（session timeout=0） | `novel-admin/src/main/java/com/java2nb/system/service/impl/SessionServiceImpl.java` |
| 10 | `com.java2nb.common.exception` | `CommonExceptionHandler` | 统一异常 → R / 403 / 500 页面，异常落日志 | `novel-admin/src/main/java/com/java2nb/common/exception/CommonExceptionHandler.java` |
| 11 | `com.java2nb.common.aspect` | `LogAspect` | `@Log` 切面，异步写 `sys_log` | `novel-admin/src/main/java/com/java2nb/common/aspect/LogAspect.java` |
| 12 | `com.java2nb.common.service.impl` | `GeneratorServiceImpl` | 表/列元数据 → 代码生成、列配置持久化 | `novel-admin/src/main/java/com/java2nb/common/service/impl/GeneratorServiceImpl.java` |
| 13 | `com.java2nb.common.utils` | `GenUtils` | Velocity 渲染 14 个 `.vm` 并写盘/打包 | `novel-admin/src/main/java/com/java2nb/common/utils/GenUtils.java` |
| 14 | `com.java2nb.common.controller` | `FileController` | 上传落盘（UUID+日期目录）、下载、删除 | `novel-admin/src/main/java/com/java2nb/common/controller/FileController.java` |
| 15 | `com.java2nb.novel.controller` | `BookController` | `book` 表 CRUD（`status` 即上架标志） | `novel-admin/src/main/java/com/java2nb/novel/controller/BookController.java` |
| 16 | `com.java2nb.novel.controller` | `CategoryController` | 实为 `news_category` 新闻类别 CRUD | `novel-admin/src/main/java/com/java2nb/novel/controller/CategoryController.java` |
| 17 | `com.java2nb.novel.controller` | `StatController` | 总量 + 近 7 天新增曲线 | `novel-admin/src/main/java/com/java2nb/novel/controller/StatController.java` |
| 18 | `com.java2nb.novel.controller` | `PayController` | `order_pay` 充值订单 CRUD | `novel-admin/src/main/java/com/java2nb/novel/controller/PayController.java` |
| 19 | `com.java2nb.novel.controller` | `CrawlController` | 爬虫源/单本任务 REST（含规则测试） | `novel-crawl/src/main/java/com/java2nb/novel/controller/CrawlController.java` |
| 20 | `com.java2nb.novel.service.impl` | `CrawlServiceImpl` | 开停爬虫、分类列表遍历、单本任务调度、入库判定 | `novel-crawl/src/main/java/com/java2nb/novel/service/impl/CrawlServiceImpl.java` |
| 21 | `com.java2nb.novel.core.crawl` | `CrawlParser` | 详情/目录/正文正则解析、重试、字数统计 | `novel-crawl/src/main/java/com/java2nb/novel/core/crawl/CrawlParser.java` |
| 22 | `com.java2nb.novel.core.crawl` | `RuleBean` / `PatternFactory` | 采集规则模型（JSON → Bean）/ `Pattern` 缓存 | `novel-crawl/src/main/java/com/java2nb/novel/core/crawl/RuleBean.java` |
| 23 | `com.java2nb.novel.core.listener` | `StarterListener` | 启动老书增量更新线程 + 单本任务线程 | `novel-crawl/src/main/java/com/java2nb/novel/core/listener/StarterListener.java` |
| 24 | `com.java2nb.novel.core.schedule` | `CrawlThreadMonitor` | 5 分钟回收已停止的爬虫源状态 | `novel-crawl/src/main/java/com/java2nb/novel/core/schedule/CrawlThreadMonitor.java` |
| 25 | `com.java2nb.novel.service.impl` | `BookServiceImpl`(crawl) / `DbBookContentServiceImpl` | 判重、事务写 book/book_index/正文、增量更新；正文存 DB | `novel-crawl/src/main/java/com/java2nb/novel/service/impl/BookServiceImpl.java` |
| 26 | `com.java2nb.novel.service.impl` | `FileBookContentServiceImpl` | 正文存 txt（`@Service("txt")`） | `novel-crawl/src/main/java/com/java2nb/novel/service/impl/FileBookContentServiceImpl.java` |
| 27 | `com.java2nb.novel.core.config` | `SecurityConfiguration` | 爬虫后台单管理员登录（Spring Security + BCrypt） | `novel-crawl/src/main/java/com/java2nb/novel/core/config/SecurityConfiguration.java` |
| 28 | `com.java2nb.novel.core.utils` | `HttpUtil` / `RestTemplateUtil` | 抓取 HTTP 客户端（UA 伪装、连接池、信任所有证书） | `novel-common/src/main/java/com/java2nb/novel/core/utils/HttpUtil.java` |
| 29 | `com.java2nb.novel.core.cache` | `CacheService` / `CacheKey` | 缓存抽象与 key 常量（线程集合、规则测试） | `novel-common/src/main/java/com/java2nb/novel/core/cache/CacheService.java` |

---

## 6. 面试可讲 / 需谨慎

- **可讲**：Shiro RBAC（菜单树 + 按钮权限串）、MyBatis 拦截器做数据权限（SQL 改写 + 反射）、爬虫规则外置 JSON、正文存储可插拔（db/txt + Sharding 分表）、增量更新按「序号 + 章节名」判新旧、代码生成器（Velocity 模板 + 元数据）。
- **需谨慎**：①「审核/上架」只有一个 `status` 字段，没有流转/审核人/审核日志；②小说分类、章节、作家入驻审核在后台没有入口；③数据权限只对 `sys_user` 生效（拦截器靠方法名 `ByPerm` 触发，属演示性实现）；④爬虫 `ThreadLocal` 重试计数不清、`{cal_...}` 的 `x!=1` 分支仍用 `sourceBookId.length()`（疑笔误）、`PatternFactory` 用非线程安全 `HashMap`；⑤批量采集（`crawl_batch_task`）未实现；⑥爬虫后台与平台后台两套鉴权（Spring Security 内存单用户 vs Shiro+DB），无 SSO。
