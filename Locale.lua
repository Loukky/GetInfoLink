--[[----------------------------------------------------------------------------
    GetInfoScan - Locale.lua
    Localized strings. Currently shipped: zhCN, zhTW, enUS.
    Missing keys fall back to enUS and then to the key itself.
----------------------------------------------------------------------------]]--

local _, addon = ...

local L = {}
addon.L = L

local locale = GetLocale and GetLocale() or "enUS"

-- ============================================================================
-- English (default / fallback)
-- ============================================================================
local enUS = {
    ADDON_TITLE           = "GetInfoScan",
    WINDOW_TITLE          = "Info Link Batch Scanner",

    LABEL_START           = "Start ID",
    LABEL_END             = "End ID",
    LABEL_DELAY           = "Speed (sec/batch)",

    TAB_ITEM              = "Items",
    TAB_QUEST             = "Quests",
    TAB_SPELL             = "Spells",
    TAB_ACHIEVEMENT       = "Achievements",

    BTN_SCAN              = "Start Scan",
    BTN_STOP              = "Stop",
    BTN_PAUSE             = "Pause",
    BTN_RESUME            = "Continue",
    BTN_EXPORT            = "Export",
    BTN_COPY              = "Copy All Results",
    BTN_CLEAR             = "Clear",

    HDR_RESULTS           = "Results",
    HDR_STATUS            = "Status",

    PROGRESS_IDLE         = "Idle",
    PROGRESS_SCANNING     = "Scanning %s  (%.1f%%)",
    PROGRESS_PAUSED       = "Paused - click Continue to resume",
    PROGRESS_DONE         = "Done: %d scanned, %d found, %d missing (%.1fs)",
    PROGRESS_STOPPED      = "Stopped: %d scanned, %d found, %d missing",

    ERR_RANGE             = "|cffff5555[GetInfoScan]|r Please fill in a valid Start ID and End ID (Start must not be larger than End).",
    ERR_TOO_LARGE         = "|cffff5555[GetInfoScan]|r Range is too large (%d IDs). Maximum is %d per scan.",
    ERR_NO_API            = "|cffff5555[GetInfoScan]|r This client does not expose %s data, scanning is unavailable.",
    ERR_NO_RESULTS        = "|cffff5555[GetInfoScan]|r There are no results to export yet.",
    ERR_NO_RESULTS_COPY   = "|cffff5555[GetInfoScan]|r There are no links to copy yet.",
    ERR_BUSY              = "|cffff5555[GetInfoScan]|r A scan is running - press Stop first.",

    MSG_EXPORTED          = "|cff33ff99[GetInfoScan]|r Exported %d link(s) to SavedVariables. Reload the UI (/reload) to write them to disk.",
    MSG_COPIED            = "|cff33ff99[GetInfoScan]|r %d result(s) (id + link) put in the copy box below and selected - press Ctrl+C to copy.",
    MSG_COPY_TRUNCATED    = "|cffff5555[GetInfoScan]|r the copy box took only %d of %d characters; use Export for the complete set.",
    MSG_CLEARED           = "|cff33ff99[GetInfoScan]|r Results cleared.",
    MSG_LOADED            = "|cff33ff99[GetInfoScan]|r Loaded. Type |cffffd200/gis|r to open the scanner.",
    MSG_CANCELLED         = "|cff33ff99[GetInfoScan]|r Scan stopped.",

    STATUS_LINE           = "|cff33ff99[InfoScan]|r v%s | interface %s | %s | window: %s",
    STATUS_BUILD          = "|cff33ff99[InfoScan]|r build %s  |  date %s  |  locale %s  |  WOW_PROJECT_ID %s",
    STATUS_APIS           = "|cff33ff99[InfoScan]|r %s",
    STATUS_CMDS           = "|cff33ff99[InfoScan]|r /gis (window)  /gis status  /gis build  /gis clear  /gis copy  /gis export  /gis minimap  /gis reset",

    -- Build diagnostics. Every band of the window is built through a guarded
    -- step, so a failure names itself instead of silently killing the window.
    BUILD_NONE            = "|cffff5555[GetInfoScan]|r window: not built",
    BUILD_OK              = "|cff33ff99[GetInfoScan]|r window: built  controls=%d widgets=%d",
    BUILD_MISSING         = "|cffff5555[GetInfoScan]|r missing controls: %s",
    BUILD_NO_ERRORS       = "|cff33ff99[GetInfoScan]|r build errors: none",
    BUILD_ERRORS          = "|cffff5555[GetInfoScan]|r build errors (%d):",
    BUILD_NOTES           = "|cff33ff99[GetInfoScan]|r build notes (%d):",
    BUILD_STEP_FAILED     = "|cffff5555[GetInfoScan]|r build step failed -> %s",
    BUILD_REBUILT         = "|cff33ff99[GetInfoScan]|r window rebuilt.",
    BUILD_NO_BUILDER      = "|cffff5555[GetInfoScan]|r window builder missing: UI.lua did not load.",

    -- Escape-key handling depends on a client global (UISpecialFrames), so what
    -- was registered and where it points is stated instead of assumed.
    BUILD_ESC             = "|cff33ff99[GetInfoScan]|r escape key: %s (%s)",
    ESC_STATE_OK          = "closes the window",
    ESC_STATE_BAD         = "not registered",
    ESC_NO_FRAME          = "no frame handle",
    ESC_NO_LIST           = "this client has no UISpecialFrames",

    TIP_MINIMAP           = "Info Link Batch Scanner",
    TIP_MINIMAP_CLICK     = "Click to open or close the scanner window.",
    TIP_MINIMAP_DRAG      = "Drag to move the button.",

    EXPORT_HEADER         = "GetInfoScan export",
}

-- ============================================================================
-- Simplified Chinese
-- ============================================================================
local zhCN = {
    ADDON_TITLE           = "资讯连结批次扫描",
    WINDOW_TITLE          = "资讯连结批次扫描器",

    LABEL_START           = "起始 ID",
    LABEL_END             = "结束 ID",
    LABEL_DELAY           = "速度(秒/批)",

    TAB_ITEM              = "物品",
    TAB_QUEST             = "任务",
    TAB_SPELL             = "法术",
    TAB_ACHIEVEMENT       = "成就",

    BTN_SCAN              = "开始扫描",
    BTN_STOP              = "停止",
    BTN_PAUSE             = "暂停",
    BTN_RESUME            = "继续",
    BTN_EXPORT            = "导出",
    BTN_COPY              = "复制所有结果",
    BTN_CLEAR             = "清空",

    HDR_RESULTS           = "结果",
    HDR_STATUS            = "状态",

    PROGRESS_IDLE         = "待机中",
    PROGRESS_SCANNING     = "扫描 %s 中  (%.1f%%)",
    PROGRESS_PAUSED       = "已暂停 - 点「继续」恢复扫描",
    PROGRESS_DONE         = "完成: 已扫描 %d，找到 %d，无资料 %d (耗时 %.1f 秒)",
    PROGRESS_STOPPED      = "已停止: 已扫描 %d，找到 %d，无资料 %d",

    ERR_RANGE             = "|cffff5555[资讯连结扫描]|r 请输入有效的起始 ID 与结束 ID（起始不可大于结束）。",
    ERR_TOO_LARGE         = "|cffff5555[资讯连结扫描]|r 范围过大（%d 个 ID），单次扫描上限为 %d。",
    ERR_NO_API            = "|cffff5555[资讯连结扫描]|r 当前客户端不提供「%s」资料，无法扫描。",
    ERR_NO_RESULTS        = "|cffff5555[资讯连结扫描]|r 目前没有可导出的结果。",
    ERR_NO_RESULTS_COPY   = "|cffff5555[资讯连结扫描]|r 目前没有可复制的连结。",
    ERR_BUSY              = "|cffff5555[资讯连结扫描]|r 扫描进行中，请先按「停止」。",

    MSG_EXPORTED          = "|cff33ff99[资讯连结扫描]|r 已导出 %d 条连结至 SavedVariables，请 /reload 后写入磁盘。",
    MSG_COPIED            = "|cff33ff99[资讯连结扫描]|r 已将 %d 条结果（ID + 连结）放入下方复制框并全选，按 Ctrl+C 复制。",
    MSG_COPY_TRUNCATED    = "|cffff5555[资讯连结扫描]|r 复制框只接受了 %d / %d 个字符，完整内容请用「导出」。",
    MSG_CLEARED           = "|cff33ff99[资讯连结扫描]|r 结果已清空。",
    MSG_LOADED            = "|cff33ff99[资讯连结扫描]|r 已载入，输入 |cffffd200/gis|r 打开扫描器。",
    MSG_CANCELLED         = "|cff33ff99[资讯连结扫描]|r 扫描已停止。",

    STATUS_LINE           = "|cff33ff99[资讯连结扫描]|r 版本 %s | 介面 %s | %s | 视窗: %s",
    STATUS_BUILD          = "|cff33ff99[资讯连结扫描]|r 构建 %s | 日期 %s | 语言 %s | WOW_PROJECT_ID %s",
    STATUS_APIS           = "|cff33ff99[资讯连结扫描]|r 扫描能力: %s",
    STATUS_CMDS           = "|cff33ff99[资讯连结扫描]|r /gis 开关视窗 | /gis status 状态 | /gis build 重建视窗 | /gis clear 清空 | /gis copy 复制 | /gis export 导出 | /gis minimap 小地图按钮",

    BUILD_NONE            = "|cffff5555[资讯连结扫描]|r 视窗: 未建立",
    BUILD_OK              = "|cff33ff99[资讯连结扫描]|r 视窗: 已建立  控件=%d 元件=%d",
    BUILD_MISSING         = "|cffff5555[资讯连结扫描]|r 缺少控件: %s",
    BUILD_NO_ERRORS       = "|cff33ff99[资讯连结扫描]|r 建立过程无错误",
    BUILD_ERRORS          = "|cffff5555[资讯连结扫描]|r 建立错误 (%d 项):",
    BUILD_NOTES           = "|cff33ff99[资讯连结扫描]|r 建立提示 (%d 项):",
    BUILD_STEP_FAILED     = "|cffff5555[资讯连结扫描]|r 建立步骤失败 -> %s",
    BUILD_REBUILT         = "|cff33ff99[资讯连结扫描]|r 视窗已重建。",
    BUILD_NO_BUILDER      = "|cffff5555[资讯连结扫描]|r 找不到视窗建立函式: UI.lua 未载入。",

    BUILD_ESC             = "|cff33ff99[资讯连结扫描]|r ESC 关闭: %s（%s）",
    ESC_STATE_OK          = "可关闭视窗",
    ESC_STATE_BAD         = "未注册",
    ESC_NO_FRAME          = "找不到框体",
    ESC_NO_LIST           = "此客户端没有 UISpecialFrames",

    TIP_MINIMAP           = "资讯连结批次扫描",
    TIP_MINIMAP_CLICK     = "点击开关扫描视窗。",
    TIP_MINIMAP_DRAG      = "按住左键可拖动按钮。",

    EXPORT_HEADER         = "GetInfoScan 导出",
}

-- ============================================================================
-- Traditional Chinese
-- ============================================================================
local zhTW = {
    ADDON_TITLE           = "資訊連結批次掃描",
    WINDOW_TITLE          = "資訊連結批次掃描器",

    LABEL_START           = "起始 ID",
    LABEL_END             = "結束 ID",
    LABEL_DELAY           = "速度(秒/批)",

    TAB_ITEM              = "物品",
    TAB_QUEST             = "任務",
    TAB_SPELL             = "法術",
    TAB_ACHIEVEMENT       = "成就",

    BTN_SCAN              = "開始掃描",
    BTN_STOP              = "停止",
    BTN_PAUSE             = "暫停",
    BTN_RESUME            = "繼續",
    BTN_EXPORT            = "匯出",
    BTN_COPY              = "複製所有結果",
    BTN_CLEAR             = "清除",

    HDR_RESULTS           = "結果",
    HDR_STATUS            = "狀態",

    PROGRESS_IDLE         = "待機中",
    PROGRESS_SCANNING     = "掃描 %s 中  (%.1f%%)",
    PROGRESS_PAUSED       = "已暫停 - 點「繼續」恢復掃描",
    PROGRESS_DONE         = "完成: 已掃描 %d，找到 %d，無資料 %d (耗時 %.1f 秒)",
    PROGRESS_STOPPED      = "已停止: 已掃描 %d，找到 %d，無資料 %d",

    ERR_RANGE             = "|cffff5555[資訊連結掃描]|r 請輸入有效的起始 ID 與結束 ID（起始不可大於結束）。",
    ERR_TOO_LARGE         = "|cffff5555[資訊連結掃描]|r 範圍過大（%d 個 ID），單次掃描上限為 %d。",
    ERR_NO_API            = "|cffff5555[資訊連結掃描]|r 當前客戶端不提供「%s」資料，無法掃描。",
    ERR_NO_RESULTS        = "|cffff5555[資訊連結掃描]|r 目前沒有可匯出的結果。",
    ERR_NO_RESULTS_COPY   = "|cffff5555[資訊連結掃描]|r 目前沒有可複製的連結。",
    ERR_BUSY              = "|cffff5555[資訊連結掃描]|r 掃描進行中，請先按「停止」。",

    MSG_EXPORTED          = "|cff33ff99[資訊連結掃描]|r 已匯出 %d 條連結至 SavedVariables，請 /reload 後寫入磁碟。",
    MSG_COPIED            = "|cff33ff99[資訊連結掃描]|r 已將 %d 條結果（ID + 連結）放入下方複製框並全選，按 Ctrl+C 複製。",
    MSG_COPY_TRUNCATED    = "|cffff5555[資訊連結掃描]|r 複製框只接受了 %d / %d 個字元，完整內容請用「匯出」。",
    MSG_CLEARED           = "|cff33ff99[資訊連結掃描]|r 結果已清空。",
    MSG_LOADED            = "|cff33ff99[資訊連結掃描]|r 已載入，輸入 |cffffd200/gis|r 打開掃描器。",
    MSG_CANCELLED         = "|cff33ff99[資訊連結掃描]|r 掃描已停止。",

    STATUS_LINE           = "|cff33ff99[資訊連結掃描]|r 版本 %s | 介面 %s | %s | 視窗: %s",
    STATUS_BUILD          = "|cff33ff99[資訊連結掃描]|r 建置 %s | 日期 %s | 語言 %s | WOW_PROJECT_ID %s",
    STATUS_APIS           = "|cff33ff99[資訊連結掃描]|r 掃描能力: %s",
    STATUS_CMDS           = "|cff33ff99[資訊連結掃描]|r /gis 開關視窗 | /gis status 狀態 | /gis build 重建視窗 | /gis clear 清空 | /gis copy 複製 | /gis export 匯出 | /gis minimap 小地圖按鈕",

    BUILD_NONE            = "|cffff5555[資訊連結掃描]|r 視窗: 未建立",
    BUILD_OK              = "|cff33ff99[資訊連結掃描]|r 視窗: 已建立  控件=%d 元件=%d",
    BUILD_MISSING         = "|cffff5555[資訊連結掃描]|r 缺少控件: %s",
    BUILD_NO_ERRORS       = "|cff33ff99[資訊連結掃描]|r 建立過程無錯誤",
    BUILD_ERRORS          = "|cffff5555[資訊連結掃描]|r 建立錯誤 (%d 項):",
    BUILD_NOTES           = "|cff33ff99[資訊連結掃描]|r 建立提示 (%d 項):",
    BUILD_STEP_FAILED     = "|cffff5555[資訊連結掃描]|r 建立步驟失敗 -> %s",
    BUILD_REBUILT         = "|cff33ff99[資訊連結掃描]|r 視窗已重建。",
    BUILD_NO_BUILDER      = "|cffff5555[資訊連結掃描]|r 找不到視窗建立函式: UI.lua 未載入。",

    BUILD_ESC             = "|cff33ff99[資訊連結掃描]|r ESC 關閉: %s（%s）",
    ESC_STATE_OK          = "可關閉視窗",
    ESC_STATE_BAD         = "未註冊",
    ESC_NO_FRAME          = "找不到框體",
    ESC_NO_LIST           = "此客戶端沒有 UISpecialFrames",

    TIP_MINIMAP           = "資訊連結批次掃描",
    TIP_MINIMAP_CLICK     = "點擊開關掃描視窗。",
    TIP_MINIMAP_DRAG      = "按住左鍵可拖動按鈕。",

    EXPORT_HEADER         = "GetInfoScan 匯出",
}

local tables = {
    enUS = enUS,
    zhCN = zhCN,
    zhTW = zhTW,
}

-- enGB shares the enUS strings.
if locale == "enGB" then
    locale = "enUS"
end

local active = tables[locale] or enUS

setmetatable(L, {
    __index = function(_, key)
        local value = active[key]
        if value == nil then
            value = enUS[key]
        end
        if value == nil then
            return tostring(key)
        end
        return value
    end,
})
