# Logpad

> 一款专为查看大型文本日志设计的轻量级 macOS 应用。

Logpad 旨在提供类似 Notepad++ 的日志浏览体验：等宽字体、行号、实时搜索、高亮、跳转、文本标记——但运行在 macOS 上、专注于"打开大日志文件不卡"这个场景。

## 功能特性

- 📂 **打开大文件** —— 后台分块建立行索引，GB 级日志也能秒开
- 🔍 **实时搜索** —— 工具栏输入即搜，支持正则与大小写，匹配片段黄色高亮
- ⌨️ **键盘驱动** —— 跳转行号、搜索导航、文本标记、切换分屏……几乎所有操作都有快捷键
- 🎨 **文本标记** —— 选中关键词后打上颜色，全文件相同文本统一高亮，便于追踪错误码、模块名
- 🪟 **可调分屏** —— 单窗 / 上下 / 左右三种布局，分割线可拖
- 🌐 **中英双语** —— 工具栏可手动切换
- 🔄 **外部修改检测** —— 文件被外部改动时自动提示，可一键重新加载
- 🈶 **编码自动识别** —— UTF-8 / GB18030 / Big5 等都能正确打开中文日志

## 截图

> 截图待添加。建议把 `main.png` / `search.png` / `mark.png` 放在仓库根目录或 `docs/` 下，然后用 Markdown 图片语法引用：
>
> ```markdown
> ![主界面](docs/main.png)
> ```

## 系统要求

- macOS 26.5+
- Xcode 17+（从源码构建需要）

## 安装与运行

### 方式一：从源码运行

```bash
git clone https://github.com/lixinwang77/logpad.git
cd logpad
open Logpad/Logpad.xcodeproj
```

Xcode 中按 `Cmd+R` 运行。

### 方式二：下载 Release

前往 [Releases](https://github.com/lixinwang77/logpad/releases) 页面下载最新的 `.app` 或 `.dmg`。

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd+O` | 打开文件 |
| `Cmd+F` | 聚焦搜索框 |
| `Cmd+G` | 跳转到指定行号 |
| `Cmd+M` | 对选中文字添加颜色标记 |
| `Cmd+Shift+M` | 取消选中文字的标记 |
| `Cmd+R` | 重新加载外部修改过的文件 |
| `Enter` | 搜索：首次执行；已有结果时跳到下一条匹配 |
| `Shift+Enter` | 搜索：跳到上一条匹配 |

## 使用示例

1. **打开日志** —— `Cmd+O` 选文件，或直接把 `.log` 拖到窗口
2. **搜索关键词** —— `Cmd+F` 聚焦搜索框，输入关键词，匹配片段实时高亮
3. **跳转特定行** —— `Cmd+G` 输入行号（如 `1024`）回车
4. **标记关注的错误码** —— 选中 `ERROR`，`Cmd+M` 选红色，全文件相同文本立即统一标红
5. **过滤结果分屏查看** —— 输入搜索词后自动切到上下分割，结果列表在下方

## 性能指标

| 指标 | 目标 |
|------|------|
| 启动速度 | < 1 秒 |
| 100MB 文件打开 | < 2 秒（行索引完成） |
| 内存占用 | < 100MB（无论文件多大） |
| 滚动流畅度 | 60 FPS |

## 技术栈

- **语言**：Swift
- **UI**：SwiftUI + AppKit（`NSTextView` 承载可选中文本行）
- **架构**：MVVM
- **文件读取**：`FileHandle` 分块索引（4MB chunks）+ `memchr` 扫描换行
- **搜索**：字节级预筛（`ByteNeedle`）+ 250ms debounce
- **虚拟滚动**：`NSTableView` 行回收

## 项目结构

```
Logpad/
├── README.md          # 本文件
├── AGENTS.md          # Agent 协作约束
├── SPEC.md            # 完整产品规格与技术方案
├── VERSION.md         # 版本与变更记录
└── Logpad/
    └── Logpad/        # 源代码
        ├── LogpadApp.swift          # App 入口、菜单与快捷键
        ├── ContentView.swift        # 根视图
        ├── MainView.swift           # 主界面、工具栏、分屏
        ├── SelectableLogView.swift  # 单行日志视图
        ├── VirtualLogView.swift     # 虚拟滚动
        ├── FileReader.swift         # 大文件分块索引
        ├── SearchEngine.swift       # 搜索与标记
        ├── EncodingDetector.swift   # 编码自动识别
        └── ...                      # 模型、i18n 等
```

## 路线图

- [x] **M1–M5** —— 文件打开、大文件浏览、搜索高亮、跳转、文本标记、分屏、双语、外部修改检测、编码自动识别、虚拟滚动
- [ ] **M6** —— 搜索预设（保存 / 套用 / 管理 / 重命名 / 删除 / UserDefaults 持久化）

## 文档

- [SPEC.md](SPEC.md) —— 完整产品规格、模块划分、验收标准、数据结构定义
- [VERSION.md](VERSION.md) —— 版本与变更记录
- [AGENTS.md](AGENTS.md) —— Agent 协作约束（性能红线、关键行为、文档同步约定）

## 贡献

提交前请阅读 [AGENTS.md](AGENTS.md) 了解代码风格、性能红线、文档同步约定。
