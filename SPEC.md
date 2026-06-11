# Logpad - macOS 日志查看器

## 1. 产品概述

**产品名称：** Logpad  
**产品类型：** macOS 桌面应用  
**核心定位：** 专为查看大型文本日志文件设计的轻量级工具，类似 Notepad++ 的日志浏览体验  
**目标用户：** 开发者、高级用户在 macOS 上偶尔查看日志文件

---

## 2. 功能规格

### 2.1 核心功能

| 功能 | 描述 | 优先级 | 状态 |
|------|------|--------|------|
| 文件打开 | 通过文件选择器、拖拽或 Finder 双击/「打开方式」打开 `.log` / `.txt` 等纯文本文件 | P0 | 已实现 |
| 日志浏览 | 等宽字体、行号列、横纵滚动，按行按需读取 | P0 | 已实现 |
| 跳转行号 | `Cmd+G` 弹出对话框，输入 1-based 行号跳转定位 | P0 | 已实现 |
| 关键词搜索 | 工具栏实时搜索，支持正则、大小写选项，匹配片段黄色高亮 | P0 | 已实现 |
| 搜索导航 | `Enter` 下一条匹配，`Shift+Enter` 上一条匹配；搜索框右侧上/下箭头按钮可点击导航（悬停显示快捷键） | P0 | 已实现 |
| 文本标记 | 选中文字后 `Cmd+M`（或右键 Mark）选色，全文件高亮所有相同文本；右键可按颜色取消标记或清除全部 | P1 | 已实现 |
| 大文件支持 | 后台分块建立行索引，不将整个文件载入内存 | P0 | 已实现 |
| 双窗口分割 | 主日志区 + 过滤结果区，支持单窗 / 水平 / 垂直三种布局，分割线可拖动调整占比；过滤结果面板顶部显示文件路径与匹配统计 | P0 | 已实现 |
| 搜索自动分屏 | 搜索过滤词后若当前为单窗口，自动切换为上下分割显示过滤结果面板 | P1 | 已实现 |
| 搜索预设侧栏 | 左侧栏按「组（带组名）→ 多个过滤词」管理预设；点组套用组内全部词（`\|` 合并），点词套用单词，均追加到搜索框并自动开启 Regex；侧栏内联增删改组/词，`UserDefaults` 持久化、全窗口共享 | P1 | 已实现 |
| 联动跳转 | 点击过滤结果列表中的行，主视图滚动到对应行 | P0 | 已实现 |
| 双语界面 | 中英文文案，工具栏可手动切换语言 | P1 | 已实现 |
| App 图标 | macOS Dock 图标与应用窗口图标 | P1 | 已实现 |
| 外部修改检测 | 文件被外部写入/删除/替换时提示，可一键重新加载 | P1 | 已实现 |
| 多窗口 / 多标签页 | `Cmd+N` 打开新 app 窗口，`Cmd+T` 在当前窗口新建标签页；各窗口/标签页拥有独立文件与搜索状态 | P1 | 已实现 |

### 2.2 快捷键与菜单

| 快捷键 | 功能 |
|--------|------|
| `Cmd+N` | 打开新的独立 app 窗口 |
| `Cmd+T` | 在当前窗口新建标签页 |
| `Cmd+O` | 打开文件 |
| `Cmd+F` | 聚焦搜索框 |
| `Cmd+G` | 跳转到指定行号 |
| `Cmd+M` | 对当前选中文本添加颜色标记 |
| `Cmd+Shift+M` | 取消当前选中文本的标记 |
| `Cmd+R` | 文件被外部修改提示时，重新加载文件 |
| `Enter` | 搜索框：首次执行搜索；已有结果时跳到下一条 |
| `Shift+Enter` | 搜索框：跳到上一条匹配 |

### 2.3 用户交互

#### 文件

- **打开**：菜单 / `Cmd+O` / 工具栏文件夹按钮 / 拖拽到窗口 / Finder 双击或「打开方式」（已运行时在新标签页打开）
- **空状态**：未打开文件时显示引导页
- **错误**：文件不存在或无法读取时显示错误页，可重试

#### 搜索

- 工具栏搜索框输入关键词后**实时**扫描全文件
- **搜索完成后若当前为单窗口模式，自动切换为上下分割（`VSplitView`）显示过滤结果面板**；已处于任意分屏模式时不改变当前布局；清空搜索词不会自动关闭已打开的分屏
- 勾选 **Regex** 启用正则；勾选 **Aa** 区分大小写
- **Regex / Aa 选项状态持久化**（写入 `UserDefaults`），重启 app 后保持上次设置；搜索关键词本身不持久化
- 主视图：匹配片段**黄色**背景高亮（非整行）
- 分屏模式下：过滤结果面板列出匹配行（行号 + 内容预览），**每个匹配行只显示一条**（同一行含多个匹配词不重复列出）；预览中的匹配片段与主视图一致以**黄色**背景高亮；面板顶部**同时显示文件路径与「结果」计数**
- `Enter` / `Shift+Enter` 在主视图内**逐个匹配**循环跳转（同一行的多个匹配也会依次跳到）；搜索框右侧的上/下箭头按钮等效于 `Shift+Enter` / `Enter`，鼠标悬停显示对应快捷键，无结果时禁用
- 点击结果面板中的某行，跳转并聚焦该行的**第一个**匹配，之后的 `Enter`/箭头从该匹配继续
- 当前导航到的匹配以**更深的黄橙色**背景标示（其余匹配为普通黄色），便于辨认正聚焦的是哪一个

#### 搜索预设侧栏

排查某类问题时过滤词往往固定。用窗口左侧的「预设侧栏」按**组**管理常用过滤词，下次直接点击套用，不必重新输入。

- **形态**：预设按「组 → 多个过滤词」两层组织。每个**组**有组名（**全局唯一，不区分大小写**；新建/重命名时重名会弹提示并保持编辑态不提交），组内含若干**过滤词**（纯文本字符串，不单独保存 Regex/Aa）
- **侧栏显隐**：工具栏最左侧新增侧栏开关按钮（图标 `sidebar.left`，激活态高亮），切换左侧栏显示/隐藏；**显隐状态每个窗口/标签页独立**；侧栏与右侧日志区组成 `HSplitView`，分割线可拖动调整侧栏宽度
- **套用预设**（追加语义）：
  - 点击**组名**：把组内所有过滤词用 `|` 合并后**追加**到搜索框（若搜索框已有内容，用 `|` 连接到其后）
  - 点击**单个过滤词**：把该词**追加**到搜索框
  - 因为以 `|` 连接（正则语法），套用时**自动打开 Regex 开关**；大小写沿用当前工具栏的 Aa 设置
  - 套用后等同正常输入搜索：触发搜索、单窗口下自动分屏
- **折叠/展开**：含过滤词的组名左侧显示展开箭头（`chevron.down` / `chevron.right`），点击折叠或展开组内过滤词；折叠状态按组持久化（`UserDefaults` 键 `collapsedPresetGroupIDs`），重启后保留；折叠态下点「加词」会先自动展开
- **增删改**（全部内联在侧栏完成）：
  - 顶部「+」新建组（内联输入组名）
  - 组名行悬停显示「重命名 / 加词 / 删组」：重命名、加词为内联输入框；删组带确认对话框
  - 过滤词行悬停显示「编辑 / 删除」：编辑为内联输入框，删除即时
  - 内联输入框失焦（点击主窗口或侧栏空白处）即提交并收起
- **持久化**：所有预设组写入 `UserDefaults` 的 `filterPresetGroups` 键，值为 JSON 编码的 `[FilterPresetGroup]`；由单例 `PresetStore.shared` 持有，全窗口/标签页共享同步；卸载 app 或清除沙盒数据时丢失
- **本地化**：侧栏标题、按钮提示、对话框文案均跟随工具栏语言切换
- **v1 不提供**：导入/导出、快捷键直接套用、云同步、组拖拽排序

#### 跳转行号

- `Cmd+G` 弹出「跳转到行」对话框
- 行号为 **1-based**，与左侧行号列一致
- 显示有效范围提示；超出范围时显示错误提示
- 确认后主视图滚动定位到目标行

#### 文本标记

用于在日志中持久高亮关注的关键词（如错误码、模块名）：

1. 在主日志区**选中**一段文字（AppKit `NSTextView`，支持真实文本选择）
2. 触发标记：
   - **`Cmd+M`**（需先选中文字，选区会同步到 `MarkCoordinator`）
   - 或右键菜单 **Mark**
3. 弹出颜色选择面板，可选：红 / 橙 / 绿 / 蓝 / 紫
4. 确认后，在**全文件**内查找所有与选中文本相同的内容（**不区分大小写**），以所选颜色背景高亮
5. 可多次标记不同关键词，各标记独立着色；搜索高亮（黄色）与标记高亮可同时显示
6. **取消标记**：
   - 右键菜单 →「取消标记」子菜单，**按颜色**列出当前在用的标记色（带色块），点击某色即时移除该颜色的全部标记；子菜单底部「清除全部标记」一次性清空。无选区时右键也会显示该菜单（只要存在标记）
   - **`Cmd+Shift+M`**：取消当前选中文本的标记（`Cmd+M` 的逆操作，按文本不区分大小写匹配）

#### 分割布局

- 工具栏三个图标：单窗口 / 上下分割 / 左右分割
- 分割模式下才显示过滤结果面板
- 左右分割（`HSplitView`）与上下分割（`VSplitView`）的分割线均可拖动以调整两区占比

#### 多窗口 / 标签页

- `Cmd+N` 打开一个全新的独立 app 窗口；`Cmd+T` 在当前窗口新建标签页（macOS 原生标签）。两者都新开一个空白视图（显示打开引导页），可分别打开不同文件
- 每个窗口/标签页持有独立的 `FileReader` 与 `SearchEngine`，文件内容、搜索结果、标记互不影响
- 窗口标题各自反映本窗口当前文件名（不再共用 `NSApp.windows.first`）
- 菜单/快捷键命令（`Cmd+O/F/G/M`、`Cmd+Shift+M`、`Shift+Enter`）只作用于当前**激活（key）窗口**，不会广播到其它窗口；右键标记菜单与 `Cmd+M`/`Cmd+Shift+M` 始终作用于当前激活窗口的标记状态
- **外部打开**：Finder 双击 / 「打开方式」→ Logpad 时，冷启动直接在初始窗口打开文件；app 已显示文件时则在当前窗口的**新标签页**打开
- **窗口恢复**：关闭 macOS 自动窗口恢复（`NSQuitAlwaysKeepsWindows=false`），并在启动 / 打开文件后清理多余的空闲独立窗口（最多保留一个引导页；已显示文件时不保留），避免空状态窗口累积

### 2.4 数据处理

- **行索引**：后台按 4MB 分块、用 `memchr` 扫描换行符建立行偏移表（O(n)），打开后按需 `seek` 读单行；文件读取加锁串行化，保证后台搜索与 UI 渲染并发安全
- **索引进度**：`open()` 记录文件总字节数 `fileSize`，索引循环按「已扫描字节 / 总字节」计算 `indexProgress`（0…1），节流约每前进 1% 才向主线程上报一次，避免多 GB 文件刷屏；文件大小 ≥ `indexProgressByteThreshold`（20MB）时主视图显示确定性进度条（`LoadingView`），小文件秒级完成不展示以免闪烁
- **编码**：打开时读取 64KB 头采样做严格解码，先按 BOM / UTF-8 识别；否则同时尝试 GB18030（GBK 超集）与 Big5 并按解码质量评分（CJK Unified Ideographs +1，非 ASCII 非 CJK × -3 罚分，GB18030 解 Big5 字节会落到日文假名 / 杂项符号而被罚低），高分者胜出，平局默认 GB18030；结果存于 `FileReader.encoding`，`readLine` 与 `SearchEngine` 共用，工具栏右端实时显示当前编码名
- **搜索管道**：后台线程顺序流式扫描文件（`forEachLineBytes`），先用字节级预筛（`ByteNeedle`：`memmem` / ASCII 折叠）筛选，命中行才解码为 `String` 并算精确高亮；输入带 250ms debounce
- **标记管道**：标记**不做全文件预扫描**；`SearchEngine.addMark` 仅记录标记，渲染时由 `markRanges(in:)` 对每个可见行的内容即时计算命中范围（开销与可见行数成正比，与文件大小无关），避免大文件下添加标记触发整文件扫描造成 CPU 飙升
- **虚拟滚动**：`VirtualLogView` 基于 `NSTableView` 行回收渲染，仅创建可见区域 ± 缓冲的行视图，内存与视图数量与文件大小无关
- **外部修改检测**：`FileReader` 用 `DispatchSource` 文件系统监听（`O_EVTONLY` 描述符，监听 write / extend / delete / rename / revoke），事件经 0.5s debounce 合并后置位 `fileChangedExternally`，UI 显示提示条；`reload()` 递增 `reloadGeneration` 后重新索引，`VirtualLogView` 据此恢复重载前的顶部可见行（夹取到新行数范围内）

### 2.5 边缘情况

| 场景 | 行为 |
|------|------|
| 文件不存在 / 无权限 | 显示错误提示，可重试打开 |
| 未打开文件 / 空文件 | 显示占位引导页 |
| 未打开文件时 `Cmd+G` | 不响应 |
| 跳转行号超出范围 | 对话框内提示，不跳转 |
| 未选中文字时 `Cmd+M` | 不弹出颜色面板 |
| 超大文件（>1GB） | 首次索引时显示确定性进度条（已扫描字节 / 文件总大小，节流约每 1% 刷新），完成后进入浏览 |
| 文件在外部被修改 | 检测到写入/删除/替换后，工具栏下方提示条，可重新加载（`Cmd+R`，保持滚动位置）或忽略 |

---

## 3. 技术方案

### 3.1 技术栈

- **框架**：SwiftUI + AppKit（`NSTextView` 承载可选中文本行）
- **架构**：MVVM，`FileReader` / `SearchEngine` 与视图分离
- **文件读取**：`FileHandle` 分块索引 + 按偏移读行
- **UI 渲染**：`LazyVStack` + `ScrollViewReader` 实现滚动与行定位

### 3.2 模块划分（实际代码结构）

```
Logpad/Logpad/
├── LogpadApp.swift          # App 入口、菜单与快捷键
├── WindowManager.swift      # 多窗口/标签页创建、窗口引用解析
├── ContentView.swift        # 根视图、Shift+Enter 监听
├── MainView.swift           # 主界面、工具栏、分屏、GoToLine / Mark 弹窗
├── SelectableLogView.swift  # 单行日志（NSTextView + 高亮）
├── PresetStore.swift        # 搜索预设组的全局存储与 UserDefaults 持久化
├── PresetSidebarView.swift  # 左侧预设侧栏（分组列表、内联增删改、套用）
├── FileReader.swift         # 大文件分块索引与按行读取
├── EncodingDetector.swift   # 打开时按字节采样识别文件编码
├── SearchEngine.swift       # 搜索、正则匹配、标记扫描
├── VirtualScrollManager.swift  # 虚拟滚动（预留，未接入主列表）
├── Models.swift             # LogLine、FilterCondition、HighlightMark 等
├── LanguageManager.swift    # 语言切换
├── i18n.swift
├── en.lproj/
├── zh-Hans.lproj/
└── Assets.xcassets/
```

---

## 4. 非功能规格

| 指标 | 要求 |
|------|------|
| 启动速度 | < 1 秒 |
| 100MB 文件打开 | < 2 秒（行索引完成） |
| 内存占用 | < 100MB（无论文件多大） |
| 滚动流畅度 | 60 FPS |

---

## 5. 里程碑

| 阶段 | 内容 | 状态 |
|------|------|------|
| M1 | 项目初始化，基本窗口 + 文件打开 | 已完成 |
| M2 | 大文件行索引 + 按行浏览 | 已完成 |
| M3 | 搜索 / 高亮 / 分屏 / 联动跳转 | 已完成 |
| M4 | 跳转行号、文本标记、搜索导航、双语界面 | 已完成 |
| M5 | 虚拟滚动接入（已完成）、文件变更检测（已完成）、GBK 编码（已完成）、超大文件索引进度条（已完成） | 已完成 |
| M6 | 搜索预设侧栏（组 / 词、内联增删改、点组/点词套用、UserDefaults 持久化、全窗口共享） | 已完成 |

---

## 6. 版本管理

采用语义化版本（SemVer），版本号定义在 Xcode 项目 `MARKETING_VERSION`，Build 号在 `CURRENT_PROJECT_VERSION`。运行时通过 `AppVersion.swift` 从 Bundle 读取，在菜单 **Logpad → 关于 Logpad** 中展示。

| 变更类型 | 版本号变化 |
|----------|------------|
| Bug 修复 | PATCH +1（如 1.0.0 → 1.0.1） |
| 新功能 | MINOR +1（如 1.0.1 → 1.1.0） |
| 重大不兼容变更 | MAJOR +1（如 1.1.0 → 2.0.0） |

每次发版需同步更新 `VERSION.md` 变更记录，并递增 Build 号。详见 [VERSION.md](VERSION.md)。

---

## 7. 打包 / 分发

将 app 打包成 DMG，供其他 Mac 安装测试。

### 7.1 一键打包

仓库根目录提供 `build_dmg.sh`：

```bash
./build_dmg.sh
```

脚本流程：

1. `xcodebuild -configuration Release` 构建出 `Logpad.app`
2. 把 `.app` 与 `/Applications` 软链放入暂存目录
3. `hdiutil` 压成 `build/Logpad-<MARKETING_VERSION>.dmg`

产物：`build/Logpad-<版本>.dmg`（约 1.6MB）。

### 7.2 构建约定

| 项 | 取值 | 说明 |
|---|---|---|
| 架构 | **arm64 only** | 仅支持 Apple Silicon，不构建 Intel/通用二进制 |
| 签名 | **ad-hoc**（`CODE_SIGN_IDENTITY = -`） | 无 Apple Developer 证书，未公证；仅供内部测试 |
| 部署目标 | `MACOSX_DEPLOYMENT_TARGET = 26.5` | 测试机需运行 macOS 26.5+ |
| 沙盒 | `ENABLE_APP_SANDBOX = YES`，文件只读 | — |

### 7.3 测试者首次打开（绕过 Gatekeeper）

因 ad-hoc 签名且未公证，从网络/隔离来源拿到的 DMG 首次打开会被 Gatekeeper 拦截。任选其一，仅需一次：

- **右键打开**：「应用程序」中右键 `Logpad` → 打开 → 弹窗再点「打开」
- 若提示"已损坏 / 无法打开"，终端执行一次：

```bash
xattr -dr com.apple.quarantine /Applications/Logpad.app
```

### 7.4 正式分发（未来）

若取得 Apple Developer 账号，应改为 **Developer ID Application 签名 + `notarytool` 公证 + `stapler` 装订**，分发即无 Gatekeeper 警告，无需上述手动步骤。

---

## 8. 参考资料

- [AppKit 文档](https://developer.apple.com/documentation/appkit)
- [SwiftUI macOS 文档](https://developer.apple.com/documentation/swiftui/macos)

---

## 9. 数据类型定义

### 9.1 核心结构

```swift
// 单行日志
struct LogLine: Identifiable {
    let id: Int          // 行号（1-based）
    let content: String  // 该行原始文本
}

// 搜索结果
struct FilterResult: Identifiable {
    let id: UUID
    let line: LogLine
    let highlightRange: Range<String.Index>?  // 匹配片段，用于黄色高亮
}

// 搜索条件
struct FilterCondition {
    var keyword: String
    var isRegex: Bool
    var isCaseSensitive: Bool
}

// 分割模式
enum SplitMode: String, CaseIterable {
    case none         // 单窗口
    case horizontal   // 上下分割
    case vertical     // 左右分割
}

// 文本标记
struct HighlightMark {
    let text: String
    let color: HighlightColor  // red / orange / green / blue / purple
}

// 搜索预设：组 → 多个过滤词
struct FilterPresetWord: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String              // 纯文本过滤词
}

struct FilterPresetGroup: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String              // 组名（全局唯一，不区分大小写）
    var words: [FilterPresetWord]
}
```

---

## 10. 模块职责

| 文件 | 职责 |
|------|------|
| `LogpadApp.swift` | App 入口；`NSApplicationDelegate` 接收 Finder 传入文件；注册 `Cmd+N/T/O/F/G/M` 菜单命令 |
| `WindowManager.swift` | `Cmd+N` 新建独立窗口 / `Cmd+T` 新建标签页；`WindowAccessor` / `WindowHolder` 解析视图所属窗口 |
| `ContentView.swift` | 根视图；`Shift+Enter` 全局监听 |
| `MainView.swift` | 主布局、工具栏、分屏、`GoToLineView` / `MarkMenuView` |
| `SelectableLogView.swift` | 单行 `NSTextView`：文本选择、右键 Mark、片段高亮 |
| `PresetStore.swift` | 单例 `ObservableObject`，预设组的增删改与 `UserDefaults` 持久化（键 `filterPresetGroups`），全窗口共享 |
| `PresetSidebarView.swift` | 左侧预设侧栏：分组/词列表、内联增删改、点组/点词回调套用 |
| `FileReader.swift` | 分块建索引（含 `indexProgress` / `fileSize` 进度上报）、`readLine(at:)` |
| `SearchEngine.swift` | `search(condition:)`、`addMark(_:)` / `markRanges(in:)` |
| `VirtualScrollManager.swift` | 可见行范围（预留） |
| `LanguageManager.swift` / `i18n.swift` | 中英文本地化 |

---

## 11. 验收标准

### M1 - 文件打开

- [x] App 正常启动，显示主窗口
- [x] 文件选择器 / 拖拽打开 `.txt` / `.log`
- [x] 窗口标题显示当前文件名

### M2 - 大文件浏览

- [x] 大文件后台建索引，打开后不整文件载入内存
- [x] 左侧行号正确（1-based）
- [x] 空文件 / 未打开文件显示占位
- [x] 100MB 文件 2 秒内可浏览；内存 < 100MB

### M3 - 搜索与高亮

- [x] `Cmd+F` 聚焦搜索框
- [x] 关键词实时搜索，匹配片段黄色高亮
- [x] 支持正则、大小写选项
- [x] 分屏显示过滤结果列表
- [x] 点击结果行 / `Enter` / `Shift+Enter` 跳转匹配行
- [x] 单窗口下输入搜索词后自动切换为上下分割显示过滤结果面板；手动切到其它布局时不会被搜索覆盖

### M4 - 跳转、标记与国际化

- [x] `Cmd+G` 跳转指定行号，含范围校验
- [x] 选中文本后 `Cmd+M` 或右键 Mark 弹出颜色面板
- [x] 标记后全文件相同文本以所选颜色高亮
- [x] 中英文界面，工具栏可切换语言
- [x] 单窗 / 水平 / 垂直分割可切换

### M5 - 部分完成

- [x] 真正虚拟滚动（`NSTableView` 行回收，不创建全部行视图）
- [x] 外部文件修改检测与提示（写入/删除/替换，重新加载并保持滚动位置）
- [x] GBK 等编码自动检测
- [x] 超大文件索引进度条（确定性进度条，按字节进度刷新）

### M6 - 搜索预设侧栏

- [x] 工具栏侧栏开关按钮切换左侧栏显隐（每窗口独立），分割线可拖动调整侧栏宽度
- [x] 侧栏内联新建/重命名/删除组（删组带确认、组名重名校验不区分大小写）、添加/编辑/删除过滤词
- [x] 点击组名套用组内全部词（`|` 合并）、点击单词套用单词，均追加到搜索框并自动开启 Regex，触发搜索与自动分屏
- [x] 预设写入 UserDefaults（`filterPresetGroups`），随 app 重启保留，全窗口/标签页共享同步
- [x] 侧栏标题、按钮提示、对话框文案随工具栏语言切换
