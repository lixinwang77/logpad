# Logpad 版本历史

## 版本规范

采用语义化版本 `MAJOR.MINOR.PATCH`（例如 `1.2.3`）：

| 变更类型 | 版本号变化 | 示例 |
|----------|------------|------|
| Bug 修复 | PATCH +1 | 1.0.0 → 1.0.1 |
| 新功能（向后兼容） | MINOR +1，PATCH 归零 | 1.0.1 → 1.1.0 |
| 不兼容的重大变更 | MAJOR +1，MINOR/PATCH 归零 | 1.1.0 → 2.0.0 |

每次发版还需递增 **Build 号**（`CURRENT_PROJECT_VERSION`），与版本号同步更新。

### 发版步骤

1. 修改 `Logpad/Logpad.xcodeproj/project.pbxproj` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`（Debug / Release 两处都要改）
2. 在本文件「变更记录」中追加条目
3. 提交代码

## 当前版本

**1.1.0** (Build 2)

## 变更记录

### 1.1.0 (2026-05-29)

- 新增外部文件修改检测：文件被外部写入/删除/替换时显示提示条，可一键重新加载（`Cmd+R`，保持滚动位置）或忽略

### 1.0.0 (2026-05-29)

- 初始发布：文件浏览、搜索高亮、文本标记、分屏布局、跳转行号、中英文界面
- 添加应用版本号与「关于 Logpad」窗口
