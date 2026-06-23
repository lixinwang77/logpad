# Logpad

> 一款专为查看大型文本日志设计的轻量级 macOS 应用。

Logpad 提供类似 Notepad++ 的日志浏览体验：等宽字体、行号、实时搜索、片段高亮、跳转、文本标记、过滤结果分屏——运行在 macOS 上，专注于「打开大日志文件不卡」。

**当前版本：1.16.2**

## 功能特性

### 打开与浏览

- 📂 **大文件秒开** —— 后台分块建立行索引，GB 级日志也不整文件载入内存；≥ 20MB 时显示索引进度条
- 🔢 **行号浏览** —— 1-based 行号列，虚拟滚动（`NSTableView` 行回收），内存占用与文件大小无关
- 🈶 **编码自动识别** —— UTF-8 / GB18030 / Big5 等中文日志均可正确打开，工具栏实时显示当前编码
- 🔄 **外部修改检测** —— 文件被外部写入、删除或替换时自动提示，可一键重新加载并保持滚动位置
- 🪟 **多窗口与标签页** —— `Cmd+N` 新建独立窗口，`Cmd+T` 新建标签页；Finder 双击或「打开方式」亦可打开

### 搜索与过滤

- 🔍 **实时搜索** —— 工具栏输入即搜（250ms debounce），支持正则与大小写，匹配**片段**黄色高亮（非整行）
- ⬆️⬇️ **匹配导航** —— `Enter` / `Shift+Enter` 逐条跳转，当前聚焦匹配以更深的黄橙色标示；搜索框旁箭头按钮等效
- 📋 **过滤结果分屏** —— 单窗 / 上下 / 左右三种布局，分割线可拖；搜索后自动切到上下分屏展示结果列表，点击结果行联动跳转主视图
- 📌 **搜索预设侧栏** —— 按「组 → 过滤词」管理常用关键词，点组名一键套用（`|` 合并、自动开启 Regex）；侧栏内联增删改，勾选控制启用，全窗口共享并持久化

### 标记与效率

- 🎨 **文本标记** —— 选中关键词后 `Cmd+M` 选色，全文件相同文本统一高亮（红 / 橙 / 绿 / 蓝 / 紫）；`Cmd+Shift+M` 或右键按颜色取消
- ⌨️ **键盘驱动** —— 跳转行号、搜索导航、文本标记、分屏切换……几乎所有操作都有快捷键
- 🌐 **中英双语** —— 工具栏可手动切换界面语言

## 系统要求

- macOS 26.5+（Apple Silicon）
- Xcode 17+（从源码构建需要）

## 安装与运行

### 方式一：从源码运行

```bash
git clone https://github.com/lixinwang77/logpad.git
cd logpad
open Logpad/Logpad.xcodeproj
```

Xcode 中按 `Cmd+R` 运行。

### 方式二：本地打包 DMG

仓库根目录提供一键打包脚本：

```bash
./build_dmg.sh
```

产物位于 `build/Logpad-<版本>.dmg`。因 ad-hoc 签名未公证，首次打开若被 Gatekeeper 拦截，可右键「打开」，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/Logpad.app
```

### 方式三：下载 Release

前往 [GitHub Releases](https://github.com/lixinwang77/logpad/releases/latest) 下载最新 `.dmg`。首次打开若被 Gatekeeper 拦截，处理方式见上方「本地打包 DMG」一节。

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd+N` | 打开新的独立窗口 |
| `Cmd+T` | 在当前窗口新建标签页 |
| `Cmd+O` | 打开文件 |
| `Cmd+F` | 聚焦搜索框 |
| `Cmd+G` | 跳转到指定行号 |
| `Cmd+M` | 对选中文字添加颜色标记 |
| `Cmd+Shift+M` | 取消选中文字的标记 |
| `Cmd+R` | 重新加载外部修改过的文件 |
| `Enter` | 搜索：首次执行；已有结果时跳到下一条匹配 |
| `Shift+Enter` | 搜索：跳到上一条匹配 |

## 使用示例

1. **打开日志** —— `Cmd+O` 选文件，拖拽到窗口，或 Finder 双击 / 「打开方式」
2. **搜索关键词** —— `Cmd+F` 聚焦搜索框，输入关键词，匹配片段实时高亮；`Enter` 逐条浏览匹配
3. **跳转特定行** —— `Cmd+G` 输入行号（如 `1024`）回车
4. **标记关注的错误码** —— 选中 `ERROR`，`Cmd+M` 选红色，全文件相同文本立即统一标红
5. **过滤结果分屏查看** —— 输入搜索词后自动切到上下分割，结果列表在下方，点击某行跳回主视图对应位置
6. **套用搜索预设** —— 打开左侧预设侧栏，维护「网络错误」等分组与过滤词，排查时点击组名即可套用整组条件

## 技术栈

- **语言**：Swift
- **UI**：SwiftUI + AppKit（`NSTextView` 承载可选中文本行）
- **架构**：MVVM（`FileReader` / `SearchEngine` 与视图分离）
- **文件读取**：`FileHandle` 分块索引（4MB chunks）+ `memchr` 扫描换行
- **搜索**：字节级预筛（`ByteNeedle`）+ 后台流式扫描 + 250ms debounce
- **虚拟滚动**：`VirtualLogView`（`NSTableView` 行回收）

## 项目结构

```
.
├── README.md              # 本文件
├── AGENTS.md              # Agent 协作约束
├── SPEC.md                # 完整产品规格与技术方案
├── VERSION.md             # 版本与变更记录
├── build_dmg.sh           # 一键打包 DMG
└── Logpad/
    └── Logpad/            # 源代码
        ├── LogpadApp.swift          # App 入口、菜单与快捷键
        ├── WindowManager.swift      # 多窗口 / 标签页
        ├── ContentView.swift        # 根视图
        ├── MainView.swift           # 主界面、工具栏、分屏
        ├── PresetSidebarView.swift  # 搜索预设侧栏
        ├── PresetStore.swift        # 预设持久化
        ├── SelectableLogView.swift  # 单行日志视图
        ├── VirtualLogView.swift     # 虚拟滚动
        ├── FileReader.swift         # 大文件分块索引
        ├── SearchEngine.swift       # 搜索与标记
        ├── EncodingDetector.swift   # 编码自动识别
        └── ...                      # 模型、i18n、关于页等
```

## 里程碑

| 阶段 | 内容 | 状态 |
|------|------|------|
| M1 | 项目初始化，基本窗口 + 文件打开 | ✅ |
| M2 | 大文件行索引 + 按行浏览 | ✅ |
| M3 | 搜索 / 高亮 / 分屏 / 联动跳转 | ✅ |
| M4 | 跳转行号、文本标记、搜索导航、双语界面 | ✅ |
| M5 | 虚拟滚动、外部修改检测、编码识别、索引进度条 | ✅ |
| M6 | 搜索预设侧栏（组 / 词、内联增删改、套用、持久化） | ✅ |

## 文档

- [SPEC.md](SPEC.md) —— 完整产品规格、模块划分、验收标准、数据结构定义
- [VERSION.md](VERSION.md) —— 版本与变更记录
- [AGENTS.md](AGENTS.md) —— Agent 协作约束（性能红线、关键行为、文档同步约定）

## 贡献

提交前请阅读 [AGENTS.md](AGENTS.md) 了解代码风格、性能红线、文档同步约定。
