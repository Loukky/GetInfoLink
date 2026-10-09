# GetInfoScan — 魔兽世界 ID 区段批量扫描器

填入**起始 ID** 和**结束 ID**，一次扫描整个区段里的**物品 / 任务 / 法术 / 成就**，把存在的条目连同 ID、名称和可点击的超连结一起收集起来，支持**复制**和**导出**。

这是一个**纯客户端**插件：不依赖任何第三方数据库，不联网，不读别人的资料库，所有数据都来自客户端自身的 API。
导出的 `ID + 名称` 可以直接用来**补全或校对自己的数据库**（例如 QuestieDB 之类）。

- 适配客户端：`Interface 38002`（Titan ，`GetBuildInfo` 报 `3.80.2`），语言 `zhCN`
- 作者：**Loukky**
- 内置语言：简体中文 / 繁體中文 / English（缺 key 自动回退）
- 依赖：`LibStub`、`CallbackHandler-1.0`、`AceGUI-3.0`（已随插件内置，无需另装）

---

## 目录

- [它解决什么问题](#它解决什么问题)
- [功能一览](#功能一览)
- [安装](#安装)
- [快速上手](#快速上手)
- [界面说明](#界面说明)
- [复制与导出的格式](#复制与导出的格式)
- [导出文件在哪里](#导出文件在哪里)
- [斜杠命令](#斜杠命令)
- [扫描引擎是怎么工作的](#扫描引擎是怎么工作的)
- [存档结构（SavedVariables）](#存档结构savedvariables)
- [兼容性与已知限制](#兼容性与已知限制)
- [常见问题](#常见问题)
- [目录结构](#目录结构)
- [开发说明](#开发说明)
- [English](#english)
- [授权](#授权)

---

## 它解决什么问题

想查某个 ID 到底存不存在、叫什么名字，通常只能：

- 在游戏里一个一个敲 `/run print(GetItemInfo(12345))`，慢且不能批量；
- 或者去 wowhead 之类网站查——但**私服的 ID 表和官方不一致**，网站的数据未必是你这个服的。

GetInfoScan 把这件事变成一次扫描：给一个区段，它把客户端**真正认得**的条目全部列出来，并给出 ID + 名称 + 连结。
判断"这个服到底有没有这个 ID"、"这个区段里有多少个是空的"，几秒钟就能扫完。

## 功能一览

- **4 种类型**：物品、任务、法术、成就，各自独立扫描（类型不通用，ID 空间也完全不同）
- **区段扫描**：`起始 ID` ~ `结束 ID`，单次最多 100,000 个 ID，结果上限 5000 条
- **实时进度**：扫描中进度条和结果列表持续刷新，不用等扫完才看到东西
- **暂停 / 继续 / 停止**：随时中断，已扫到的结果保留
- **结果列表**：`ID` + `连结` 两列；鼠标悬停显示该条目的游戏内提示框；**左键点击**把连结送进聊天输入框（可直接发给别人）；Ctrl / Shift 点击走客户端原生的连结改造（例如把物品连结贴成可比较的形式）
- **复制所有结果**：把全部结果的 `ID + 连结` 一次性放进下方文本框并全选，Ctrl+C 即可
- **导出**：写进存档变量，`/reload` 后落盘成一个文本文件，格式是 `ID<TAB>连结`，一行一条
- **参数记忆**：起始 ID、结束 ID、速度、窗口大小与位置、小地图按钮位置，全部跨重载保留
- **小地图按钮**：点击开关窗口，拖动调整位置
- **ESC 关闭**：按 ESC 就能关窗口（`UISpecialFrames` 注册，会自我校对）
- **自检**：`/gis status` 会告诉你这个客户端到底支持哪些 API、窗口有没有建全，而不是静默失败

## 安装

1. 把 `GetInfoScan` 整个文件夹放进：
   ```
   ...\World of Warcraft\_classic_titan_\Interface\AddOns\GetInfoScan
   ```
   最终路径应该长这样，`GetInfoScan.toc` 就在这一层：
   ```
   Interface\AddOns\GetInfoScan\GetInfoScan.toc
   Interface\AddOns\GetInfoScan\Core.lua
   ...
   ```
   ⚠️ 不要出现 `AddOns\GetInfoScan\GetInfoScan\` 这种多套一层的情况，那是安装失败最常见的原因。

2. 重启客户端（或在人物选择界面点「插件」确认它被勾选）。
3. 如果客户端提示插件「已过期」，勾选**加载过期插件**即可 —— 本插件把 `Interface` 固定在 `38002`，在别的客户端版本上会显示过期，但代码本身有兼容层（见[兼容性](#兼容性与已知限制)）。

## 快速上手

1. 进游戏后点小地图上的按钮，或输入 `/gis`
2. 在「起始 ID / 结束 ID」里填入要查的区段（默认 `1` ~ `5000`）
3. 选类型页签：**物品 / 任务 / 法术 / 成就**
4. 点「开始扫描」，看着结果一条条冒出来
5. 扫完后：
   - 想看某条详情 → 鼠标悬停那一行
   - 想发连结给别人 → 点那一行，连结进入聊天输入框
   - 想批量拿走 → 「复制所有结果」，然后 Ctrl+C
   - 想存成文件 → 「导出」，再 `/reload`，见[导出文件在哪里](#导出文件在哪里)

> 想要更稳：把「速度」调大一点（例如 `0.15`）。物品类型在客户端没有资料时要去服务器问，速度太快反而会因为限速而变慢。

## 界面说明

窗口从上到下是：

| 区域 | 内容 |
| --- | --- |
| 参数行 | `起始 ID`、`结束 ID`、`速度（秒/批）` —— 回车即开始扫描 |
| 按钮行 | `开始扫描`（扫描中变成`暂停`/`继续`）、`停止`、四个类型页签、`复制所有结果`、`导出`、`清空` |
| 进度条 | 扫描百分比 |
| 进度文字 | `待机中` / `扫描 物品 中 (12.3%)` / `已暂停` / `完成: 已扫描 5000，找到 812，无资料 4188 (12.4 秒)` |
| 结果标题 | `结果: 812` |
| 结果列表 | `ID` + `连结`，可滚动，几万条也不卡（虚拟化，只画看得见的行） |
| 复制框 | 「复制所有结果」的内容会放在这里并自动全选 |
| 状态栏 | **客户端自己报的**数据：版本、build、Interface 号、内容线（`WOW_PROJECT_*`）、语言。例如 `物品 \| 3.80.2 (build 70177) \| Interface 38002 \| WRATH_CLASSIC \| zhCN` |

当前选中的类型页签会**加绿色底纹并把文字染绿**，一眼能看出选的是哪一类。
当某个类型在当前客户端不可用时（例如客户端没有成就 API），悬停该页签会弹出红色提示说明缺什么。

## 复制与导出的格式

**复制**（放进下方文本框，空格分隔，方便直接贴到聊天或记事本）：

```
2 |cffffff00|Hquest:2|h[沙普塔隆的爪子]|h|r 3 |cff1eff00|Hitem:3|h[粗糙的短剑]|h|r
```

**导出**（`ID` 与 `连结` 之间是一个 **Tab**）：

```
-- GetInfoScan 导出  2025-01-01 12:00:00
-- type=quest  range=1-5000  found=812
1	|cffffff00|Hquest:1|h[任务名]|h|r
2	|cffffff00|Hquest:2|h[沙普塔隆的爪子]|h|r
3	|cffffff00|Hquest:3|h[任务名]|h|r
```

- 前两行是注释：导出时间、类型、区段、命中数
- 之后每行一条：`数字 ID` + `Tab` + `完整连结`
- **名称就在连结的方括号里**，所以不需要额外的名称列；数字在左边，排序、grep、脚本处理都很方便
- 全部结果只保留 ID 与连结，**没有**任何额外行、续行或缩进

## 导出文件在哪里

WoW 插件没有写文件的权限，所以「导出」是写进**存档变量**，由客户端在**重载界面时**落盘：

```
...\World of Warcraft\_classic_titan_\WTF\Account\<你的账号>\SavedVariables\GetInfoScan.lua
```

所以导出后必须 **`/reload`（或小退 / 退出游戏）**，文件才会更新。用记事本或 VS Code 打开，找：

```lua
GetInfoScanDB = {
    ["export"] = {
        ["quest"] = {
            ["time"] = "2025-01-01 12:00:00",
            ["from"] = 1, ["to"] = 5000, ["count"] = 812,
            ["text"] = "-- GetInfoScan 导出 ...\n1\t|cffffff00|Hquest:1|h[...]|h|r\n...",
        },
    },
}
```

`text` 字段就是上面那份文件的完整内容，`\n` 是换行、`\t` 是 Tab。
每次导出会覆盖**同一类型**的上一次导出（`export.item` / `export.quest` / `export.spell` / `export.achievement` 各存一份，互不覆盖）。

## 斜杠命令

命令：`/gis`、`/getinfoscan`、`/infoscan`（三者等价）

| 命令 | 作用 |
| --- | --- |
| `/gis` | 打开 / 关闭窗口（`show`、`toggle`、`open` 同义） |
| `/gis hide` | 关闭窗口（`close` 同义） |
| `/gis status` | 打印客户端自报的版本 / build / 日期 / 语言 / 内容线、各类型 API 可用性、窗口构建报告、ESC 注册状态（`debug` 同义） |
| `/gis build` | 丢弃并重建窗口（窗口显示不全时的修复手段） |
| `/gis clear` | 清空当前结果列表 |
| `/gis copy` | 复制所有结果到复制框 |
| `/gis export` | 导出当前结果 |
| `/gis minimap` | 显示 / 隐藏小地图按钮 |
| `/gis reset` | 清空已保存的导出内容 |

`/gis status` 是排查问题的第一站，它会明确告诉你（下面每一个值都是**客户端自己报的**，不是本插件推断的）：

```
版本 3.80.2 | 介面 38002 | WOW_PROJECT_WRATH_CLASSIC | 视窗: yes
构建 70177 | 日期 Oct  1 2026 | 语言 zhCN | WOW_PROJECT_ID 11
扫描能力: preload=ItemMixin itemInfo=yes itemExists=yes quest=yes spell=yes achv=yes
视窗: 已建立  控件=7 元件=25
ESC 关闭: GetInfoScanMainFrame（可关闭视窗）
建立过程无错误
```

- `版本` / `构建` / `日期` / `介面` 全部来自 `GetBuildInfo()`（第 4 个返回值就是 Interface 号，也就是 TOC 里那个 `## Interface`）
- `WOW_PROJECT_WRATH_CLASSIC` 是 `WOW_PROJECT_ID` 等于**客户端自己的哪个 `WOW_PROJECT_*` 常量**（在 `_G` 里查出来的，不是写死的对照表；`WOW_PROJECT_ID` 这个"存放 ID 的常量"本身会被排除，否则它会永远匹配自己）。客户端没提供这个值时显示 `unknown`
- 语言来自 `GetLocale()`

## 扫描引擎是怎么工作的

插件必须在不把客户端卡死的前提下走完上万次查询，所以引擎是**分批 + 双路径**的：

```
每 tick（默认 0.08 ~ 0.1 秒）：
  1) 先处理上一轮"待验证"的 ID（它们需要时间让客户端把资料读进缓存）
  2) 快路径：本 tick 检查 200 个 ID，只认客户端本地缓存里已有的资料
     ├─ 有资料  → 记录结果
     ├─ 确认不存在 → 记入"无资料"计数
     └─ 未知     → 放进请求队列
  3) 慢路径：把队列里的 ID 交给客户端去服务端取（限速 40 个/秒）
     ├─ 优先用 Item mixin 的预载接口
     └─ 没有该接口的客户端，退回隐藏提示框 SetItemByID
  4) 下个 tick 再回头验证这批 ID 有没有变成已缓存
```

关键参数（都在 `Scanner.lua` 顶部，可自行调整）：

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `CHUNK_CACHE` | 200 | 每 tick 检查多少个 ID 的本地缓存 |
| `CHUNK_VERIFY` | 24 | 每批最多同时等待多少个 ID 回填 |
| `REQUEST_BUDGET` | 40 | 每秒最多向客户端请求多少个物品资料 |
| `MAX_RETRY` | 1 | 一个 ID 最多重新验证几轮 |
| `MAX_RESULTS` | 5000 | 结果条数上限（超出会明确提示并丢弃后续） |
| `DEFAULT_TICK` | 0.1 | 界面「速度」框留空时的 tick 间隔 |

补充说明：

- **只有物品类型**有慢路径。任务 / 法术 / 成就都是纯本地查询，速度由 tick 决定，可以调得很快。
- 「无资料」不等于"不存在"，它只代表**这个客户端现在拿不到这个 ID 的资料**（可能真的没有，也可能服务端没给）。插件不猜，如实分开统计 `找到` 与 `无资料`。
- 结果列表是**虚拟化**的：只有屏幕上看得到的那十几行是真的 Frame，所以几万条结果也不会卡。

## 存档结构（SavedVariables）

`WTF\...\SavedVariables\GetInfoScan.lua` 里的 `GetInfoScanDB`：

```lua
GetInfoScanDB = {
    ["minimap"] = { ["hide"] = false, ["angle"] = 220 },      -- 小地图按钮
    ["window"]  = { ["width"] = 660, ["height"] = 620, ... }, -- 窗口大小与位置
    ["range"]   = { ["from"] = "1", ["to"] = "5000", ["delay"] = "0.08" }, -- 上次输入的参数
    ["export"]  = { ["quest"] = { ... } },                    -- 上一次导出
}
```

- `range` 里存的是**你输入的原文**（字符串），所以重载后不会被打回默认值。
- 想彻底重置：删掉这个文件，或 `/gis reset`（只清导出）。

## 兼容性与已知限制

**已实测的环境**：Titan / 永恒服，`GetBuildInfo` 返回 `3.80.2`，`Interface` 为 `38002`，`zhCN`。

**兼容层**：`Core.lua` 里所有 API 都是"先探测、再使用"（每个引用都经过 `pcall` 探测并缓存），能识别 `Mainline` / `Classic Era` / `Wrath (38xxx)` / `Classic (16xxx)` 等版本线，并优先使用 `C_Item` / `C_Spell` / `C_QuestLog` 这类命名空间接口，缺失时回退到旧的全局函数。**但除上述环境外没有做过真机验证**，别的客户端上可能：
- 显示插件过期（把 `## Interface` 改成你客户端的版本号即可，或勾选"加载过期插件"）
- 某个类型不可用（`/gis status` 会明说哪个 API 缺失，悬停页签也会提示）

**明确的限制**：

- **任务只导出 ID 与名称，不导出任务描述和任务需求。**
  这是实测结论，不是偷懒：这个客户端**没有任何"按任务 ID 取任务文本"的接口**（`C_QuestLog` 上只有标题 getter 和计数型需求 `GetQuestObjectives`，也没有 `C_TooltipInfo`）。唯一能给出任务短句的 `GetQuestLogQuestText()`，它描述的是**你在任务日志里当前选中的那一条**，对着一整个 ID 区段用它会把这个任务的文字安到别的任务头上——那比不导出更糟。所以这条功能被**完整移除**了（早期版本曾经尝试过 API、提示框、任务日志三条路，都做不到按 ID 取）。
  使命名可行的是标题 getter（`GetTitleForQuestID`，缺失时回退 `GetQuestInfo`），名称就在连结里。
- 只能扫**连续整数区段**，不能给一串离散 ID。
- 客户端不知道的 ID 不会被"猜"出来；私服如果没给某个 ID 的资料，插件也拿不到。
- 复制走的是游戏内文本框，**文本框有长度上限**。超长时插件会明确告诉你"只接受了 N / M 个字符，完整内容请用导出"，不会假装成功。
- 本插件**不读取、不依赖任何第三方数据库**（包括 Questie / QuestieDB）。这是刻意设计：它的输出正是用来补全那些数据库的，拿它们当输入就成了循环论证。

## 常见问题

**Q：扫 1~5000 物品很慢？**
A：大部分 ID 客户端本地没有资料，要去服务端问，插件把请求限速在 40 个/秒，这是为了保护连接不被刷爆。想更快可以把「速度」调大（例如 `0.15`），或缩小扫描区段。

**Q：为什么任务扫描很快，物品很慢？**
A：只有物品有服务端请求。任务 / 法术 / 成就是纯本地查询，一次 tick 能查 200 个。

**Q：显示"无资料"是什么意思？**
A：这个客户端现在拿不到这个 ID 的资料。可能是真的不存在，也可能是服务端没返回。插件不做猜测，`找到` 和 `无资料` 分开计数。

**Q：窗口左下角那串东西是什么？**
A：是**客户端自己报的**原样数据，顺序为：版本、build、Interface 号、内容线、语言。例如 `物品 | 3.80.2 (build 70177) | Interface 38002 | WRATH_CLASSIC | zhCN`。

- `版本` / `build` / `Interface` 来自 `GetBuildInfo()`（第 4 个返回值就是 TOC 里那个 `## Interface` 号）
- 语言来自 `GetLocale()`
- `WRATH_CLASSIC` 是 `WOW_PROJECT_ID` 等于**客户端自己定义的哪个 `WOW_PROJECT_*` 常量**（在 `_G` 里查出来的）。插件**不会**贴一个自己推断的版本名；如果客户端没提供 `WOW_PROJECT_ID`，或它的值不等于任何 `WOW_PROJECT_*` 常量，这里会显示 `unknown` 或 `project 11` 这样的原样数字。

**Q：那"版本 3.80.2"是插件写死的吗？**
A：不是。整行都是运行时从客户端读的，可以直接贴进 bug 报告。

**Q：导出后文件没变化？**
A：必须 `/reload`（或退出游戏）才会写盘。另外要注意每个类型只保留**最后一次**导出。

**Q：窗口显示不全 / 少了控件？**
A：`/gis build` 重建窗口，然后 `/gis status` 看"建立过程无错误"和"缺少控件"两行。

**Q：按 ESC 关不掉？**
A：`/gis status` 会打印 `ESC 关闭: GetInfoScanMainFrame（可关闭视窗）`。如果显示"未注册"，说明当前客户端没有 `UISpecialFrames`（少见），此时用标题栏的关闭按钮。

**Q：能扫描坐骑 / 宠物 / 成就分类别的 ID 吗？**
A：目前只支持物品、任务、法术、成就四种。加类型很容易（见下），欢迎 PR。

## 目录结构

```
GetInfoScan/
├─ GetInfoScan.toc          # 插件清单（Interface 38002、版本、加载顺序）
├─ Locale.lua               # zhCN / zhTW / enUS 文案，缺 key 回退
├─ Core.lua                 # 命名空间、客户端识别、API 兼容层、存档、小地图按钮、斜杠命令
├─ Scanner.lua              # 扫描引擎（分批、快慢路径、限速、结果与导出）
├─ UI.lua                   # AceGUI 窗口、自绘边框、虚拟化结果列表、页签高亮、ESC 注册
├─ icon.tga                 # 小地图按钮图标
└─ Libs/                    # 内置库（无需另装）
   ├─ LibStub/
   ├─ CallbackHandler-1.0/
   └─ AceGUI-3.0/
```

## 开发说明

**加一个扫描类型**（例如坐骑）：

1. 在 `Core.lua` 里写一个 resolver，返回 `id, link, quality, level`；无法解析时返回 `nil`：
   ```lua
   function api.ResolveMount(mountID)
       local name = safeCall(api.GetMountName, mountID)
       if not name or name == "" then return nil end
       return tostring(mountID), ("|cff...|Hmount:%d|h[%s]|h|r"):format(mountID, name), 1, 0
   end
   ```
2. 往 `addon.SCAN_TYPES` 里加一项 `{ key = "mount", resolver = ResolveMount, apiName = "mount", defaultFrom = 1, defaultTo = 2000 }`，并在 `apiCheckers` 里补一个可用性检测。
3. 在 `Locale.lua` 三种语言里加 `TAB_MOUNT`。

UI、导出、复制、结果列表都会自动跟着走，不需要改别的地方。

> `apiName` 是给 `/gis status` 的技术输出用的稳定标识（例如 `quest=yes`），玩家看到的名称一律来自 `TAB_<类型>`（经 `addon:TypeLabel`），所以中文客户端不会冒出 "扫描 item 中" 这种半截英文。

**排查问题**：`/gis status` 是第一站。它会打印**客户端自报**的版本 / build / 日期 / 语言 / 内容线（全部来自 `GetBuildInfo`、`GetLocale`、`WOW_PROJECT_ID`，不含任何推断）、每个 API 的可用性、窗口构建报告（哪个控件缺失、哪个构建步骤失败）、以及 ESC 注册状态。
`/gis build` 会丢弃并重建窗口，构建过程按"步骤"逐个保护，任何一步失败都会指名道姓而不是把窗口弄没。

**代码风格约定**（读代码时值得知道）：
- 注释写"为什么"，不写"做什么"；踩过的坑都留在注释里，避免同一条路走两遍。
- 涉及多字节字符（中文）的字符串处理一律**按字节安全**处理：Lua 的字符集匹配的是**单个字节**，把全角冒号这类字符写进 `[...]` 会吃掉前一个汉字的最后一个字节，直接把 `狼` 变成 `狠`。这类 bug 在本项目真实发生过。
- 永不使用 `assert` 做运行期校验：一次断言失败会连带毁掉**之后**的全部 UI 构建。所有构建步骤都是保护的，失败会记录并打印。

## English

**GetInfoScan** is a World of Warcraft addon that scans a numeric ID range and collects every **item / quest / spell / achievement** that actually exists on your client, with its ID, name and clickable hyperlink.

Built for a Chinese private "Titan" client (`GetBuildInfo` reports `3.80.2`, `## Interface: 38002`), and it works purely through the client's own APIs — **no third-party databases, no network**, so the IDs you get are the ones *your* server really has. The output is meant to be used to cross-check or fill in other databases (QuestieDB, etc.).

**Author**: Loukky · **License**: MIT · **Inspired by** [GetInfoLink](https://www.curseforge.com/wow/addons/getinfolink) by Char11e (independent implementation, no shared code).

**Install**: drop the `GetInfoScan` folder into `Interface\AddOns\` so that `Interface\AddOns\GetInfoScan\GetInfoScan.toc` exists, then restart the client.

**Use**: click the minimap button or type `/gis`. Fill in *Start ID* and *End ID*, pick a type tab, press *Start Scan*. Hover a row for its in-game tooltip, click a row to put its link into the chat edit box, use *Copy All Results* or *Export*.

**Export** goes to SavedVariables — `/reload` to write it to disk:

```
WTF\Account\<account>\SavedVariables\GetInfoScan.lua
```

Format: two `--` comment lines, then one `numericID<TAB>hyperlink` line per hit. The name is the link's visible text, so no extra column is needed.

**Commands**: `/gis` (toggle) · `status` · `build` · `clear` · `copy` · `export` · `minimap` · `reset`

**Known limitation**: quest rows carry only the ID and the name. This client exposes no per-ID quest-text getter, and the one call that returns a quest's short objective sentence describes whichever log entry is currently *selected* — using it across an ID range would attribute one quest's text to another, so description/objective export was removed deliberately.

**Built-in libraries**: LibStub, CallbackHandler-1.0, AceGUI-3.0 (all vendored under `Libs/`).

## 授权

**MIT License** —— 可自由使用、修改、再发布，保留版权声明即可。完整文本见 [LICENSE](LICENSE)，版权归 **Loukky**。

`Libs/` 里是上游库的**原样副本**，遵循各库自身的许可，不适用上面的 MIT 声明：

- **LibStub** —— 公有领域（其源文件开头写明 "hereby placed in the Public Domain"）
- **CallbackHandler-1.0**、**AceGUI-3.0** —— 来自 [Ace3](https://github.com/WoWUIDev/Ace3)，上游鼓励按需内嵌（其 README 明确建议直接引用用到的库）。上游仓库根目录没有 LICENSE 文件，若要严格确认条款请以 [WoWAce 的 Ace3 项目页](https://www.wowace.com/projects/ace3) 为准。

## 致谢

- 灵感来自 **[GetInfoLink](https://www.curseforge.com/wow/addons/getinfolink)**（作者 **Char11e**）—— 同样是"输入 ID 查出这个名字"的工具。本插件是独立实现，与对方没有代码关系，图标也是自己画的。
- [Ace3 / AceGUI-3.0](https://www.wowace.com/projects/ace3) —— 窗口控件
- [LibStub](https://www.wowace.com/projects/libstub)、[CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler) —— AceGUI 的依赖
- 仓库根目录提供一个 `.vscode/settings.json`（Lua Language Server + [Ketho 的 WoW API 注解](https://github.com/Ketho/vscode-wow-api)），方便用 VS Code 打开就能补全与查错。
