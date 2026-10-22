# novel-plus v6.0.0 架构 / 技术栈 / 配置 / 部署 / 数据模型增量 调研笔记

> 基线：`upstream/master`（Tip `e8daac0a` 2026-10-21；`v6.0.0` tag 指向 `537027cd`）。对比基线：`906e7762`（v3.6.1，Java 8 + Spring Boot 2.1.8）。
> 取证：`git -C <仓库根> show upstream/master:<路径>` / `ls-tree -r --name-only upstream/master -- <路径>` / `diff 906e7762 upstream/master -- <路径>`。只写代码、配置、脚本能确认的事实，找不到闭环证据的标「未确认」。

## 0. 速览（面试口径）

- **4 个 Maven 模块**不变：`novel-common`（普通 jar，非 starter）/`novel-front`（门户+作家后台）/`novel-crawl`（爬虫）/`novel-admin`（平台后台），另有非 Maven 的 `templates/` 模版目录。
- **Java 21 + Spring Boot 3.4.0 + Spring AI 1.0.0**：根 `pom.xml` 用 `spring-ai-bom:1.0.0`（`dependencyManagement` + `scope=import`）统一版本。
- **打包形态换了**：v3.6 是「瘦 jar + `layout=ZIP` + `-Dloader.path=conf,lib`」；v6 是 **fat jar + 外置 `config/` + 外置 `templates/`**，启动脚本只 `java -jar`。
- **分库分表依赖换代且配置外置**：`io.shardingsphere:sharding-jdbc-spring-boot-starter:3.0.0` → `org.apache.shardingsphere:shardingsphere-jdbc:5.5.1`，分片规则从 `application-common-*.yml` 挪到独立文件 `config/shardingsphere-jdbc.yml`。
- **缓存只剩 Redis**：删除 `EhCacheServiceImpl` 与 `cache.type` 开关；**后台安全框架换了**：`novel-admin` 由 Shiro 全量重写为 Spring Security 内存用户，151 个旧 java 文件被删。
- **ES / RabbitMQ / FastDFS 全部退场**：v3.6 front 的 `jest`、`elasticsearch-rest-high-level-client`、`spring-boot-starter-data-elasticsearch`、`spring-boot-starter-amqp`、`fastdfs-client` 及 `EsConfig`、`SearchService`、`BookToEsSchedule`、`BookVisitAddListener` 一并删除。
- **数据模型新增 9 张表**：`website_info`、`user_book_list`、`user_book_list_item`、`book_paragraph_comment`、`user_message`、`ai_creation_plan`、`ai_chapter_plan`、`ai_creation_task`、`ai_author_pref`。

## 1. 依赖与版本

### 1.1 根 `pom.xml`（`git show upstream/master:pom.xml`）

| 项 | v3.6.1 | v6.0.0 |
| --- | --- | --- |
| `project.version` | `3.6.1` | `6.0.0` |
| Spring Boot parent | `2.1.8.RELEASE` | `3.4.0` |
| `java.version` | `1.8` | `21` |
| MyBatis starter / dynamic-sql / PageHelper | `2.1.4` / `1.1.4` / `1.2.5` | `3.0.4` / `1.5.0` / `1.4.6` |
| ShardingSphere | `sharding.jdbc=3.0.0`（`io.shardingsphere`） | `shardingsphere-jdbc=5.5.1`（`org.apache.shardingsphere`） |
| MySQL 驱动 | `8.0.11` | `8.0.29`（坐标仍是 `mysql:mysql-connector-java`） |
| JJWT | `0.9.0` | `0.9.1` |
| aliyun-oss / commons-fileupload / alipay-sdk | `2.4.0` / `1.3.1` / `4.9.153.ALL` | `3.16.3` / `1.5` / `4.35.139.ALL` |
| 被删属性 | — | `elasticsearch.version=7.9.3`、`orderbyhelper.version`、`fastdfs-client.version` |
| 新增 | — | `spring-ai-bom:1.0.0`、`central-repo` profile（切 Maven 中央仓库） |

- 仍残留但已无依赖使用的属性：`jest.version=6.3.1`、`redis.version=1.4.1.RELEASE`、`redisson.version=3.12.5`、`xxyopen.version=1.0.0`；`maven.test.skip=true` 保留，`maven-antrun-plugin` 是打发布包的主力插件。

### 1.2 四个模块 pom 的增删

**`novel-common/pom.xml`**
- 增：`spring-boot-starter-aop`、`shardingsphere-jdbc`、`com.h2database:h2`（runtime，ShardingSphere 5.x 依赖）、`httpclient5`（替换 httpclient 4.5.2）、`hibernate-validator`（注释「请求参数校验相关」）、`maven-antrun-plugin`（把 `doc/sql` 打成 `target/build/sql.zip`）。
- 删：`net.sf.ehcache:ehcache`、`sharding-jdbc-spring-boot-starter` + `sharding-jdbc-spring-namespace`、`orderbyhelper-spring-boot-starter`、`httpclient:4.5.2`；保留 `spring-boot-starter-redis:1.4.1.RELEASE`（Spring Boot 1.x 时代的老 starter 坐标）。

**`novel-front/pom.xml`**
- 增：`snakeyaml:2.2`、`jackson-databind`、`spring-ai-starter-model-openai`、`ip2region:2.7.0`、`houbb:sensitive-word:0.29.5`。
- 删：`spring-boot-starter-amqp`、`jest`、`elasticsearch-rest-high-level-client`、`spring-boot-starter-data-elasticsearch`、`fastdfs-client`、`maven-shade-plugin`、`maven-dependency-plugin`（v3.6 用来做「瘦 jar + lib/」）。
- 打包：`spring-boot-maven-plugin`（默认 repackage，**fat jar**）+ `maven-antrun-plugin` 组装 `target/build/{config,templates,bin,<artifactId>.jar,Dockerfile,<artifactId>.zip}`，jar 名去版本号。

**`novel-admin/pom.xml`**（改动最大）
- v3.6：自己声明 parent（Boot 2.0.1）与 `3.6.1` 版本，依赖 Shiro/shiro-ehcache/thymeleaf-extras-shiro、velocity、fastjson、druid、swagger2、jedis、ehcache、nekohtml、commons-configuration 等。
- v6：继承根 parent，只剩 **4 个依赖** —— `novel-common`、`snakeyaml:2.2`、`spring-boot-starter-security`、`jackson-databind`；构建改为 fat jar + `build/config` + Dockerfile。

**`novel-crawl/pom.xml`**
- 增：`snakeyaml:2.2`、`jackson-databind`、`spring-boot-starter-mail`；删：`maven-shade-plugin`、`maven-dependency-plugin`；保留 v3.6 已有的 `spring-boot-starter-security`。

## 2. 配置

### 2.1 端口（源码默认 vs 生产包外置配置）

| 模块 | `src/main/resources/application.yml` | `src/main/build/config/application.yml`（部署包 `config/`） |
| --- | --- | --- |
| novel-front | `8083` | `8085` |
| novel-admin | `80` | `8088` |
| novel-crawl | `8081` | `8083` |

- 外置 `config/application.yml` 覆盖 jar 内 `application.yml`（Boot 默认 `./config/` 优先级更高），且都写死 `spring.profiles.active: prod`；注意 crawl 部署包 `8083` 与 front 源码默认 `8083` 撞车。

### 2.2 profile 引入链

`application.yml`（`spring.profiles.active: dev|prod`）→ `application-{dev,prod}.yml`（只有一行 `spring.config.import: classpath:application-common-{dev,prod}.yml`）→ `application-common.yml`。v3.6 是 `spring.profiles.include: [common]`，v6 改成 **`spring.config.import`**（Boot 2.4+ 机制）。
- front 的 `application.yml` 额外 `include: website,alipay,oss`，对应 `application-website.yml`、`application-alipay.yml`、`application-oss.yml`。
- `novel-crawl/src/main/resources/application-test.yml` 写 `include: [common-test]`，但 `novel-common/src/main/resources/` 只有 `application-common.yml`/`-dev`/`-prod`，**没有 `application-common-test.yml`**（该 profile 是否废弃未确认）。

### 2.3 数据源与连接池（`novel-common/src/main/resources/application-common.yml`）

```yaml
spring:
  datasource:
    url: jdbc:shardingsphere:absolutepath:${user.dir}/config/shardingsphere-jdbc.yml
    driver-class-name: org.apache.shardingsphere.driver.ShardingSphereDriver
```

- 业务 yml 里**不再出现 username/password/druid**（v3.6 的 `application-common-dev.yml` 是 `spring.datasource` 直连 MySQL + 一套 `sharding.jdbc.datasource.ds0.type: HikariDataSource`）；连接池统一在分片配置里 `dataSourceClassName: com.zaxxer.hikari.HikariDataSource` 创建（见 2.4）。
- 保留：`mybatis.mapper-locations: classpath*:mybatis/mapping/*.xml`、`type-aliases-package: com.java2nb.novel.entity`、`map-underscore-to-camel-case: true`、`pagehelper.helper-dialect: mysql`、`logging.config: classpath:logback-boot.xml`。

### 2.4 `config/shardingsphere-jdbc.yml` 分片规则

四份文件：仓库根 `config/shardingsphere-jdbc.yml`（未见于打包脚本引用，按 `${user.dir}` 推断是「在仓库根目录起进程」时用，用途未确认）与三份打包副本 `novel-{front,admin,crawl}/src/main/build/config/shardingsphere-jdbc.yml`（antrun 拷进发布包 `config/`）。

| 项 | 值 |
| --- | --- |
| 运行模式 / 其它 | `mode.type: Standalone`、元数据 `repository.type: JDBC`；`props.sql-show: true`（打印 SQL） |
| 数据源 | `ds_1`：Hikari + MySQL `localhost:3306/novel_plus`，root/test123456 |
| SINGLE 规则 | `- !SINGLE tables: ["*.*"]`（未单独配置的表走单表路由） |
| 分片表 | `book_content`（逻辑表） |
| 分片键 | `shardingColumn: index_id`（章节 ID，**不是** `book_id`） |
| 表名规则 | `actualDataNodes: ds_${1}.book_content${0..9}` + `INLINE` 算法 `book_content${index_id % 10}` |
| 是否分库 | **否**：只声明 `ds_1` 一个库，节点表达式 `ds_${1}`，无 `databaseStrategy`（v3.6 里也是注释掉 database-strategy） |

- 根配置比模块副本多一个 `ds_2`，但写成 `url:`（Hikari 的属性名是 `jdbcUrl`）且指向 `information_schema`，是否导致 5.5.1 启动建池报错**未确认**；根配置的 `jdbcUrl` 带 `allowPublicKeyRetrieval=true`（commit `0e156c04`），**三个模块副本没有**。

### 2.5 Redis（`application-common-dev.yml` / `-prod.yml`）

- v6 用 Boot 3 新前缀 `spring.data.redis.{host,port,password,timeout}`（v3.6 是 `spring.redis.*` + `jedis.pool.*`）；dev `127.0.0.1:6379` / `test123456` / `timeout: 10000`，prod 同主机同密码、仅 `logging.level.root: error`。
- 没有自定义 `RedisConfig`/`RedisTemplate` Bean（admin 的 `RedisConfig` 已删除），走 Boot 自动配置 + `StringRedisTemplate`。

### 2.6 AI 配置（`novel-front/src/main/resources/application.yml` 末尾）

```yaml
spring:
  ai:
    openai:
      api-key: sk-...            # 明文入库
      base-url: https://api.siliconflow.cn
      chat.options.model: deepseek-ai/DeepSeek-R1-0528-Qwen3-8B
      image:
        enabled: true
        api-key: sk-...          # 明文入库
        base-url: https://api.siliconflow.cn
        options: { model: Kwai-Kolors/Kolors, response_format: URL }
```

- 只有 `novel-front` 引 `spring-ai-starter-model-openai`，admin/crawl 无 AI 依赖；`core/config/AiConfig.java` 自定义 `RestClient.Builder`（connect 5000ms / read 60000ms）并暴露 `ChatClient` Bean。
- 提示词外置为 `novel-front/src/main/resources/prompts/ai-assistant/*.txt`（7 个：`book_name`/`chapter_check`/`chapter_content`/`chapter_plan_batch`/`chapter_revise`/`chapter_summary`/`creative_plan`），由 `core/ai/PromptTemplateUtil` 按 `{key}` 占位符渲染并缓存；部署包 `build/config/application.yml` 里另有一把不同的 api-key（同样明文）。

### 2.7 JWT

| 位置 | 内容 |
| --- | --- |
| `novel-front/src/main/resources/application.yml` | `jwt.secret: ${JWT_SECRET:}`（默认空）、`jwt.expiration: 604800` |
| `application-dev.yml` | `jwt.secret: ${JWT_SECRET:novel!#20191230}`（dev 弱默认值） |
| `application-prod.yml` | 不覆盖 → prod 下只能来自环境变量 |
| `core/utils/JwtTokenUtil.java` | `@Value("${jwt.secret}")`，`Jwts.builder().signWith(SignatureAlgorithm.HS512, secret)` |

### 2.8 上传 / 正文存储 / 模板 / XSS

- 图片：`pic.save.{type,storage,path}`，`type: 1` 用爬取网络图、`type: 2` 存自己介质，`storage: local|OSS`，OSS 走 `application-oss.yml` 的 `novel.file.{endpoint,key-id,key-secret,bucket-name,file-host,web-url}`；dev 的 `path` 是 `/Users/xiongxiaoyang/java/`（作者本机路径）。上传统一限 `spring.servlet.multipart.max-file-size: 100MB`（admin 另限 5MB/20MB）。
- 正文：`content.save.{storage,path}`，`storage: db|txt`；实现是 `@Service("db") DbBookContentServiceImpl` 与 `@Service("txt") FileBookContentServiceImpl`，按 Bean 名从 Map 取（v3.6 同机制）。
- 模板：prod 下 `spring.thymeleaf.prefix: file:${user.dir}/templates/${templates.name}/html/`、`spring.web.resources.static-locations: file:${user.dir}/templates/${templates.name}/static/`，`templates.name: green`；仓库并存 `templates/green` 与 `templates/orange`。
- XSS：`xss.{enabled,excludes,urlPatterns}`，实现 `core/filter/XssFilter` + `core/wrapper/XssHttpServletRequestWrapper` + `core/config/FilterConfig`；白名单含新增的 `/book/addParagraphComment`、`/bookList/*`、`/author/aiAssistant/*` 等写接口。其它：`author.income.*`、`book.price.*`、`cache.manager.password`、`thread.pool.*`、`http.proxy.*`（配 `core/config/HttpProxyProperties` + `core/utils/RestTemplates` 的 HttpClient5 连接池）。

### 2.9 admin / crawl 专属配置

- admin：`admin.username: admin` / `admin.password: admin`，被 `novel/core/config/SecurityConfiguration.java` 读取 —— `InMemoryUserDetailsManager` + `BCryptPasswordEncoder`、`formLogin("/login.html")`、`loginProcessingUrl("/login")`、`anyRequest().hasRole("ADMIN")`、`csrf.disable()`、启用 `httpBasic`（登录不再查 `sys_user` 表）。
- crawl：`crawl.update.thread: 1`、`crawl.interval.{min:300,max:500}`（ms）、`spring.mail.*`（smtp.163.com:465，配 `EmailService`）、`disk-monitor.{enabled,interval-minutes,warning:85,severe:90,critical:95,recipients}`（对应 `core/config/DiskMonitorProperties` + `core/schedule/DiskMonitorSchedule`）。

## 3. 部署

### 3.1 Dockerfile（三份同构，仅 jar 名不同）

`novel-{front,admin,crawl}/src/main/build/docker/Dockerfile`：

```dockerfile
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY novel-front.jar /app/
# 默认关闭 ShardingSphere，保证旧版本兼容
ENV JDBC_DRIVER=com.mysql.cj.jdbc.Driver
ENTRYPOINT ["sh","-c","exec java -Dspring.datasource.driver-class-name=${JDBC_DRIVER} -jar /app/novel-front.jar"]
```

- 基础镜像从 JDK8 时代升到 `eclipse-temurin:21-jre`，容器内只放 fat jar，**不打入 `config/`**（配置靠挂载/环境变量）；`doc/sql/Dockerfile` 是 `FROM mysql:8.0.46` + `COPY novel_plus_data.sql /docker-entrypoint-initdb.d/init.sql`。
- 注意：注释说「默认关闭 ShardingSphere」，实际只覆盖了 `driver-class-name`，`spring.datasource.url` 仍是 `jdbc:shardingsphere:absolutepath:` —— 该组合能否启动**未确认**（很可能需同时覆盖 `SPRING_DATASOURCE_URL`）。

### 3.2 `.github/workflows/release.yml`

- 触发 push tag `v*`，`ubuntu-latest` 上：`checkout@v3` → `setup-java@v3`（JDK 21 / temurin）→ `mvn clean install -DskipTests=true -Pcentral-repo` → `actions/create-release@v1`（`GITHUB_TOKEN: secrets.GH_PAT`）→ 上传 4 个 zip（`novel-common/target/build/sql.zip`、`novel-{crawl,front,admin}/target/build/<artifactId>.zip`）→ 登录 Docker Hub → `docker/build-push-action@v5` 推送 `novel-front`/`novel-admin`/`novel-crawl`（`latest` + tag）→ 解压 `novel_plus_data.sql.zip` 后构建 `201206030/mysql-novel-plus`。
- 结论：一次打 tag 同时产出 4 个 zip + 4 个镜像。

### 3.3 启动脚本

| v3.6 | v6 |
| --- | --- |
| 每模块 `start.sh` / `stop.sh` / `windows-start.bat` / `readme.txt` | 每模块 `novel-<模块>.sh` + `novel-<模块>.bat` |

- v6 `novel-front.sh`：`start|stop|restart|status` 四合一，`cd $(dirname $(readlink -f $0))/..`，`nohup java -jar -Dspring.profiles.active=prod novel-front.jar`，pid 写 `novel-front.pid`，stop 先 `kill` 再 `kill -9`；`novel-front.bat`（Windows 一键启动）只有 `cd /d "%~dp0.."` + `java -jar -Dspring.profiles.active=prod novel-front.jar` + `pause`。
- 与 v3.6 的关键差异：v3.6 启动行是 `java -jar $JAVA_OPTS $JAVA_MEM_OPTS -Dloader.path=conf,lib` 且带 `-Xloggc`、`PrintGCDateStamps` 等 JDK8 GC 参数；v6 全去掉，只传 profile。README 要求解压 `novel-front.zip` 后先 `export JWT_SECRET=...` 再 `bin/novel-front.sh start`。

### 3.4 打包方式结论

| 维度 | v3.6 | v6.0.0 |
| --- | --- | --- |
| jar 形态 | `layout=ZIP` + `includes` 排除第三方 → 瘦 jar | 默认 repackage → **fat jar**；jar 名去版本号（`<artifactId>.jar`，Dockerfile 才能写死） |
| 三方依赖 / loader.path | `maven-dependency-plugin` 拷 `target/lib`→`build/lib`，启动带 `-Dloader.path=conf,lib` | 打进 jar，**无 `lib`、无 loader.path** |
| 配置 | `conf/`（复制 `src/main/resources` 全量） | `config/`（只放 `src/main/build/config/*` + front 的 `application-alipay.yml`、`application-website.yml`） |
| 模板 | 无外置 | front 额外产出 `build/templates/`（`../templates` 全量） |

## 4. 数据模型增量

### 4.1 `doc/sql/` 2023~2026 增量脚本（按文件）

| 文件 | 内容 |
| --- | --- |
| `20230413.sql` | 新建 `website_info`（网站名/域名/SEO 关键词/描述/QQ/深浅色 logo + 审计四字段）并插 1 行；`sys_menu` 新增「网站管理 300/网站信息 301」「友情链接 310~315」「会员管理 400/401」「订单管理 500/501」「小说管理 600~604」及 `sys_role_menu` 授权 |
| `20230418.sql` | `sys_dict` 插 `book_rec_type`（0 轮播图/1 顶部小说栏/2 本周强推/3 热门推荐/4 精品推荐）；`sys_menu` 新增「小说推荐 320~325」「会员反馈 410」 |
| `20230508.sql` | 补「网站信息-修改」按钮权限 305 |
| `20240512.sql` | 纯数据：`crawl_source` id=16 规则里 `ibiquge.net` → `ibiquzw.org` |
| `20250317.sql` | 新增采集源「香书小说网」（JSON 规则，`xbiqugu.la`）；再把 id=16 的规则 `ibiquzw.org` → `biquxs.info`；删菜单 104、57 |
| `20250630.sql` | `book_comment` 加 `location varchar(50)`（地理位置） |
| `20250711.sql` | `crawl_single_task` 加 `crawl_chapters int default 0`（采集章节数） |
| `20250712.sql` | **重建** `book_comment_reply`：加 `location`、`audit_status`（0 待审/1 通过/2 不通过）；注意 `create_time`/`create_user_id` 的 COMMENT 写反了（"回复用户ID"/"回复时间"） |
| `20261013.sql` | 纯数据（无 DDL）：新增采集源「香书小说网（2026）」，域名 `ibiqugu.net` |
| `20261016.sql` | 纯数据（无 DDL）：新增/更新采集源「书趣阁（2026）」，`wap.xshuquge.net` |
| `20261019.sql` | 新建 `user_book_list`（书单，`idx_user_id`）、`user_book_list_item`（条目，`uk_list_book(list_id,book_id)` + `remark` 推荐语）、`book_paragraph_comment`（段评，`book_index_id + paragraph_idx` 定位段落，`root_id` 支持回复，`reply_count` 冗余，`idx_index_paragraph`/`idx_root_id`） |
| `20261020.sql` | 新建 `user_message`（`msg_type` 1 书评被回复/2 段评被回复，`read_flag`，`idx_user_read`/`idx_user_time`）、`ai_creation_plan`（`stage` 1~4、`creative_params`/`plan_content` JSON、`outline_version`、`uk_book`）、`ai_chapter_plan`（`plan_id+chapter_no` 唯一，`status` 0~3，`summary` 作创作记忆）、`ai_creation_task`（`task_type` 1~6，`running_flag` 配 `uk_running(plan_id,task_type,chapter_no,running_flag)` 防重复提交）、`ai_author_pref`（`uk_author`，全局偏好 JSON）；并 `alter table book modify pic_url ... default '/images/default.gif'` |

### 4.2 `novel_plus.sql` 表清单与新增

- 结构：**48 张逻辑表 + 10 张 `book_content0..9` 分表**（`book_content` 为逻辑表），唯一表名 58 个、`CREATE TABLE` 语句 60 条 —— `crawl_single_task`、`book_comment_reply` 各有「旧定义 + `DROP TABLE IF EXISTS` 重建」两份，后者覆盖前者。v3.6 是 39 张逻辑表 + 10 张分表（唯一 49 个），差值正好是下面 9 张新表：

| 新增表 | 归类 |
| --- | --- |
| `website_info` | 站点配置（v4.0 起） |
| `user_book_list` / `user_book_list_item` | 书单广场 |
| `book_paragraph_comment` | 段落评论（含回复，平铺树） |
| `user_message` | 站内消息（书评/段评被回复） |
| `ai_creation_plan` / `ai_chapter_plan` / `ai_creation_task` / `ai_author_pref` | AI 长篇创作助手 |

- 全量脚本在建表段之后**又追加 7 条 ALTER**（第 2819 行起）：`book.yesterday_buy`、`book_index.book_price`、`news.read_count`、`book_index.storage_type`（这 4 条是 v3.x 遗留增量）、`book_comment.location`（3159 行）、`crawl_single_task.crawl_chapters`（3162 行）、`book.pic_url` 改默认值（3424 行）—— 后 3 条与 2025/2026 增量脚本一致，所以 `git show upstream/master:doc/sql/novel_plus.sql` 单独执行即可初始化（`doc/sql/readme.md` 也如此说明）。
- **没有对应新表的三个功能**（易被误判）：敏感词 —— 无词库表，用 `houbb:sensitive-word:0.29.5` 内置词库，`SensitiveWordHelper.replace(...)` 调用点在 `BookServiceImpl`（书评/回复）、`BookParagraphCommentServiceImpl`（段评/昵称）、`UserBookListServiceImpl`（书单名/推荐语）；sitemap —— 无表，`core/schedule/SitemapGenSchedule`（`@Profile("prod")`、`@Scheduled(cron = "0 0 2 * * ?")`）每天 2 点把 `sitemap.xml` 写进 `spring.web.resources.static-locations` 目录；统计图表 —— 无新表，`novel-admin/.../mapper/AdminStatMapper.dailyCount` 用 `${table}` 动态表名做 `date_format(create_time,'%Y-%m-%d') group by` 按天聚合。

## 5. 代码结构变化

统计命令与结果（`git diff --no-renames --name-status 906e7762 upstream/master -- novel-front/src/main/java novel-admin/src/main/java novel-common/src/main/java novel-crawl/src/main/java`）：**340 条变更 = 新增 105 + 删除 164 + 修改 71**。

| 模块 | 合计 | 新增 | 删除 | 修改 |
| --- | --- | --- | --- | --- |
| novel-front | 84 | 40 | 8 | 36 |
| novel-common | 41 | 22 | 3 | 16 |
| novel-admin | 194 | 36 | 151 | 7 |
| novel-crawl | 21 | 7 | 2 | 12 |

### 5.1 新增（按包/职责，路径相对模块 `src/main/java/com/java2nb/`）

- **front · AI**：`novel/core/ai/{AiJsonUtil,ChapterTextCheckUtil,PromptTemplateUtil}.java`、`novel/core/config/AiConfig.java`、`novel/controller/AiAssistantController.java`、`novel/service/AiAssistantService.java` + `service/impl/AiAssistantServiceImpl.java`、`novel/vo/AiPlanProgressVO.java`、`novel/mapper/FrontAi{CreationPlan,ChapterPlan,CreationTask,AuthorPref}Mapper.java`
- **front · 书单/段评/消息**：`controller/{UserBookListController,MessageController}.java`、`service/{UserBookListService,BookParagraphCommentService,UserMessageService,LikeService}.java` + impl、`vo/{BookListVO,BookListItemVO,BookParagraphCommentVO,BookCommentReplyVO,UserMessageVO}.java`、`mapper/Front{UserBookList,BookParagraphComment,BookCommentReply,UserMessage,User}Mapper.java`
- **front · 基础设施**：`core/config/{IpLocationConfig,JwtSecretValidator}.java`、`core/schedule/SitemapGenSchedule.java`、`core/serialize/TimeAgoFormatSerialize.java`、`core/utils/NameMaskUtil.java`、`service/IpLocationService.java` + impl、`controller/page/PageController.java`（原 `novel/page/PageController.java` 迁移）
- **common**：`core/advice/{CommonExceptionHandler,CustomResponseBodyAdvice}.java`、`core/config/HttpProxyProperties.java`、`core/utils/{RestTemplates,SpringUtil}.java`；`entity/{AiAuthorPref,AiChapterPlan,AiCreationPlan,AiCreationTask,BookCommentReply,BookParagraphComment,NewsCategory,UserBookList,UserBookListItem,UserMessage,WebsiteInfo}.java`；`mapper/{BookCommentReply,NewsCategory,WebsiteInfo}{Mapper,DynamicSqlSupport}.java`
- **crawl**：`core/bean/DiskInfo.java`、`core/config/DiskMonitorProperties.java`、`core/schedule/DiskMonitorSchedule.java`、`service/{EmailService,impl/EmailServiceImpl}.java`、`utils/CrawlHttpClient.java`、`controller/page/PageController.java`
- **admin（整包重写，落在 `novel/` 下）**：`novel/AdminApplication.java`、`novel/core/config/{SecurityConfiguration,WebMvcConfig}.java`、`novel/core/utils/AdminUtil.java`、`novel/controller/{BookList,Comment,Member,Message,Order,Website,File,page/PageController}.java`、`novel/mapper/Admin{BookCommentQuery,BookParagraphComment,BookSettingQuery,OrderPayQuery,Stat,UserBookListItem,UserBookList,UserFeedbackQuery,UserMessage}Mapper.java`、`novel/service/*` + impl、`novel/vo/Admin*VO.java`
- **无新增 `api` / `mobile` java 包**：跨端接口是在 v6.0.0 之后的 tip 提交 `e8daac0a feat(api): 提交跨端客户端相关接口` 里加到现有 `BookController`、`NewsController`，并给 front `core/config/WebMvcConfig.java` 增加全局 CORS（`allowedOriginPatterns("*")` + `allowCredentials(true)`）。

### 5.2 删除（能力退场的证据）

- front：`core/config/{EsConfig,RabbitConfig}.java`、`core/listener/BookVisitAddListener.java`、`core/schedule/BookToEsSchedule.java`、`service/SearchService.java` + `impl/SearchServiceImpl.java`、`service/impl/FastDfsFileServiceImpl.java`、`page/PageController.java`；common：`core/cache/impl/EhCacheServiceImpl.java`、`core/advice/PageExceptionHandler.java`、`core/utils/RestTemplateUtil.java`；crawl：`core/schedule/CrawlThreadMonitor.java`（由 `DiskMonitorSchedule` 取代）。
- admin：`com/java2nb/common/**`（Shiro、Redis Session、XSS、Swagger、Druid、velocity 代码生成、`R`/`Query`/`PageBean` 等）与 `com/java2nb/system/**`（菜单/角色/部门/数据权限/会话）整体消失 —— 共 151 个 java 文件。

## 6. 五个重点确认

### 6.1 JWT_SECRET 生产强制

`novel-front/.../core/config/JwtSecretValidator.java`：`@Component @Profile("prod") implements ApplicationRunner`，启动时 `System.getenv("JWT_SECRET")` 为空/空白 → 打 error 日志并 `throw new IllegalStateException("Missing required environment variable: JWT_SECRET")`，**直接终止启动**。
配合 `application.yml` 的 `${JWT_SECRET:}`（无默认值）与 dev 的 `${JWT_SECRET:novel!#20191230}`：dev 免配置、prod 必须显式注入；README 用 `openssl rand -base64 64` 生成并提示「换密钥会使原 token 失效」。注意校验读的是**环境变量**而非 `jwt.secret` 配置项 —— 只改 yml 不设环境变量，prod 下仍启动失败。

### 6.2 连接池统一创建

- 业务 yml 中 `spring.datasource` 只留 `url`（ShardingSphere JDBC 协议）+ `driver-class-name`，**没有 username/password/池参数**；真正的池由 `config/shardingsphere-jdbc.yml` 的 `dataSources.ds_x.dataSourceClassName: com.zaxxer.hikari.HikariDataSource` 统一创建，v3.6 那套 `sharding.jdbc.datasource.ds0.type`（admin 还另有 `DruidDBConfig`）全部退役。
- 收益是「一份分片文件 = 数据源 + 分片规则」，代价是「改数据库要改 `user.dir` 下的 `config/` 文件而不是 jar 内 yml」。

### 6.3 Spring AI 1.0.0

- 根 pom `spring-ai-bom:1.0.0`（`import`）统一版本，front 只引 `spring-ai-starter-model-openai`（1.0.0 的新 artefact 命名，GA 前叫 `spring-ai-openai-spring-boot-starter`）。
- 代码用新 API：`ChatClient`（`AiConfig` 造 Bean）、`ChatClient.Builder`，`AiAssistantServiceImpl` 直接注入 `org.springframework.ai.chat.client.ChatClient`；对接硅基流动的 OpenAI 兼容端点，chat `deepseek-ai/DeepSeek-R1-0528-Qwen3-8B`、image `Kwai-Kolors/Kolors`（`response_format: URL`）。
- 工程化设计（类注释自述）：生成任务落 `ai_creation_task` 表 + 专用线程池异步串行执行，前端轮询任务状态实现断点恢复；正文草稿存 `result`，作者确认后才经 `addBookContent` 写正式章节，`ai_chapter_plan.status` 区分「草稿已生成未保存 / 已保存 / 保存中」。

### 6.4 ShardingSphere 配置外置

- `url: jdbc:shardingsphere:absolutepath:${user.dir}/config/shardingsphere-jdbc.yml` —— `absolutepath:` 前缀表示按**绝对路径**加载 YAML（5.x 的 JDBC URL 协议），文件由 antrun 从 `src/main/build/config/` 拷到发布包 `config/`。
- 升级点：3.0.0（`io.shardingsphere`，Spring Boot starter + 前缀 `sharding.jdbc`）→ 5.5.1（`org.apache.shardingsphere`，独立 driver，走 `spring.datasource.url`）；运维上不再支持「改 jar 内 yml 改分片」，必须改 `config/shardingsphere-jdbc.yml`，且 `${user.dir}` 依赖启动目录（`sh bin/novel-front.sh` 已 `cd` 到上一级，符合预期）。

### 6.5 缓存模块优化

- 删除 `EhCacheServiceImpl` 与 `cache.type` 开关（v3.6 是 `cache.type: ehcache` + `spring.cache.ehcache.config: classpath:ehcache.xml`），`CacheService` 只剩 `RedisServiceImpl`：`StringRedisTemplate` + Jackson `ObjectMapper`（`@PostConstruct` 里 `setSerializationInclusion(NON_NULL)`），提供 `get/set/setObject/getList/del/contains/expire`；`CacheKey` 保留并演进（如 `indexBookSettingsKey:v2` 带版本号，改结构后自然失效）。
- 影响：`RedisServiceImpl` 在 `novel-common` 里是唯一实现，front/admin/crawl 运行期缓存全部走 Redis，没有 Ehcache 纯内存降级路径；Redis 不可用时缓存接口会失败（是否影响启动**未确认**，Bean 创建不触发连接）。`CacheController` + `cache.manager.password` 仍是手动刷缓存入口。

## 7. 风险 / 未确认清单

1. **分片配置四份副本已漂移**：根 `config/shardingsphere-jdbc.yml` 有 `ds_2`（写成 `url:` 而非 Hikari 的 `jdbcUrl:`，指向 `information_schema`）和 `allowPublicKeyRetrieval=true`，三份模块副本都没有；`ds_2` 是否导致 5.5.1 启动建池失败**未确认**。
2. **`Public Key Retrieval is not allowed` 的修复（commit `0e156c04`）只落在根配置**，发布包用的是模块副本 → 部署后是否仍踩该坑**未确认**。
3. **Dockerfile 与 ShardingSphere 的冲突风险**：只覆盖 `spring.datasource.driver-class-name`，`url` 仍是 `jdbc:shardingsphere:absolutepath:`，而容器内没有 `config/shardingsphere-jdbc.yml`（只 COPY jar）→ 默认镜像能否启动**未确认**。
4. **AI api-key 明文入库**：`novel-front/src/main/resources/application.yml` 与 `src/main/build/config/application.yml` 各一把且值不同；同样明文入库的还有 `application-alipay.yml` 商户私钥、`application-oss.yml` key-secret、Redis/MySQL 密码、`admin.password: admin`。
5. **老依赖仍在 Boot 3.4 下跑**：`mysql:mysql-connector-java:8.0.29`（新坐标应为 `com.mysql:mysql-connector-j`）、`spring-boot-starter-redis:1.4.1.RELEASE`；`jjwt 0.9.1`（`setSigningKey(String)` + `SignatureAlgorithm` 旧 API）在 Java 21 上的运行时依赖（是否需 jaxb）**未确认**。
6. **crawl 的 `application-test.yml` 引用 `common-test`**，该 yml 在 v6 树中不存在；**端口冲突**：crawl 部署包 `8083` 与 front 源码默认 `8083` 重叠，同机部署三件套需覆盖 `config/application.yml`。
7. **`book_comment` 结构要看到文件尾部**：`novel_plus.sql` 里 CREATE TABLE 无 `location`，靠末尾 ALTER（第 3159 行附近）补齐，只截取建表语句会漏字段。
8. admin 改为内存用户后，`sys_user`/`sys_role`/`sys_menu`/`sys_dept`/`sys_data_perm` 等 14 张 `sys_*` 表（含代码生成器 3 张 `sys_gen_*`）仍在库中但登录链路已不查表；是否还有残留页面引用**未确认**。

## 8. 面试可讲点（从上面事实直接抽）

- **一次依赖升级就是一次架构重构**：Boot 2.1.8/Java 8 → Boot 3.4/Java 21 连带 `javax→jakarta`、ShardingSphere 3→5、`spring.redis→spring.data.redis`、`spring.profiles.include→spring.config.import`、Shiro→Spring Security；可用「先 `git diff --name-status` 盘删改面，再按 `application*.yml` 收敛配置」的方法论讲。
- **瘦 jar → fat jar 的取舍**：v3.6 用 `layout=ZIP` + `loader.path=conf,lib` 换「改配置/换依赖不重打包」，v6 用 fat jar + 外置 `config/` 换「镜像只 COPY 一个 jar」，两者都能外置配置，v6 少一层 `lib`；配置外置的三种粒度是环境变量（`JWT_SECRET`）、外置目录（`config/`、`templates/`）、外置 profile 文件（`spring.config.import`）。
- **AI 功能的工程底线与可讲的坑**：任务表 + 线程池 + 轮询 + 「草稿 vs 正式章节」状态机，避免大模型调用把 Web 线程拖死、避免半成品污染正文表；`JwtSecretValidator` 读的是 `System.getenv`，只配 `jwt.secret` 不设环境变量在 prod 下照样启动失败；分片配置四份副本已开始漂移（`allowPublicKeyRetrieval` 只修了一份）。
