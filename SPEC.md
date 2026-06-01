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
| 文件打开 | 通过文件选择器或拖拽打开 `.log` / `.txt` 等纯文本文件 | P0 | 已实现 |
| 日志浏览 | 等宽字体、行号列、横纵滚动，按行按需读取 | P0 | 已实现 |
| 跳转行号 | `Cmd+G` 弹出对话框，输入 1-based 行号跳转定位 | P0 | 已实现 |
| 关键词搜索 | 工具栏实时搜索，支持正则、大小写选项，匹配片段黄色高亮 | P0 | 已实现 |
| 搜索导航 | `Enter` 下一条匹配，`Shift+Enter` 上一条匹配；搜索框右侧上/下箭头按钮可点击导航（悬停显示快捷键） | P0 | 已实现 |
| 文本标记 | 选中文字后 `Cmd+M`（或右键 Mark）选色，全文件高亮所有相同文本 | P1 | 已实现 |
| 大文件支持 | 后台分块建立行索引，不将整个文件载入内存 | P0 | 已实现 |
| 双窗口分割 | 主日志区 + 过滤结果区，支持单窗 / 水平 / 垂直三种布局，分割线可拖动调整占比 | P0 | 已实现 |
| 联动跳转 | 点击过滤结果列表中的行，主视图滚动到对应行 | P0 | 已实现 |
| 双语界面 | 中英文文案，工具栏可手动切换语言 | P1 | 已实现 |
| 外部修改检测 | 文件被外部写入/删除/替换时提示，可一键重新加载 | P1 | 已实现 |

### 2.2 快捷键与菜单

| 快捷键 | 功能 |
|--------|------|
| `Cmd+O` | 打开文件 |
| `Cmd+F` | 聚焦搜索框 |
| `Cmd+G` | 跳转到指定行号 |
| `Cmd+M` | 对当前选中文本添加颜色标记 |
| `Cmd+R` | 文件被外部修改提示时，重新加载文件 |
| `Enter` | 搜索框：首次执行搜索；已有结果时跳到下一条 |
| `Shift+Enter` | 搜索框：跳到上一条匹配 |

### 2.3 用户交互

#### 文件

- **打开**：菜单 / `Cmd+O` / 工具栏文件夹按钮 / 拖拽到窗口
- **空状态**：未打开文件时显示引导页
- **错误**：文件不存在或无法读取时显示错误页，可重试

#### 搜索

- 工具栏搜索框输入关键词后**实时**扫描全文件
- 勾选 **Regex** 启用正则；勾选 **Aa** 区分大小写
- **Regex / Aa 选项状态持久化**（写入 `UserDefaults`），重启 app 后保持上次设置；搜索关键词本身不持久化
- 主视图：匹配片段**黄色**背景高亮（非整行）
- 分屏模式下：过滤结果面板列出匹配行（行号 + 内容预览），**每个匹配行只显示一条**（同一行含多个匹配词不重复列出）；预览中的匹配片段与主视图一致以**黄色**背景高亮；面板顶部「结果」计数为**匹配总数**（含同行多个匹配），非行数
- `Enter` / `Shift+Enter` 在主视图内**逐个匹配**循环跳转（同一行的多个匹配也会依次跳到）；搜索框右侧的上/下箭头按钮等效于 `Shift+Enter` / `Enter`，鼠标悬停显示对应快捷键，无结果时禁用
- 点击结果面板中的某行，跳转并聚焦该行的**第一个**匹配，之后的 `Enter`/箭头从该匹配继续
- 当前导航到的匹配以**更深的黄橙色**背景标示（其余匹配为普通黄色），便于辨认正聚焦的是哪一个

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

#### 分割布局

- 工具栏三个图标：单窗口 / 上下分割 / 左右分割
- 分割模式下才显示过滤结果面板
- 左右分割（`HSplitView`）与上下分割（`VSplitView`）的分割线均可拖动以调整两区占比

### 2.4 数据处理

- **行索引**：后台按 4MB 分块、用 `memchr` 扫描换行符建立行偏移表（O(n)），打开后按需 `seek` 读单行；文件读取加锁串行化，保证后台搜索与 UI 渲染并发安全
- **编码**：优先 UTF-8，失败回退 ISO Latin-1（GBK 等待实现）
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
| 超大文件（>1GB） | 首次索引时显示加载状态（进度条待完善） |
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
├── ContentView.swift        # 根视图、Shift+Enter 监听
├── MainView.swift           # 主界面、工具栏、分屏、GoToLine / Mark 弹窗
├── SelectableLogView.swift  # 单行日志（NSTextView + 高亮）
├── FileReader.swift         # 大文件分块索引与按行读取
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
| M5 | 虚拟滚动接入（已完成）、文件变更检测（已完成）、GBK 编码 | 部分完成 |

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

## 7. 参考资料

- [AppKit 文档](https://developer.apple.com/documentation/appkit)
- [SwiftUI macOS 文档](https://developer.apple.com/documentation/swiftui/macos)

---

## 8. 数据类型定义

### 8.1 核心结构

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
```

---

## 9. 模块职责

| 文件 | 职责 |
|------|------|
| `LogpadApp.swift` | App 入口；注册 `Cmd+O/F/G/M` 菜单命令 |
| `ContentView.swift` | 根视图；`Shift+Enter` 全局监听 |
| `MainView.swift` | 主布局、工具栏、分屏、`GoToLineView` / `MarkMenuView` |
| `SelectableLogView.swift` | 单行 `NSTextView`：文本选择、右键 Mark、片段高亮 |
| `FileReader.swift` | 分块建索引、`readLine(at:)` |
| `SearchEngine.swift` | `search(condition:)`、`addMark(_:)` / `markRanges(in:)` |
| `VirtualScrollManager.swift` | 可见行范围（预留） |
| `LanguageManager.swift` / `i18n.swift` | 中英文本地化 |

---

## 10. 验收标准

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

### M4 - 跳转、标记与国际化

- [x] `Cmd+G` 跳转指定行号，含范围校验
- [x] 选中文本后 `Cmd+M` 或右键 Mark 弹出颜色面板
- [x] 标记后全文件相同文本以所选颜色高亮
- [x] 中英文界面，工具栏可切换语言
- [x] 单窗 / 水平 / 垂直分割可切换

### M5 - 部分完成

- [x] 真正虚拟滚动（`NSTableView` 行回收，不创建全部行视图）
- [x] 外部文件修改检测与提示（写入/删除/替换，重新加载并保持滚动位置）
- [ ] GBK 等编码自动检测
- [ ] 超大文件索引进度条
