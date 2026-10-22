# 上游 v6.0.0 调研笔记：新业务功能与 AI 实现

> 调研基线：`upstream/master`，HEAD `e8daac0a`（2026-10-21 22:52，含"提交跨端客户端相关接口"）；版本发布提交 `537027cd`（v6.0.0 发布）。仓库根 `C:\Users\Chen\Documents\deepseek-harness\default-workspace`。
> 说明：本文只写从上游代码确认的事实；标注「未确认」的条目表示仓库内没有足够证据。本文路径均相对仓库根，文件内容均以 `git show upstream/master:<路径>` 读取。调研期间未修改仓库文件、未切换分支。

## 0. 结论速览

- v6.0.0 的 AI 能力分三层：编辑器级（扩写/缩写/续写/润色，Spring AI `ChatClient` 直调）、生成式封面（`OpenAiImageModel`）、**长篇创作助手**（任务化异步生成 + 断点续写，是本版最大新增）。
- 长篇创作助手新增 4 张表：`ai_creation_plan`、`ai_chapter_plan`、`ai_creation_task`、`ai_author_pref`，全部在 `doc/sql/20261020.sql`；生成动作落 `ai_creation_task`，前端每 2.5s 轮询，刷新/重启可恢复。
- 移动端（H5）是 v6 的主战场：书单广场（`user_book_list`/`user_book_list_item`）、段落评论（`book_paragraph_comment`）、消息系统（`user_message`）、UI 重做（green 主题 mobile 模板）。
- 评论增强没有新增点赞表：赞/踩存 Redis Set + Lua 原子切换；回复新增 `book_comment_reply` 表；评论/回复/段评都新增 `location` 字段（ip2region 本地库）。
- 作家端新增"完结""AI 创作入口""移动端语音朗读（纯前端 Web Speech API）"；"小说下载"接口只在 **novel-admin** 模块，移动端按钮的相对路径与前端模块不一致（见 4.3，部署映射未确认）。
- SEO/运营：`SitemapGenSchedule`（仅 prod，每天 2 点）、后台首页 ECharts 增长趋势（`/stat/trend`）、爬虫磁盘监控邮件告警（≥95% 直接退出进程）与随机 UA 池。
- ⚠️「会员注册自动生成随机昵称」在 v6.0.0 **并不存在**：提交 `23ec63ef` 加入，随后 `b0c3f4d1` 回滚，早于 v6.0.0 发布提交。当前注册仍是 `nickName = username`（详见 5.3）。

---

## 1. AI 功能

### 1.1 Spring AI 集成方式

| 项 | 事实 | 证据 |
| --- | --- | --- |
| BOM | `spring-ai-bom` **1.0.0**，Spring Boot 3.4.0 / Java 21 | `pom.xml`（根） |
| starter | `spring-ai-starter-model-openai`（仅 novel-front 引入） | `novel-front/pom.xml` |
| 对话模型 | `deepseek-ai/DeepSeek-R1-0528-Qwen3-8B` | `novel-front/src/main/resources/application.yml` |
| 生图模型 | `Kwai-Kolors/Kolors`，`response_format: URL` | 同上 |
| 服务商 | 硅基流动 `https://api.siliconflow.cn`（OpenAI 兼容协议） | 同上 |
| 客户端 | `AiConfig` 注册 `ChatClient` Bean；自定义 `RestClient.Builder`（连接 5s / 读取 60s） | `novel-front/src/main/java/com/java2nb/novel/core/config/AiConfig.java` |
| 生图客户端 | `OpenAiImageModel` 由 starter 自动装配，`BookServiceImpl` 直接注入 | `novel-front/src/main/java/com/java2nb/novel/service/impl/BookServiceImpl.java` |

配置里 `api-key` 是明文硬编码（`sk-...`），面试可当安全问题讲：应改为环境变量/配置中心。

### 1.2 章节编辑器的 AI 扩写 / 缩写 / 续写 / 润色

入口：作家后台"发布章节/更新章节"页工具栏，模板 `novel-front/src/main/resources/templates/author/content_add.html`（`content_update.html` 同源），按钮 `data-type="stream/expand|condense|continue|polish"`，用 `EventSource` 消费 SSE。

接口（`novel-front/src/main/java/com/java2nb/novel/controller/AuthorController.java`）：

| 能力 | 同步接口 | 流式接口（SSE，`text/event-stream`） |
| --- | --- | --- |
| 扩写 | `POST /author/ai/expand`（`text`、`ratio`） | `GET /author/ai/stream/expand` |
| 缩写 | `POST /author/ai/condense`（`text`、`ratio`） | `GET /author/ai/stream/condense` |
| 续写 | `POST /author/ai/continue`（`text`、`length`） | `GET /author/ai/stream/continue` |
| 润色 | `POST /author/ai/polish`（`text`） | `GET /author/ai/stream/polish` |

实现要点：
- **没有独立 Service/Prompt 模板**，提示词在 Controller 里字符串拼接，例如 `"请将以下文本扩写为原长度的" + ratio/100 + "倍：" + text`；流式接口返回 `Flux<String>`，非流式走 `chatClient.prompt().user(prompt).call().content()`。
- 前端把 `EventSource.onmessage` 的内容直接追加进 `textarea#bookContent`，结束时 `close()`；续写长度用 `layer.prompt` 收集（默认 200 字）。
- 数据流：编辑器选中文本 → `encodeURIComponent` 拼 URL → SSE 逐段返回 → `event.data` 追加到 textarea → 作者手工确认后走原有 `addBookContent` 保存。
- ⚠️ 这 8 个接口都**没有调用 `checkAuthor(request)`**（同文件其他接口有），代码层面未见作者身份校验；是否有网关/过滤器兜底未确认。

### 1.3 AI 生成封面图

入口：作者发布小说 `POST /author/addBook`。若未上传本地封面（`picUrl` 为空或不以 `/localPic/` 开头），异步生成。

- 关键类/配置：`BookServiceImpl.addBook`（`novel-front/src/main/java/com/java2nb/novel/service/impl/BookServiceImpl.java`）、`OpenAiImageModel`、`application.yml` 的 `spring.ai.openai.image`。
- Prompt：`生成一本小说的封面图片，图片中间显示书名《%s》，书名下方显示作者“%s 著”。`
- 参数：`quality=hd`、`width=600`、`height=800`；返回 `ImageResponse.getResult().getOutput().getUrl()`。
- 存储流程（5 步）：
  1. `bookMapper.insertSelective` 先落库，拿到 `book.id`；
  2. 异步线程调用生图模型，得到临时 URL；
  3. `FileUtil.downloadFile(url, picSavePath + picUrl)` 下载到本地，路径规则 `/localPic/aiGen/yyyy/MM/dd/{bookId}.png`（`Constants.LOCAL_PIC_PREFIX = "/localPic/"`，`pic.save.path` 由配置给出）；
  4. `update book set pic_url = ...`；
  5. `cacheService.set("aiGenPic"+bookId, picUrl, 3600)`，前端轮询 `GET /author/queryAiGenPic?bookId=` 取缓存值（1 小时过期）。
- 表：仅 `book.pic_url`；`doc/sql/20261020.sql` 末尾把 `pic_url` 放宽到 `varchar(200)` 并给默认值。
- 风险：异步 lambda 未捕获异常（生图失败时 `pic_url` 保持空）；API Key 明文。

### 1.4 AI 长篇创作助手（核心新增）

入口：作家后台菜单「AI创作助手」→ `/author/ai_assistant.html`；「我的小说」列表单本「AI创作」→ `/author/ai_assistant.html?bookId={id}`。页面源码 `novel-front/src/main/resources/templates/author/ai_assistant.html`；受 `PageController` 的 `/author` 登录+作者身份拦截保护。

#### 1.4.1 接口清单（`AiAssistantController`，前缀 `/author/aiAssistant`）

| 接口 | 作用 |
| --- | --- |
| `POST initPlan` | 初始化/恢复方案：传 `planId` 直接加载；传 `bookId` 绑定现有小说；都不传则复用最近未绑定方案，否则新建（支持断点续写） |
| `POST saveParams` | 保存问答参数 JSON（校验 `genre/coreIdea/protagonist/conflict` 必填，章节数默认 60 限 1~1000，单章字数默认 3000 限 200~20000，总长 ≤8000） |
| `POST startTask` | 提交异步任务，返回 taskId（`taskType`：1 书名 2 方案 3 正文 4 校验修订 6 章节规划增量；5 摘要仅系统内部触发） |
| `GET task/{taskId}` | 轮询任务状态与结果（含 12 分钟静默超时兜底） |
| `GET progress` | 页面恢复：方案 + 章节计划 + 执行中任务 + 最近 15 条任务摘要（不含正文） |
| `POST savePlanContent` | 保存编辑后的方案草稿（JSON 结构校验 + 章节序号重排 + ≤150000 字符） |
| `POST confirmPlan` | 确认方案：新建小说（走 `bookService.addBook`，含同名校验与 AI 封面）并拆分章节规划 |
| `POST updateChapterPlan` | 改单章规划（仅未保存章节） |
| `POST saveDraft` | 把作者手工编辑内容落为服务端草稿（以 task_type=3、status=1 的记录保存） |
| `POST saveChapter` | 确认保存到现有章节体系（`bookService.addBookContent`） |
| `POST programCheck` | 程序化校验（字数 + 重复段落） |
| `GET/POST pref`、`savePref` | 作者全局创作偏好（`ai_author_pref`，≤4000 字符 JSON） |

所有接口先 `checkAuthor`（未登录 → `NO_LOGIN`；作者封禁 → `AUTHOR_STATUS_FORBIDDEN`），Service 层再用 `author_id` 做数据隔离。

#### 1.4.2 数据模型（`doc/sql/20261020.sql`）

| 表 | 关键字段 | 说明 |
| --- | --- | --- |
| `ai_creation_plan` | `author_id`、`book_id`(唯一)、`stage`、`creative_params`、`plan_content`、`outline_version` | 一个作者/一本书一份方案 |
| `ai_chapter_plan` | `plan_id+chapter_no` 唯一、`index_name`、`chapter_outline`(JSON)、`status`、`index_id`、`word_count`、`summary` | 章节规划 + 创作记忆摘要 |
| `ai_creation_task` | `task_type`、`chapter_no`、`status`、`running_flag`、`result`(longtext)、`error_msg` | 唯一键 `uk_running(plan_id,task_type,chapter_no,running_flag)` 防重复提交 |
| `ai_author_pref` | `author_id` 唯一、`pref_content` | 跨作品偏好，注入所有 prompt 的 `{pref}` |

#### 1.4.3 状态机

- 方案 `stage`：`1 创作问答 → 2 方案草稿 → 3 方案已确认`；实体注释里的 `4 创作完成` 在代码中没有写入点（未确认是否废弃）。
- 章节 `status`：`0 待创作 → 1 草稿 → 2 已保存`；`3 保存中` 是事务内瞬时态（CAS `0/1 → 3`，成功后 `3 → 2`）。
- 任务 `status`：`0 执行中 → 1 成功 / 2 失败`；`running_flag` 执行中为 1、结束置 NULL。

#### 1.4.4 完整工作流（与 README「AI 长篇创作助手」一节一致）

1. **创意问答**：填写题材/核心创意/主角/核心冲突，可「随机灵感」（前端 `IDEAS` 数组随机填表）或「使用默认参数」；深度设定（世界观、文风、目标读者、章节数、每章字数）可跳过 → `saveParams`。
2. **书名建议**：`startTask type=1` → prompt `book_name.txt`（8 个书名 + 一句理由，限 12 字）→ `ai_creation_task.result` 存 `{"names":[...]}`；前端 `renderNameChips` 点击回填。
3. **创作方案**：`startTask type=2` → prompt `creative_plan.txt` 生成：`bookName/sellingPoints/targetReaders/intro/worldview/characters/mainOutline(五段)/volumes/foreshadows/chapters`。首轮最多 40 章（`MAX_FIRST_PLAN_CHAPTERS`），超出用 `type=6` 增量（每批 30 章，`CHAPTER_PLAN_BATCH_SIZE`）继续；草稿可保存/重生成，确认前不写章节。
4. **逐章创作**：`confirmPlan` 创建/绑定小说并批量写 `ai_chapter_plan`；`startTask type=3` → `chapter_content.txt`。上下文由 `buildChapterVars` 组装：简介 800、世界观 2000、人物 2500、总纲 1500、分卷 1200、未回收伏笔 ≤8 条、最近 5 章摘要（2000）、上一章结尾 500 字、本章规划 1200、目标字数；作者偏好 500 字。
5. **校验修订**：`startTask type=4` → 循环最多 3 轮（`MAX_REVISE_ROUNDS`）：程序校验（`ChapterTextCheckUtil`）+ AI 责编校验（`chapter_check.txt`，6 个检查项，输出 `passed/issues`），不通过则把问题清单交给 `chapter_revise.txt` 重写；最后一轮仍不通过就保留当前版本交作者处理。结果 JSON：`{passed,rounds,issues,content}`。
6. **确认保存**：`saveChapter` → `casMarkSaving` → `convertText`（`\n→<br>`、空白→`&nbsp;`）→ `ChapterTextCheckUtil.validWordCount` → `bookService.addBookContent` → 回查最新章节 `index_id` → `markSaved`；事务提交后（`TransactionSynchronization.afterCommit`）异步触发 `type=5` 摘要，写回 `ai_chapter_plan.summary`，失败降级为程序截取 120 字。
7. **断点续写**：`progress` 返回方案/章节/执行中任务；前端若发现有 running 任务则恢复 2.5s 轮询；正文草稿存在 `ai_creation_task.result`（正文任务纯文本，校验任务 JSON 的 `content`），`latestDraftTask` 优先取较新的校验结果；进程重启时 `ApplicationReadyEvent` 把遗留 running 任务批量置失败以释放唯一键。

#### 1.4.5 Prompt 组织

- 目录：`novel-front/src/main/resources/prompts/ai-assistant/`，共 7 个模板：`book_name.txt`、`creative_plan.txt`、`chapter_plan_batch.txt`、`chapter_content.txt`、`chapter_check.txt`、`chapter_revise.txt`、`chapter_summary.txt`。
- 加载器：`core/ai/PromptTemplateUtil.java`，`ConcurrentHashMap` 缓存 classpath 文本，正则 `\{([a-zA-Z][a-zA-Z0-9_]*)\}` 单次扫描替换，缺省填「未提供」，变量值中的占位符不会被二次展开。
- 解析兜底：`core/ai/AiJsonUtil.java` 去 markdown 围栏、截取首个 `{` 到最后一个 `}` 再反序列化；`validateNames/validatePlan/validateChapters/validateCheck` 做结构校验；`truncate` 统一控制上下文长度。
- 调用方式：`chatClient.prompt().user(prompt).stream().content().collectList().block(Duration.ofMinutes(10))`——对模型是流式，但对任务是聚合等待，避免长文本读超时；专用线程池 `aiTaskExecutor`（core 1 / max 2 / queue 30 / AbortPolicy）与页面渲染线程隔离。

#### 1.4.6 字数 / 一致性校验规则

- 程序校验（`core/ai/ChapterTextCheckUtil.java`）：有效字数沿用 `StringUtil.getStrValidWordCount`；<200 字直接告警；低于目标 70% 或高于 150% 告警；重复段落检测以 ≥15 字为一段，重复段落占比 >12%（且段落数 ≥5）告警；`fallbackSummary` 用于摘要降级。
- AI 校验（`chapter_check.txt`）：是否完成本章规划、人物行为/知识/能力一致性、与前文事实/时间线/世界观冲突、重复与注水、与上一章衔接、字数是否在 ±30%——注意 prompt 写 ±30%，代码程序校验是 70%~150%，两者口径**不完全一致**（可当实现瑕疵讲）。

#### 1.4.7 幂等与并发

- 提交任务靠 `uk_running` 唯一索引 + `DuplicateKeyException → AI_TASK_RUNNING` 拒绝重复；保存章节靠 `casMarkSaving`（`status in (0,1)`）保证同一章只成功一次；`confirmPlan` 只重建未保存章节（`deleteUnsaved` + `batchInsert`），已保存章节不动；`outlineVersion` 每次确认 +1。

---

## 2. 移动端（mobile）新增

移动端是同一套 Thymeleaf 的 `mobile/` 模板（`ThreadLocalUtil` + `NovelFilter` 按 UA/`to=mobile` 切换模板目录）；生产模板主题 `templates.name: green`，源码在 `novel-front/src/main/resources/templates/mobile/`，打包时由 `novel-front/pom.xml` 的 antrun 复制到 `templates/green/html`。

### 2.1 移动端 UI 重做

- 提交：`efc589a1 feat(mobile): 重新设计移动端UI`（26 个文件）+ 后续 `4a667a5c`（首页）、`251211e8`（筛选页）、`67e6d10d`（排行榜）、`da024491`（个人中心）。
- 视觉：主色 `#3eaf7c`，页头 `mobile/common/header.html`（sticky + 绿色渐变 + 返回/首页 SVG），页尾 `mobile/common/footer.html`（首页/排行榜/阅读记录/书架/回顶部固定导航），卡片化列表（书单卡、书卡）、layui 保留但样式重写。
- 覆盖页面：`mobile/index.html`、`book/*`（详情、目录、正文、排行、分类）、`user/*`（登录、注册、个人中心、书架、阅读记录、书评、段评、消息、设置）、`pay/index.html`、`booklist/*`。
- 入口 URL 不变（`/book/{bookId}.html`、`/user/userinfo.html` 等），由 `PageController` 统一返回 `ThreadLocalUtil.getTemplateDir() + ...`。

### 2.2 书单广场

- 入口：`/booklist/plaza.html`（广场）、`/booklist/mine.html`（我的）、`/booklist/detail-{listId}.html`（详情）；移动端首页/个人中心有入口。PC 无对应 `booklist` 模板（未确认是否移动端专属）。
- 接口（`novel-front/src/main/java/com/java2nb/novel/controller/UserBookListController.java`，前缀 `/bookList`）：`plaza`、`mine`、`detail`、`create`、`update`、`delete`、`addBook`、`removeBook`。
- 关键类：`UserBookListService(Impl)`、`FrontUserBookListMapper(.xml)`、`BookListVO`/`BookListItemVO`；详情会回填 `isMyList`，列表按 `book_count desc, create_time desc` 排序（广场）。
- 表：`user_book_list`（软删 `status`、冗余 `book_count`）、`user_book_list_item`（`uk_list_book` 唯一）；SQL 在 `doc/sql/20261019.sql`。
- 数据流：读者在书详情点「加书单」→ `GET /bookList/mine?limit=200` 选书单 → `POST /bookList/addBook`（推荐语过敏感词、`book_count+1`）→ 广场/我的列表分页展示 → 详情聚合 `user_book_list_item join book`。
- 管理端：`novel-admin` 的 `BookListController`（`/bookList/bookList/list`、`/item/list`…），页面 `/bookList/bookList.html`、`/bookList/bookListItem.html`。

### 2.3 段落评论

- 入口：移动端阅读页 `/book/{bookId}/{bookIndexId}.html`，`mobile/book/book_content.html`：把整章 HTML 按 `<br>/<p>/<div>` 拆成段落（`splitParagraphs`），每段右浮气泡显示评论数。
- 接口（`BookController`）：`GET /book/listParagraphCommentCounts`、`GET /book/listParagraphComment`、`POST /book/addParagraphComment`。
- 关键类：`BookParagraphCommentService(Impl)`、`FrontBookParagraphCommentMapper(.xml)`、`BookParagraphComment`/`BookParagraphCommentVO`。
- 表 `book_paragraph_comment`（`doc/sql/20261019.sql`）：`book_index_id + paragraph_idx` 索引、`root_id` 两级树（0=顶层）、`reply_count` 冗余、`reply_user_name`、`location`。
- 数据流：前端拆段 → 拉 `paragraphIdx→count` 映射 → 点气泡拉该段评论（倒序顶层 + 正序回复）→ 提交评论（≤200 字、敏感词替换、记录 IP 归属地）→ 回复校验根评论同段落后写入并 `reply_count+1` → 通知被回复人（`user_message.msg_type=2`）。列表 SQL `limit 200`。

### 2.4 消息系统

- 入口：`/user/message.html`；个人中心菜单与首页右上角铃铛显示未读数角标（>99 显示 `99+`）。
- 接口（`novel-front/src/main/java/com/java2nb/novel/controller/MessageController.java`，前缀 `/user/message`）：`listByPage`（可按 `msgType` 过滤）、`unreadCount`、`read`、`readAll`。
- 关键类：`UserMessageService(Impl)`、`FrontUserMessageMapper(.xml)`、`UserMessageVO`。
- 表 `user_message`（`doc/sql/20261020.sql`）：`msg_type` 1 书评被回复 / 2 段评被回复 / 3 系统通知，`book_index_id` 用于段评跳转定位，`target_id` 存被回复主评论，`read_flag`。
- 触发点：`BookServiceImpl.addBookCommentReply`（书评）、`BookParagraphCommentServiceImpl.addParagraphComment`（段评，优先 `replyUserId`，缺省根评论作者，自己回复自己不通知）；管理端 `novel-admin` 的 `MessageController` + `/message/userMessage.html` 可人工发系统通知（强制 `msgType=3`、`sendUserId=1`、`targetId=0`）。
- 数据流：回复落库 → 组装 `UserMessage`（内容摘要压缩空白、截 200 字）→ 插入 → 前台分页 `left join user/book/book_index` → 点击标记已读 / 全部已读。

### 2.5 跨端客户端接口（发布后追加）

- `e8daac0a feat(api): 提交跨端客户端相关接口`：
  - `WebMvcConfig` 新增全局 CORS（`allowedOriginPatterns("*")`、含 `allowCredentials(true)`），注释明确用于 `uni-app` 跨端客户端。
  - `BookController` 新增 `GET /book/queryBookIndexContent/{indexId}`：返回章节元信息 + 上下章 ID + `needBuy`，未购买不返回正文。
  - `NewsController` 新增 `GET /news/detail/{newsId}`。
  - `ResponseStatus` 新增 `INDEX_NOT_EXISTS(5002)`、`NEWS_NOT_EXISTS(5003)`。
- 说明：该目录下没有 uni-app 工程源码，跨端客户端本身不在本仓库（未确认）。

## 3. 评论增强

### 3.1 点赞 / 点踩

- 接口：`POST /book/toggleCommentLike`、`/book/toggleCommentUnLike`、`/book/toggleReplyLike`、`/book/toggleReplyUnLike`（`BookController`）。
- 实现：`LikeServiceImpl` 用 Redis Set + Lua 脚本原子切换（`SISMEMBER → SREM/SADD → SCARD`），key 前缀 `like:comment:`、`unlike:comment:`、`like:comment:reply:`、`unlike:comment:reply:`；**不落库**，列表查询时 `BookServiceImpl.listCommentByPage` / `listCommentReplyByPage` 逐条回填 `likesCount/unLikesCount`。
- 数据流：用户点击赞/踩 → 携带登录用户 ID 调 toggle 接口 → Lua 原子增删 Set 成员并返回最新计数 → 前端更新数字，刷新后从 Redis 重算。
- 风险：N+1 Redis 调用；计数只存 Redis，未做持久化/重建（Redis 丢数据则赞数归零，未确认是否有补偿）。

### 3.2 评论回复

- 表 `book_comment_reply`（`doc/sql/20250712.sql`，此前版本可能已存在，本次为重建脚本）：`comment_id`、`reply_content`、`location`、`audit_status`、`create_user_id`。
- 接口：`GET /book/listCommentReplyByPage`、`POST /book/addCommentReply`；页面 `/book/reply-{commentId}.html`（PC）与移动端 `novel-front/src/main/resources/templates/mobile/book/book_comment_reply.html`。
- 数据流：回复内容敏感词替换 → 插入 → `book_comment.reply_count+1` → 发 `user_message`（排除自己）→ 回复列表回填赞/踩数。

### 3.3 地理位置

- 依赖 `org.lionsoul:ip2region:2.7.0`；`IpLocationConfig` 把 `classpath:ip2region.xdb` 读入内存构造线程安全 `Searcher`（destroyMethod=close）；`IpLocationServiceImpl` 解析 `国家|0|省|市|运营商`：中国取省（去掉末尾"省"），非中国取国家，内网 IP 先取公网出口 IP 再查，异常返回「未知地区」。
- 写入点：`BookController.addBookComment`、`addCommentReply`、`addParagraphComment` 统一 `comment.setLocation(ipLocationService.getLocation(IpUtil.getRealIp(request)))`。
- 数据流：发表评论/回复/段评 → `IpUtil.getRealIp` 取真实 IP → `Searcher.search` 得到 region 串 → 解析省/国家 → 写入 `location` → 页面拼接「xx读者」。
- 表字段：`book_comment.location`（`doc/sql/20250630.sql`）、`book_comment_reply.location`、`book_paragraph_comment.location`；展示为「xx读者」。

### 3.4 敏感词过滤

- 依赖：`com.github.houbb:sensitive-word:0.29.5`（`novel-front/pom.xml`），使用 `SensitiveWordHelper.replace(...)` 做替换式脱敏。
- 覆盖点：书评、书评回复、段评内容/被回复人昵称、书单名/简介/推荐语（`BookServiceImpl`、`BookParagraphCommentServiceImpl`、`UserBookListServiceImpl`）。
- 词库/算法：仓库内**没有**自定义词表、没有配置类、没有敏感词表；使用库默认词库与库内部匹配算法（具体算法未在代码中体现，通常为 DFA/Trie，未确认）。面试时建议表述为"接入开源敏感词库做默认词库替换，未做业务自定义词库"。
- 注意：`SensitiveWordHelper.replace` 只替换不拦截，命中后仍会入库（替换字符由库默认实现决定，代码未显式指定）。

## 4. 作家端新功能

### 4.1 作品完结

- 入口：作家后台「小说管理」列表的「设为完结」→ `POST /author/finishBook`（`AuthorController.finishBook`）。
- 实现：`BookServiceImpl.finishBook` 一条 UPDATE，`book_status=1`，`where id=? and author_id=?`；页面二次确认「该操作不可逆」。
- 数据流：点击 → 确认弹层 → 请求 → 更新 `book.book_status` → 列表/详情/书单/排行按 `book_status` 展示"已完结"；没有章节级联动（不自动补完、不锁定章节）。

### 4.2 语音播放（TTS）

- **纯前端**，无后端 TTS 接口、无音频文件、无语音表。
- 位置：移动端阅读页 `novel-front/src/main/resources/templates/mobile/book/book_content.html`（`speakChapter/speak/getSpeakText`），使用浏览器 `window.speechSynthesis` + `SpeechSynthesisUtterance`：`lang=zh-CN`、`rate=0.5`、`pitch=1`；支持暂停/继续，`beforeunload` 时 `cancel`。
- 数据流：点击朗读 → `getSpeakText` 聚合段落文本 → `SpeechSynthesisUtterance` 设置 zh-CN/0.5 语速 → `speechSynthesis.speak` → 再次点击 pause/resume，离开页面 cancel。
- 只朗读 `#paragraphList .para-text`（排除段落评论按钮），若为空则回退 `#chaptercontent` 整章文本。
- 限制：依赖浏览器语音包，iOS/桌面支持度不一；无服务端缓存与音色选择。

### 4.3 小说下载

- 管理端：`novel-admin` 的 `GET /book/download?bookId=`（`novel-admin/src/main/java/com/java2nb/novel/controller/BookController.java`）直接写响应流（`Content-Disposition: attachment; filename*=UTF-8''书名.txt`），避免被全局 `ResponseBodyAdvice` 序列化；`BookService.bookDownload` 按 `index_num` 遍历 `book_index`，拼 `书内容` 后 `htmlToText`（去标签、`&nbsp;`→空格、压缩 3+ 空行）。
- 移动端：书详情页「下载TXT」按钮 `location.href = '/book/download?bookId=...'`（`novel-front/src/main/resources/templates/mobile/book/book_detail.html`）。
- ⚠️ 不一致：`novel-front` 中**没有** `/book/download` 映射（全仓仅 novel-admin 有），而按钮是相对当前域的路径。若前台与后台不同域/端口，需要 Nginx 反代或前端补接口；仓库内未见该映射（部署方式未确认）。

### 4.4 AI 创作助手入口

- 菜单：所有作家后台页面顶部导航「AI创作助手」→ `/author/ai_assistant.html`。
- 单本入口：`/author/index.html` 列表每行「AI创作」→ `/author/ai_assistant.html?bookId={bookId}`，`initPlan` 会校验小说归属后绑定。
- 章节管理页可跳 `content_update.html` 继续人工修改；AI 只负责生成与草稿，正式写入仍走 `addBookContent`。

### 4.5 管理后台重构（背景）

- `4787f113 refactor: 重构管理后台`：删除旧 `com.java2nb.common.*`（Shiro/代码生成/字典等）与大量旧页面，`novel-admin/pom.xml` 改为 `spring-boot-starter-security`；`SecurityConfiguration` 用内存管理员 + BCrypt，`/login.html` 表单登录，其余请求需 `ROLE_ADMIN`；新增 `admin/index.html`、`menu.html` 与书单/段评/消息管理页。

## 5. SEO / 运营

### 5.1 sitemap.xml 自动生成

- 类：`novel-front/src/main/java/com/java2nb/novel/core/schedule/SitemapGenSchedule.java`，`@Profile("prod")`，`@Scheduled(cron = "0 0 2 * * ?")`。
- 依赖：`spring.web.resources.static-locations` 必须是 `file:` 前缀（prod 配置为 `file:${user.dir}/templates/${templates.name}/static/`），把 `sitemap.xml` 写到该静态目录，理论上可由静态资源路径 `/sitemap.xml` 访问（线上 Nginx 是否另做前缀未确认）。
- 数据流：首页访问时 `PageController.index` 把站点根 URL 写入 `CacheKey.WEB_SITE_ROOT_URL` → 定时任务读取根 URL（为空则直接返回）→ 按 `create_time desc` 每批 100 本、`word_count>0` 游标翻页 → 跳过无 `last_index_update_time` 的书 → 输出 `<loc>/book/{id}.html</loc>`、`<lastmod>`（yyyy-MM-dd）、`changefreq=daily`、`priority=0.8` → 写 `</urlset>`。
- 风险：依赖"有人访问过首页"才有根 URL，否则静默不生成；无 `robots.txt`、无分页 sitemap（书多时单文件会很大）。

### 5.2 首页统计图表

- 后台首页 `novel-admin/src/main/resources/templates/admin/index.html`：ECharts 5.5.1（unpkg CDN）折线图，可切近 7/30/90 天。
- 接口：`GET /stat/trend?days=`（`StatController`）→ `StatService.trend`：`days` 非法或超出 7~90 回退 30；白名单表 `book`、`user`、`order_pay`（防 SQL 注入，XML 用 `${table}` 但值来自 Map 白名单）；按天 `date_format(create_time,'%Y-%m-%d')` 分组计数，缺失日期补 0，返回 `{dates, book, user, order}`。
- 爬虫管理端另有 `crawl/index.html` 的柱状图/饼图（ECharts 5.4.3，统计采集源任务），属于同类运营可视化。

### 5.3 会员注册随机昵称（⚠️ 已回滚，v6.0.0 不含）

- `23ec63ef feat(novel-front): 会员注册自动生成初始随机昵称` 曾把 `UserServiceImpl.register` 的 `nickName=username` 改为 `书友 + 6 位随机数`（`ThreadLocalRandom.nextInt(100000,1000000)`）。
- 随后 `b0c3f4d1 Revert "feat(novel-front): 会员注册自动生成初始随机昵称"` 完整回滚；两个提交都早于 `537027cd v6.0.0 发布`。
- 当前 `upstream/master` 的 `novel-front/src/main/java/com/java2nb/novel/service/impl/UserServiceImpl.java` 仍是 `entity.setNickName(entity.getUsername())`；注册页 `/user/register` 只收 `username/password/velCode`。
- 替代方案是「展示脱敏」：`NameMaskUtil.maskIfNeeded` 对手机号昵称打码（`138****1234`，空值显示「匿名用户」），由 `CommentUserNameSerialize` 在书评/段评/书单/消息 VO 序列化时统一调用（提交 `62b2507e`）。面试时不要把"随机昵称"说成 v6.0.0 已上线功能，可讲"曾实现后回滚，最终采用展示层脱敏"。

### 5.4 爬虫磁盘保护 / 邮件告警 / 动态 UA

- 磁盘监控：`novel-crawl/src/main/java/com/java2nb/novel/core/config/DiskMonitorProperties.java`（`disk-monitor.*`：enabled、interval-minutes、warning/severe/critical-threshold、recipients）+ `core/schedule/DiskMonitorSchedule.java`，`@ConditionalOnProperty(enabled=true)`，`fixedDelay = interval-minutes`：
  - 遍历 `File.listRoots()` 计算使用率；`≥85%` 发 INFO、`≥90%` 发 WARNING、`≥95%` 发 CRITICAL；
  - CRITICAL 用 `AtomicBoolean` 防重复，发邮件后 `Thread.sleep(10s)` 再 `System.exit(1)`（注释写"关闭爬虫程序"）；
  - 邮件：`EmailServiceImpl` 用 `JavaMailSender` + Thymeleaf 模板 `novel-crawl/src/main/resources/templates/disk_alert.html`（磁盘表格、按级别着色），`spring.mail.*` 在 `novel-crawl/src/main/resources/application.yml`。
  - 默认 `enabled: false`，阈值 85/90/95，接收人示例为占位邮箱。
- 动态 UA：`novel-common/src/main/java/com/java2nb/novel/core/utils/HttpUtil.java` 内置 8 条桌面/移动浏览器 UA（Chrome/Firefox/Safari/Android/iPhone），`ThreadLocalRandom` 随机选一条写入 `user-agent`，供 `CrawlHttpClient` 与爬虫规则测试复用；字符集维度缓存 `RestTemplate`。
- 采集侧新增字段：`doc/sql/20250711.sql` 给 `crawl_single_task` 增加 `crawl_chapters`（采集章节数量）。

---

## 6. 未确认 / 风险清单（面试可展开）

- **未确认**：编辑器 8 个 AI 接口是否有网关层鉴权（Controller 内无 `checkAuthor`）。
- **未确认**：移动端「下载TXT」相对路径 `/book/download` 在生产如何路由到 novel-admin（仓库内 novel-front 无该映射）。
- **未确认**：`ai_creation_plan.stage=4`（创作完成）无写入点，可能是预留状态。
- **未确认**：跨端（uni-app）客户端源码不在本仓库；`doc/` 中无独立 API 文档。
- **风险**：AI API Key 明文写在 `application.yml`；仓库配置未见重试/熔断，任务失败仅置 `status=2` 由作者重试。
- **风险**：点赞/点踩存 Redis，未持久化；列表逐条查 Redis 存在 N+1。
- **风险**：AI 校验 prompt 的 ±30% 与程序校验 70%~150% 口径不一致。
- **风险**：`confirmPlan` 新建小说会走 `addBook` 的 AI 封面异步流程，生图失败无补偿，封面为空。

---

### 附：v6.0.0 相关提交（上游 `git log`）

- `15716638` AI创作助手、`2c92b106` 消息系统、`170a8f4b` 书单广场、`3263048c` 段落评论、`efc589a1` 移动端 UI、`4787f113` 管理后台重构。
- `23ec63ef`+`b0c3f4d1`（随机昵称先加后回滚）、`62b2507e`（昵称展示脱敏）。
- `537027cd` v6.0.0 发布、`e8daac0a` 跨端客户端接口。
