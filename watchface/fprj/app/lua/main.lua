--[[
  ============================================================
  FloatLayerDemo —— 小米手环 Lua 表盘「顶层悬浮窗」可行性测试
  ============================================================

  目的
  ----
  验证 LVGL top/sys layer 在米环 Lua(VelaOS + Luavgl) 表盘环境里
  是否可用、能否实现"跨页面常驻的全局悬浮控件"。

  核心原理
  --------
  LVGL 中除挂在当前屏幕(screen)下的控件外，还有独立于任何 screen
  的特殊图层：
      lv_disp_get_layer_sys()  最顶层，系统提示用
      lv_disp_get_layer_top()  次顶层，位于所有 screen 之上
  把控件创建在这些 layer 之下，它就不属于任何具体页面。
  表盘内无论怎样切换/隐藏/重建页面内容，它都一直悬浮在最上层。

  本 Demo 用「同屏双容器模拟页面切换」(页面A / 页面B) 演示：
    - 挂在 layer_top 的悬浮球：切页后依然可见、最顶、持续刷新电量
    - 挂在页面A内部的对照标签：随页面A一起隐藏（体现普通控件差异）

  若固件裁剪掉了 layer API，代码会自动降级：
      layer_top -> layer_sys -> root 兼容模式
  并通过日志(FLOAT:) 打印实际生效的模式。

  打包 / 测试方法见工程 docs/README-FloatDemo.md
  ============================================================
--]]

local lvgl     = require("lvgl")
local dataman  = require("dataman")

-- 日志：EasyFace 模拟器/真机可用 adb logcat 观察（前缀 [FLOAT]）
local log = print or function() end
local function dbg(...) log("[FLOAT]", ...) end

-- =====================================================================
-- 1) 探测显示设备与顶层图层 API（全部容错，不因缺 API 崩溃）
-- =====================================================================
local disp      = nil    -- 显示设备句柄
local topLayer  = nil    -- 次顶层 layer
local sysLayer  = nil    -- 最顶层 layer
local layerMode = "none" -- "top" | "sys" | "root"

do
  local ok
  ok, disp = pcall(function() return lvgl.disp.get_default() end)
  if ok and disp then
    dbg("lvgl.disp.get_default() OK")
  else
    disp = nil
    dbg("lvgl.disp.get_default() 不可用")
  end
end

if disp then
  local ok, l
  ok, l = pcall(function() return disp:get_layer_top() end)
  if ok and l then
    topLayer  = l
    layerMode = "top"
    dbg("get_layer_top() OK -> 悬浮层挂 TOP layer")
  else
    dbg("get_layer_top() 不可用")
  end
end

if layerMode == "none" and disp then
  local ok, l
  ok, l = pcall(function() return disp:get_layer_sys() end)
  if ok and l then
    sysLayer  = l
    layerMode = "sys"
    dbg("get_layer_sys() OK -> 悬浮层挂 SYS layer")
  else
    dbg("get_layer_sys() 不可用")
  end
end

if layerMode == "none" then
  dbg("当前固件未暴露 layer API，降级为 root 兼容模式")
end

-- =====================================================================
-- 2) 安全取字体
-- =====================================================================
local FONT_BASE = lvgl.BUILTIN_FONT.MONTSERRAT_20

local function makeFont(size)
  local ok, f = pcall(function() return lvgl.Font("montserrat", size, "normal") end)
  if ok and f then return f end
  dbg("Font(" .. tostring(size) .. ") 加载失败，回退内置字体")
  return FONT_BASE
end

local FONT_TIME  = makeFont(40) -- 时钟大字（失败自动回退内置）
local FONT_MID   = makeFont(22)
local FONT_SMALL = lvgl.BUILTIN_FONT.MONTSERRAT_14 or FONT_BASE

-- =====================================================================
-- 3) 页面数据（由 dataman 订阅维护）
-- =====================================================================
local curHour  = 0
local curMin   = 0
local curBatt  = 0
local mStr, dStr, wStr = "--", "--", "---"

local function dateText()
  return string.format("%s/%s %s", mStr, dStr, wStr)
end

-- =====================================================================
-- 4) UI 创建
-- =====================================================================
local HOR = lvgl.HOR_RES()
local VER = lvgl.VER_RES()
dbg(string.format("screen = %d x %d", HOR, VER))

-- 一个常驻引用对象（dataman 订阅时作为关联 obj 传入）
local uiRoot = lvgl.Object(nil, {
  w = HOR, h = VER,
  bg_opa = 0, border_width = 0, pad_all = 0,
})
uiRoot:clear_flag(lvgl.FLAG.SCROLLABLE)
uiRoot:clear_flag(lvgl.FLAG.CLICKABLE)

-- ---------------------------------------------------------------
-- 4.1 页面 A：主页（时钟）
-- ---------------------------------------------------------------
local pageA = lvgl.Object(uiRoot, {
  w = HOR, h = VER,
  bg_color = 0x0A0E1A, bg_opa = 255,
  border_width = 0, pad_all = 0,
})
pageA:clear_flag(lvgl.FLAG.SCROLLABLE)
pageA:clear_flag(lvgl.FLAG.CLICKABLE)

local clockLabel = lvgl.Label(pageA, {
  text = "00:00",
  text_color = 0xFFFFFF,
  text_font = FONT_TIME,
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = -42 },
})

local dateLabel = lvgl.Label(pageA, {
  text = dateText(),
  text_color = 0x9FB3C8,
  text_font = FONT_MID,
  align = { type = lvgl.ALIGN.CENTER, x_ofs = 0, y_ofs = 6 },
})

local hintA = lvgl.Label(pageA, {
  text = "Page A | tap button below",
  text_color = 0x55607A,
  text_font = FONT_SMALL,
  align = { type = lvgl.ALIGN.BOTTOM_MID, x_ofs = 0, y_ofs = -26 },
})

-- 对照①：伪装成悬浮的“普通控件”（挂在页面A里）
-- 切到页面B后它随 pageA 一起隐藏 → 用于与 layer 悬浮球做对照
local fakeFloatA = lvgl.Label(pageA, {
  text = "A-fake",
  text_color = 0xE8684A,
  text_font = FONT_SMALL,
  align = { type = lvgl.ALIGN.TOP_RIGHT, x_ofs = -8, y_ofs = 8 },
})

-- 切到页面B的按钮
local btnToB = lvgl.Object(pageA, {
  w = 128, h = 40, radius = 20,
  bg_color = 0x1B2330, bg_opa = 255,
  border_width = 1, border_color = 0x3A8DD6,
  align = { type = lvgl.ALIGN.BOTTOM_MID, x_ofs = 0, y_ofs = -74 },
})
btnToB:clear_flag(lvgl.FLAG.SCROLLABLE)
btnToB:add_flag(lvgl.FLAG.CLICKABLE)

local btnToBLbl = lvgl.Label(btnToB, {
  text = "Go B  ->",
  text_color = 0xFFFFFF,
  text_font = FONT_SMALL,
  align = lvgl.ALIGN.CENTER,
})

-- ---------------------------------------------------------------
-- 4.2 页面 B：设置模拟页（全屏不透明背景，盖住 A）
-- ---------------------------------------------------------------
local pageB = lvgl.Object(uiRoot, {
  w = HOR, h = VER,
  bg_color = 0x12203A, bg_opa = 255,
  border_width = 0, pad_all = 0,
})
pageB:clear_flag(lvgl.FLAG.SCROLLABLE)
pageB:clear_flag(lvgl.FLAG.CLICKABLE)
pageB:add_flag(lvgl.FLAG.HIDDEN) -- 初始隐藏

local titleB = lvgl.Label(pageB, {
  text = "Page B (settings sim)",
  text_color = 0xFFFFFF,
  text_font = FONT_MID,
  align = { type = lvgl.ALIGN.TOP_MID, x_ofs = 0, y_ofs = 22 },
})

local rowsB = {
  "  * Brightness ..... 80%",
  "  * DND ............ ON",
  "  * Vibration ...... ON",
}
for i, txt in ipairs(rowsB) do
  lvgl.Label(pageB, {
    text = txt,
    text_color = 0xB9C6DD,
    text_font = FONT_SMALL,
    align = { type = lvgl.ALIGN.TOP_LEFT, x_ofs = 12, y_ofs = 66 + (i - 1) * 38 },
  })
end

local btnBack = lvgl.Object(pageB, {
  w = 128, h = 40, radius = 20,
  bg_color = 0x1B2330, bg_opa = 255,
  border_width = 1, border_color = 0x3A8DD6,
  align = { type = lvgl.ALIGN.BOTTOM_MID, x_ofs = 0, y_ofs = -74 },
})
btnBack:clear_flag(lvgl.FLAG.SCROLLABLE)
btnBack:add_flag(lvgl.FLAG.CLICKABLE)

local btnBackLbl = lvgl.Label(btnBack, {
  text = "<- Back A",
  text_color = 0xFFFFFF,
  text_font = FONT_SMALL,
  align = lvgl.ALIGN.CENTER,
})

-- ---------------------------------------------------------------
-- 4.3 悬浮球（核心验证对象）
--     父级取决于探测结果：
--       layerMode=="top" -> topLayer
--       layerMode=="sys" -> sysLayer
--       否则             -> uiRoot（兼容模式，见 showPage 注释）
-- ---------------------------------------------------------------
local ball      = nil
local ballLabel = nil

local function makeFloatBall()
  local parent
  if layerMode == "top" then
    parent = topLayer
  elseif layerMode == "sys" then
    parent = sysLayer
  else
    parent = uiRoot -- 兼容模式：放 root 下，靠创建顺序盖在最上
  end

  ball = lvgl.Object(parent, {
    w = 42, h = 42, radius = 21,
    bg_color = 0x2FA84F, bg_opa = 255,
    border_width = 2, border_color = 0xFFFFFF,
    pad_all = 0,
    align = { type = lvgl.ALIGN.BOTTOM_RIGHT, x_ofs = -14, y_ofs = -14 },
  })
  -- 关键②：悬浮球不可点击 → 不拦截下层触摸，纯展示
  ball:clear_flag(lvgl.FLAG.CLICKABLE)
  ball:clear_flag(lvgl.FLAG.SCROLLABLE)

  ballLabel = lvgl.Label(ball, {
    text = "--%",
    text_color = 0xFFFFFF,
    text_font = FONT_SMALL,
    align = lvgl.ALIGN.CENTER,
  })

  dbg("悬浮球已创建, 父对象=" .. tostring(parent))
end

makeFloatBall()

-- =====================================================================
-- 5) 页面切换（同一屏幕下的子视图切换 = 手环表盘常见的“翻页”形态）
-- =====================================================================
local function showPage(goB)
  if goB then
    pageA:add_flag(lvgl.FLAG.HIDDEN)
    pageB:clear_flag(lvgl.FLAG.HIDDEN)
    dbg("切换到 Page B：A 上的普通控件(A-fake)已隐藏；悬浮球应仍可见且在最顶")
  else
    pageB:add_flag(lvgl.FLAG.HIDDEN)
    pageA:clear_flag(lvgl.FLAG.HIDDEN)
    dbg("切回 Page A")
  end

  if layerMode == "none" and ball then
    -- 兼容模式没有独立图层：只能保证球最后创建(盖在现有页面之上)。
    -- 若后续还想再压过新建页面，可在此 delete+重建（演示从简）。
    dbg("root 兼容模式提示：新建全屏页面后需 delete+重建球才能保持置顶")
  end
end

btnToB:onevent(lvgl.EVENT.CLICKED, function()
  dbg("button clicked -> go B")
  showPage(true)
end)

btnBack:onevent(lvgl.EVENT.CLICKED, function()
  dbg("button clicked -> back A")
  showPage(false)
end)

-- =====================================================================
-- 6) dataman 订阅：时间 / 日期 / 电量
--    通道值高字节为真实值（value//256），参考小鱼 daymatter 表盘
-- =====================================================================
local function sub(ch, cb)
  local ok, err = pcall(function()
    dataman.subscribe(ch, uiRoot, function(obj, value)
      pcall(cb, obj, value) -- 回调内部再包一层容错
    end)
  end)
  if not ok then
    dbg("dataman.subscribe 失败 channel=" .. ch .. " err=" .. tostring(err))
  end
end

local function refreshClock()
  if clockLabel then
    clockLabel:set({ text = string.format("%02d:%02d", curHour, curMin) })
  end
end

sub("timeHourHigh", function(obj, v) curHour = (curHour % 10) + (v // 256) * 10; refreshClock() end)
sub("timeHourLow",  function(obj, v) curHour = (curHour // 10) * 10 + (v // 256); refreshClock() end)
sub("timeMinuteHigh", function(obj, v) curMin = (curMin % 10) + (v // 256) * 10; refreshClock() end)
sub("timeMinuteLow",  function(obj, v) curMin = (curMin // 10) * 10 + (v // 256); refreshClock() end)

-- 日期
local WEEK = { "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" }
sub("dateMonth", function(obj, v)
  local m = v // 256
  mStr = (m < 10) and ("0" .. m) or tostring(m)
  dateLabel:set({ text = dateText() })
end)
sub("dateDay", function(obj, v)
  local d = v // 256
  dStr = (d < 10) and ("0" .. d) or tostring(d)
  dateLabel:set({ text = dateText() })
end)
sub("dateWeek", function(obj, v)
  local w = (v // 256) + 1
  if w < 1 then w = 1 elseif w > 7 then w = 7 end
  wStr = WEEK[w]
  dateLabel:set({ text = dateText() })
end)

-- 电量 -> 刷新悬浮球内容（验证顶层控件能独立接收数据流）
sub("systemStatusBattery", function(obj, v)
  curBatt = v // 256
  if ballLabel then
    ballLabel:set({ text = curBatt .. "%" })
    dbg("悬浮球电量刷新 -> " .. curBatt .. "%")
  end
end)

dbg("==== FloatLayerDemo 初始化完成 ====")
local modeName = layerMode == "top" and "top (TOP layer)"
  or layerMode == "sys" and "sys (SYS layer)"
  or "root 兼容模式"
dbg("悬浮模式: " .. modeName)
dbg("测试: 点 'Go B ->' 切页，观察右下角绿球是否仍在、右上角 A-fake 是否消失")

-- =====================================================================
-- 7) 框架约定导出（EasyFace / Vela 表盘框架可能回调，保留空实现）
-- =====================================================================
function ScreenStateChangedCB(pre, now, reason)
end