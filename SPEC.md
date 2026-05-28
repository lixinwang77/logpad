# Logpad - macOS 日志查看器

## 1. 产品概述

**产品名称：** Logpad
**产品类型：** macOS 桌面应用
**核心定位：** 专为查看大型文本日志文件设计的轻量级工具，类似 Notepad++ 的日志浏览体验
**目标用户：** 开发者、高级用户在 macOS 上偶尔查看日志文件

---

## 2. 功能规格

### 2.1 核心功能

| 功能 | 描述 | 优先级 |
|------|------|--------|
| 文件打开 | 通过文件选择器或拖拽打开 .log/.txt 等文本文件 | P0 |
| 日志浏览 | 支持滚动、定位、跳转行号 | P0 |
| 关键词搜索 | 支持正则表达式、高亮匹配结果 | P0 |
| 大文件支持 | 处理 100MB+ 甚至 GB 级文件不卡顿 | P0 |
| 双窗口分割 | 主日志窗口 + 过滤结果窗口，支持水平/垂直分割布局 | P0 |
| 联动跳转 | 点击过滤结果窗口中的日志行，主窗口跳转定位 | P0 |
| 双语界面 | 中英文切换，界面跟随系统语言 | P1 |

### 2.2 用户交互

- **打开文件**：文件选择对话框 / 拖拽文件到窗口
- **搜索**：Cmd+F 调出搜索面板，输入关键词实时匹配
- **跳转行号**：Cmd+G 输入行号直接跳转
- **滚屏**：支持流畅滚动，不预加载整个文件到内存
- **分割布局**：通过工具栏按钮或快捷键切换「水平分割/垂直分割/单窗口」模式，主日志窗口与过滤结果窗口各占一半
- **联动跳转**：点击过滤结果窗口中的某一条日志，主日志窗口自动滚动定位到对应行

### 2.3 数据处理

- **虚拟滚动**：只渲染可见区域内容，内存占用恒定
- **增量加载**：按需从文件读取分片数据
- **编码支持**：UTF-8、GBK、Latin-1 等常见编码自动检测
- **过滤管道**：搜索条件同步驱动主视图高亮 + 整合面板收集，无需两次解析文件

### 2.4 边缘情况

- 文件不存在或无权限：显示友好错误提示
- 文件为空：显示"空文件"占位
- 超大文件（>1GB）：首次打开显示进度提示
- 文件在外部被修改：检测变化并提示用户

---

## 3. 技术方案

### 3.1 技术栈

- **框架**：纯 SwiftUI（现代声明式 UI，自定义虚拟滚动）
- **架构**：MVVM，核心逻辑与 UI 分离
- **文件读取**：分片读取 + RandomAccessFile，绕过内存限制
- **UI 渲染**：自定义虚拟列表（LazyVStack 改造）

### 3.2 模块划分

```
Logpad/
├── App/
│   ├── main.swift
│   ├── AppDelegate.swift
│   └── LogpadApp.swift
├── Core/
│   ├── FileReader.swift       # 大文件分片读取
│   ├── VirtualScroll.swift    # 虚拟滚动引擎
│   └── SearchEngine.swift     # 搜索/正则匹配
├── UI/
│   ├── MainWindow.swift
│   ├── SplitViewController.swift  # 分割视图管理
│   ├── LogTextView.swift
│   ├── FilterResultView.swift    # 过滤结果窗口
│   ├── SearchPanel.swift
│   └── FilterPanel.swift      # 过滤条件面板
├── i18n/
│   ├── en.lproj/
│   └── zh-Hans.lproj/
└── Resources/
    └── Assets.xcassets
```

---

## 4. 非功能规格

| 指标 | 要求 |
|------|------|
| 启动速度 | < 1 秒 |
| 100MB 文件打开 | < 2 秒 |
| 内存占用 | < 100MB（无论文件多大） |
| 滚动流畅度 | 60 FPS |

---

## 5. 里程碑

| 阶段 | 内容 |
|------|------|
| M1 | 项目初始化，基本窗口 + 文件打开 |
| M2 | 核心大文件读取 + 虚拟滚动 |
| M3 | 搜索/高亮功能 |
| M4 | 双语界面 + 打磨 |

---

## 6. 参考资料

- [AppKit 虚拟滚动实现](https://developer.apple.com/documentation/appkit)
- [SwiftUI macOS 大纲](https://developer.apple.com/documentation/swiftui/macos)

---

## 7. 数据类型定义

### 7.1 核心结构

```swift
// 单行日志
struct LogLine: Identifiable {
    let id: Int          // 行号（1-based）
    let content: String  // 该行原始文本
}

// 过滤结果
struct FilterResult: Identifiable {
    let id: UUID
    let line: LogLine           // 关联的日志行
    let highlightRange: Range<String.Index>? // 高亮位置
}

// 过滤条件
struct FilterCondition {
    let keyword: String        // 搜索关键词
    let isRegex: Bool          // 是否正则表达式
    let isCaseSensitive: Bool  // 是否大小写敏感
}

// 分割模式
enum SplitMode: String, CaseIterable {
    case none      // 单窗口
    case horizontal // 上下分割
    case vertical   // 左右分割
}
```

---

## 8. 模块职责

| 文件 | 职责 | 公开 API |
|------|------|----------|
| `LogpadApp.swift` | App 入口，根视图 | - |
| `ContentView.swift` | 主容器，负责分割布局 | - |
| `LogTextView.swift` | 主日志列表（虚拟滚动） | `scrollToLine(_:)` |
| `FilterResultView.swift` | 过滤结果列表 | `onLineSelected: (LogLine) → Void` |
| `SearchPanel.swift` | 搜索输入框 | `filterCondition: Binding<FilterCondition>` |
| `FileReader.swift` | 文件分片读取 | `readChunk(start:offset:length:)`, `totalLines()` |
| `SearchEngine.swift` | 全文搜索/正则 | `search(query:) -> [FilterResult]` |
| `VirtualScrollManager.swift` | 虚拟滚动引擎 | `visibleRange`, `loadIfNeeded()` |
| `i18n.swift` | 国际化字符串 | `String(localized:)` |

---

## 9. 验收标准

### M1 - 项目初始化，基本窗口 + 文件打开

- [ ] App 可以正常启动，显示主窗口
- [ ] 可以通过文件选择器打开 .txt/.log 文件
- [ ] 可以拖拽文件到窗口打开
- [ ] 窗口标题显示当前文件名

### M2 - 核心大文件读取 + 虚拟滚动

- [ ] 100MB 文件在 2 秒内加载完成
- [ ] 滚动时内存占用保持稳定（< 100MB）
- [ ] 行号显示正确
- [ ] 空文件显示占位提示

### M3 - 搜索/高亮功能

- [ ] Cmd+F 调出搜索面板
- [ ] 输入关键词后主视图高亮匹配行
- [ ] 过滤结果窗口同步显示匹配行
- [ ] 支持正则表达式搜索
- [ ] 点击过滤结果行，主视图跳转定位

### M4 - 双语界面 + 打磨

- [ ] 界面语言跟随 macOS 系统语言
- [ ] 水平/垂直/单窗口分割可切换
- [ ] 窗口可调整大小，分割比例保持
- [ ] 无内存泄漏
