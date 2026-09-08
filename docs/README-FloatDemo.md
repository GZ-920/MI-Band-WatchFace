# FloatLayerDemo —— 米环 Lua 表盘「顶层悬浮窗」可行性测试表盘

> 用最小工程验证：**能否在小米手环 Lua 表盘里做出"跨页面常驻、始终置顶、不挡触摸"的全局悬浮控件**。

---

## 一、结论先行（基于对 Luavgl 绑定源码的核查）

1. 小米手环/手表的 Lua 表盘底层是 **Luavgl**（`lua + lvgl` 绑定，代表实现 [XuNeo/luavgl](https://github.com/XuNeo/luavgl)，运行于 NuttX/VelaOS，并有 `luavgl-nuttx-example`）。
2. Luavgl 在 `src/disp.c` 中**确实暴露了顶层图层 API**（调用 LVGL 原生 `lv_disp_get_layer_top()/lv_disp_get_layer_sys()`）：

   ```lua
   local lvgl = require("lvgl")
   local disp = lvgl.disp.get_default()
   local topLayer = disp:get_layer_top()   -- 次顶层，位于所有 screen 之上
   local sysLayer = disp:get_layer_sys()   -- 最顶层（系统提示用）
   ```

3. 把控件创建在这两个 layer 之下，控件**不属于任何页面**，页面怎么切换/重建都不影响它 —— 这就是"表盘内全局悬浮窗"的实现本质（真正的跨 App 系统级悬浮，手环固件权限模型不允许）。

4. ⚠️ **重要限制（为什么 Demo 用"同屏双容器"模拟翻页）**：Luavgl 里 `lvgl.Object(nil, ...)` 并不是创建一个新 screen，而是挂在绑定上下文 `ctx->root`（一个创建在 `lv_scr_act()` 上的普通容器）里；源码中也没有暴露"创建新 screen / load_scr"的常规 Lua 接口。所以手环 Lua 表盘的"多页面"实际形态 = **同一屏幕内多个全屏容器互相隐藏/显示**。本 Demo 正是用这种形态验证悬浮层跨页面常驻；若未来固件暴露了 `lvgl.disp.load_scr` 之类的屏幕加载接口，顶层 layer 方案依旧成立（layer 与 screen 无关）。

---

## 二、Demo 长什么样

| 位置 | 内容 |
| --- | --- |
| 页面 A | 深色主页：大时钟、日期、底部 "Go B ->" 按钮；右上角有橙色 `A-fake` 对照标签 |
| 页面 B | 蓝色"设置模拟页"：标题 + 几行假设置项 + "<- Back A" 按钮 |
| 悬浮球 | **右下角绿色圆球，显示实时电量 %**，挂在 top/sys layer 上 |

测试时你**只需要盯住右下角绿球**：

- 点 `Go B ->`：右上角 `A-fake`（普通控件，属于页面 A）**消失**；右下角绿球（layer 控件）**仍在且在最上层**，电量继续刷新 → 证明"跨页面常驻全局悬浮"成立。
- 绿球设了 `clear_flag(CLICKABLE)` → **不拦截触摸**，球下面的页面按钮照样能点。

---

## 三、工程结构

```
FloatLayerDemo/
├── watchface.config.json          # 工程配置（已改名 FloatLayerDemo）
├── watchface/fprj/app/lua/main.lua  # ★ 本次编写的表盘代码（核心）
├── docs/README-FloatDemo.md       # 本文档
└── ... 其余为 LuaDevTemplate 模板自带工具链
```

> 代码零图片资源、纯控件绘制（Object/Label），仅用内置/动态 montserrat 字体 + ASCII 文本，避免中文字体和 .bin 图片依赖，方便直接跑。

### 代码里的模式探测与降级

| 日志关键字 | 含义 |
| --- | --- |
| `get_layer_top() OK` | ✅ 次顶层可用，悬浮球挂在 TOP layer（首选） |
| `get_layer_sys() OK` | ✅ TOP 不可用但 SYS 可用（会盖系统 UI，慎用于正式表盘） |
| `降级为 root 兼容模式` | ❌ 固件裁剪了 layer API：球挂普通 root，靠"最后创建"置顶，切页后不保证盖过后续新建的全屏页 |

---

## 四、怎么跑起来测试

### 方式 A：LuaDevTemplate 工具链（推荐，可热重载 + 看日志）

前置：Windows + Python 3 + 能 adb 连接的目标（Watch S3/手环模拟器 或 真机）。

1. `pip install -r requirements.txt`
2. 用 VS Code 打开本工程（`.vscode` 里已配好任务）：
   - `热重载`：只改了 lua 时用它，秒级生效
   - `全新部署`：改了资源时用
   - `构建表盘二进制`：产出 `bin/*.face`，可用于 `表盘自定义工具` / `MiFitness mod` 装到真机
3. 跑起来后，通过 adb 看表盘 Lua 日志：

   ```
   adb logcat | grep FLOAT
   ```

   应能看到 `悬浮模式: top`（或 sys/root 降级提示），以及点击按钮时的 `[FLOAT] button clicked -> go B` 等日志。

### 方式 B：EasyFace / 表盘自定义工具（真机 米环8/9 等）

- EasyFace 体系的手环 Lua 表盘，通常把代码放在 `app/_lua/<模块名>/<模块名>.lua`（参考 [sf-yuzifu/daymatter](https://github.com/sf-yuzifu/daymatter)）。
- 可以直接把本工程的 `main.lua` 整体替换进你已能打包的某个 Lua 表盘工程入口（本 demo 不用图片，fprj 里资源可留空/占位即可），再用 EasyFace 或米坛「表盘自定义工具」打包安装到手环。
- 表盘自定义工具：https://www.bandbbs.cn/threads/9797/

### 方式 C：EasyFace 自带 Watch S3 模拟器（最适合看 API 是否存在）

EasyFace 作者从小米 IDE 提取了手表模拟器（含 adb），可先在该模拟器上装本表盘，快速确认 `disp:get_layer_top()` 是否返回对象、有没有报错日志，再上真机。

---

## 五、测试判定清单

- [ ] 日志出现 `get_layer_top() OK`（说明 Luavgl layer API 在该固件可用）
- [ ] 页面 A 切到页面 B 后，右下角绿球仍完整可见（跨页面常驻成立）
- [ ] 页面 B 是**不透明全屏背景**，绿球仍在最上层（z-order 成立）
- [ ] 绿球上的电量百分比会随时间刷新（悬浮层能正常收 dataman 数据）
- [ ] 绿球盖住的位置，下层按钮仍可点击（事件穿透成立）
- [ ] 如果出现 `降级为 root 兼容模式` → 说明该固件裁剪了 layer API，需走"每个页面各自放一份 + 共享状态同步"的兜底方案

---

## 六、常见问题

**Q1：切页后绿球看不到 / 日志报 `layer API 不可用`？**
A：该固件/镜像的 Luavgl 可能裁剪了 disp 接口。先试 EasyFace 的 Watch S3 模拟器或 Band 9 Pro / 10 的较新固件；若都不行，用文档说的 root 兼容模式或"每页一份控件"兜底。

**Q2：中文字显示不出来？**
A：本 demo 刻意全用 ASCII。正式表盘如需中文，要在项目里带字库（如 `MiSans` 相关 .ttf/.bin），参考 daymatter 的 `lvgl.Font('MiSans-...')` 写法。

**Q3：时钟/日期没变化？**
A：dataman 通道名在不同表盘框架可能不同。本 demo 用的是 daymatter 表盘验证过的通道：`timeHourHigh/Low`、`timeMinuteHigh/Low`、`dateMonth/Day/Week`、`systemStatusBattery`。若你的框架通道命名不同，改 `sub("...")` 里的通道名即可（常见变体如 `timeHour`、`sportData` 等）。

**Q4：lvglVersion 是 9，我手环是 Band 8P/手表 S3 怎么办？**
A：在 `watchface.config.json` 把 `resourceBin.lvglVersion` 改成 `8`（README 原文说明：S3/Band8P 仅支持 lvgl v8），代码主体不受影响。

**Q5：浮球想可点击（点它干点什么）？**
A：把 `ball:clear_flag(lvgl.FLAG.CLICKABLE)` 去掉，改成 `ball:add_flag(lvgl.FLAG.CLICKABLE)` 并 `ball:onevent(lvgl.EVENT.CLICKED, ...)`。注意可点击后它就会拦截触摸，需要自己处理与下层热区的冲突。

---

## 七、没有电脑怎么打包（手机端/云端编译方案）

### 为什么不能直接在手机上"官方打包"

经过实际逆向验证：官方编译器 `Compiler.exe` 是 **.NET 程序**，可以在 Linux/mono 上运行（本项目已把它跑到"加载工程→生成 face 计划"阶段），但有两个跨不过去的点：

1. 它内嵌的 ImageMagick.NET 需要一个 **Windows 专属(WPF)程序集** —— 已在 Linux 用"最小占位 dll"骗过；
2. 它依赖的 ImageMagick native 库（NuGet 官方包）**只提供 linux-x64，没有 arm64** —— 而手机是 arm64 架构，这是硬限制。

**结论**：在 arm64 手机本地跑不动官方编译器，但任何 **x86_64 环境**都能一键编译。

### 方案①：GitHub Actions 免费云端编译（推荐，全程手机浏览器）

本工程已内置自动编译工作流（`.github/workflows/build-face.yml` + `linux/build_face_linux.sh`），云端的 x86_64 runner 会自动完成所有破解步骤并产出 `.face`。

操作步骤（全程手机浏览器，无需电脑）：

1. 手机浏览器打开 https://github.com 注册并登录；
2. 右上角 `+` → New repository，建一个 **Public** 仓库（例如 `FloatLayerDemo`），不要勾选任何初始化文件；
3. 进入仓库 → `Add file` → `Upload files`，把**本工程压缩包 FloatLayerDemo.zip** 直接拖进去上传（仓库里只有一个 zip 即可，工作流会自动解压并识别工程）；
4. 等上传完成 → 打开仓库 `Actions` 页，工作流 `Build FloatLayerDemo .face` 会自动开始（也可点 `Run workflow` 手动触发）；
5. 几分钟后构建完成，点进该次运行 → 底部 **Artifacts** → 下载 `FloatLayerDemo-face`，里面就是 `FloatLayerDemo.face`；
6. 用手机上的「表盘自定义工具」/「Notify for Mi Band」导入这个 `.face` 同步到手环即可。

> GitHub Actions 对公开仓库免费。首次使用需在仓库 Settings → Actions → General 允许 workflow（默认允许）。

### 方案②：任意一台 x86_64 Linux（含 WSL、云服务器）

```bash
sudo apt install -y mono-runtime mono-mcs libgdiplus libmono-system-drawing4.0-cil python3 unzip
bash linux/build_face_linux.sh          # 产物在 bin/FloatLayerDemo.face
```

脚本会自动完成：伪 WPF 占位 dll 编译、ImageMagick native(linux-x64) 下载、反斜杠字面路径布置、mono 调官方编译器、ID 修正。

### 方案③：让社区帮编译（零成本人工云编译）

把 `watchface/fprj/app/lua/main.lua`（或整个工程 zip）发到米坛社区/EasyFace 交流群，请人用 EasyFace/官方工具代打包一次 `.face`。这是目前很多无电脑开发者实际使用的方式。

---

## 八、参考资料

- Luavgl 绑定源码（disp.c 中 layer API、obj.c 中对象机制）：https://github.com/XuNeo/luavgl
- LuaDevTemplate（本工程基底，Vela/QuickApp 表盘 Lua 模板）：https://github.com/FangAiden/LuaDevTemplate
- daymatter（真实发布的手环 Lua 表盘，dataman 通道参考）：https://github.com/sf-yuzifu/daymatter
- EasyFace（表盘编辑器/打包/模拟器）：https://github.com/m0tral/EasyFace
- 米坛社区「表盘自定义工具」：https://www.bandbbs.cn/threads/9797/