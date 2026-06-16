# Framwise 端到端测试用例

> 测试版本：v2.0
> 更新日期：2026-06-16
> 对齐代码：main 分支（截至 2026-06-16）

本版本相对 v1.x 完全按当前代码重写：
- 切片机制由"5 秒上限切割"改为 **Preview Tiles 滑块（12~120，步进 12，默认 36）+ 灵敏度自动推导**。
- 预览由 640×480 固定窗口改为 **760×560 sheet 模态**，新增 1.0/1.5/2.0/3.0/4.0x 倍速循环切换。
- 新增覆盖：拖拽重排、反选、相似分组、废料检测、标签系统（含婚礼预设）、Session 持久化、键盘焦点态、文件访问错误。

---

## 0. 通用前置条件

- 系统：macOS 14+（与 `MACOSX_DEPLOYMENT_TARGET` 对齐）。
- 窗口：最小 1120×760（`FramwiseApp.swift:25`）。
- 主题：强制深色（`ContentView.swift:48`）。
- 测试素材：本地可访问的视频文件（建议覆盖 MP4 / MOV；4K / 长时长 / 多片段场景各一）。
- 默认状态：每次用例前清空 `~/Library/Application Support/Framwise/session.json` 或使用全新用户账户，避免 session 恢复干扰。

---

## 一、素材导入

### TC-01: 拖拽导入单个视频
**前置条件**: 应用启动，工作区为空（显示 `DropZoneView`）。

**操作步骤**:
1. 从 Finder 拖入一个 1 分钟 MP4 到中央 drop zone（580×320 虚线区域）。

**预期结果**:
- drop zone 边框切换为 accent 高亮（`FramwiseTheme.accent`），状态文案变为 "Release to import"。
- 松手后顶部 chrome bar 出现 "Reading sources" → "Building workspace" 状态徽章。
- 侧边栏 "Source Files" 出现该视频文件名及片段计数。
- 中央切换到 `ClipGridView`，按源文件分组显示片段，组头显示文件名 + 片段数。
- 切片数量受当前 `Preview Tiles` 设置控制（默认 36）。
- 分析过程中 drop zone 区域同时显示文件进度条与分析进度条（`DropZoneView.swift:97-148`）。
- 自动加载婚礼预设标签集（`AppState.ensureSession` → `loadWeddingPreset`）。

---

### TC-02: 拖拽导入多个视频
**前置条件**: 应用启动，工作区为空。

**操作步骤**:
1. 同时拖入 video1.mp4（1 分钟）、video2.mp4（5 分钟）。

**预期结果**:
- 侧边栏 Source Files 列出两个源，"All Clips" 显示总片段数。
- 主区域按源文件分组显示，每组显示文件名 + 片段数。
- 侧边栏 Statistics 区显示 Total Clips / Total Duration / Selected=0 / Tagged / Waste 计数。

---

### TC-03: 使用文件选择器导入
**前置条件**: 应用启动。

**操作步骤**:
1. 点击 chrome bar 的 "Import" 按钮，或按 ⌘+I。
2. 在文件选择器中选择多个文件（含 MOV）。
3. 点击 "Open"。

**预期结果**:
- 与 TC-02 结果相同。
- 选择器允许的类型：`.movie / .video / .mpeg4Movie / .quickTimeMovie / .folder`（`ContentView.swift:55`）。

---

### TC-04: 导入文件夹（递归扫描）
**前置条件**: 准备一个包含嵌套子目录的文件夹，子目录中混合视频与非视频文件。

**操作步骤**:
1. 拖入文件夹到 drop zone。

**预期结果**:
- 递归扫描所有层级中的支持格式视频文件（`FileResolver`）。
- 符号链接循环被安全跳过（不卡死、不重复计数）。
- 视频数量超过 5000 上限时停止扫描，并通过 `FileAccessIssue.videoLimitReached` 上报（`FileAccessIssue.swift:17`）。
- 顶部显示 "Reading sources" 直到扫描完成。

---

### TC-05: 拖入不支持格式
**前置条件**: 应用启动。

**操作步骤**:
1. 拖入 `.txt` 文件。

**预期结果**:
- 文件被拒绝。
- 若全部输入均为不支持格式，显示 `ImportError.unsupportedFiles` 错误面板（drop zone 与侧边栏同步显示）。
- 不创建空 clip。

---

### TC-06: 导入空 / 损坏 / 缺失解码器视频
**前置条件**: 准备 0 字节 `.mov`、扩展名伪装的非视频文件、本机无解码器的编码视频。

**操作步骤**:
1. 拖入这三类文件。

**预期结果**:
- 无视频轨道 / 无有效时长 / 无可解码帧的源被跳过，不生成空 clip。
- 失败信息通过 `FileAccessIssue`（`metadataReadFailed` 等）显式上报到 UI 警告面板，而非静默成功。
- 可访问的有效视频仍正常导入。

---

## 二、源文件过滤

### TC-07: 按源文件过滤
**前置条件**: 已导入 video1.mp4、video2.mp4。

**操作步骤**:
1. 在侧边栏点击 "video1.mp4" 行。

**预期结果**:
- 主区域只显示 video1.mp4 的片段，分组视图收窄为单组。
- 顶部工具栏出现 "video1.mp4" 过滤 chip，带关闭按钮（`ClipGridView.swift:199-208`）。
- 侧边栏 "All Clips" 行失去 active 高亮，"video1.mp4" 行变为 active。
- `appState.selectedSourceURL = url`。

---

### TC-08: 取消源文件过滤
**前置条件**: 当前过滤 video1.mp4。

**操作步骤**:
1. 点击 "All Clips"，或点击过滤 chip 的 ×。

**预期结果**:
- 主区域恢复显示全部片段（按源文件分组）。
- 过滤 chip 消失，"All Clips" 重新 active。

---

### TC-09: 在过滤态下搜索
**前置条件**: 过滤 video1.mp4。

**操作步骤**:
1. 在搜索框输入 "video"。

**预期结果**:
- 搜索结果与源过滤同时生效（取交集）。
- 无匹配时显示 `emptyResultsView`，提示 "No Clips Match Current Filters" 并提供 "Clear Filters" 按钮。

---

## 三、片段选择

### TC-10: 单选片段
**前置条件**: 已导入视频。

**操作步骤**:
1. 点击任意片段。

**预期结果**:
- 片段出现选中态（accent 边框）。
- chrome bar 显示 "1 selected" 徽章。
- 鼠标点击同步设置键盘焦点（`focusedClipID = clip.id`）。
- **预览不自动触发**（预览与选择完全分离）。

---

### TC-11: Shift 范围多选
**前置条件**: 已导入视频。

**操作步骤**:
1. 点击片段 A。
2. Shift+点击片段 C。

**预期结果**:
- A 与 C 之间（按当前可见顺序）所有片段被加入选中集。
- chrome bar 显示对应数量（`extendRangeSelection`）。

---

### TC-12: 全选 / 取消全选
**前置条件**: 至少 1 个片段在当前可见集合中。

**操作步骤**:
1. 点击工具栏 "Selection" 菜单 → "Select All"。
2. 再次打开 → "Deselect All"。

**预期结果**:
- Select All：当前可见集合（受搜索 / 过滤 / 视图模式约束）的所有片段被选中。
- Deselect All：`selectedClipIDs` 清空，chrome bar 归零。
- 全选仅作用于 `groupedClips.flatMap { $0.clips }`，不会选中被过滤掉的片段。

---

### TC-13: 反选
**前置条件**: 当前可见集合 80 个片段，已选中 5 个。

**操作步骤**:
1. Selection 菜单 → "Invert Selection"。

**预期结果**:
- 当前可见集合内：原 5 个未选中，其余 75 个被选中。
- 视图外的选中态被保留（`invertSelection` 只操作 view 内 ID 集合，再与外部选中并集）。

---

### TC-14: 右键"Select All from Same File"
**前置条件**: 多源文件导入，video1.mp4 有 15 个片段。

**操作步骤**:
1. 右键 video1.mp4 的任意片段 → "Select All from Same File"。

**预期结果**:
- 当前可见集合中所有 `sourceFileURL == clip.sourceFileURL` 的片段被加入选中（不替换已有选择）。

---

## 四、视图模式与排序

### TC-15: 切换到 "Selected" 视图模式
**前置条件**: 80 个片段，已选中 5 个。

**操作步骤**:
1. 点击工具栏 "Selected" 模式 chip。

**预期结果**:
- 主区域只显示 5 个已选片段。
- 顶部状态 chip 显示 "5 in selection"。
- 分组逻辑保留（仍按源文件分组）。

---

### TC-16: 在 Selected 视图下取消选择
**前置条件**: Selected 视图，5 个片段。

**操作步骤**:
1. 点击其中 1 个片段取消选择。

**预期结果**:
- 该片段从视图中消失（不再满足 "selected" 条件）。
- chrome bar 显示 "4 selected"。

---

### TC-17: 网格尺寸切换
**前置条件**: 已导入视频。

**操作步骤**:
1. 点击工具栏的网格尺寸 chip：Small / Medium / Large。

**预期结果**:
- Small：单元格 150×100，默认列数 6。
- Medium：220×150，列数 4。
- Large：320×200，列数 3。
- 实际列数随窗口宽度自适应（`availableWidth / (cellSize.width + 12)`）。

---

### TC-18: 窗口宽度变化自适应
**前置条件**: 已导入视频。

**操作步骤**:
1. 拖拽改变窗口宽度。

**预期结果**:
- 列数实时调整（窄 → 列数减少；宽 → 列数增加）。
- 片段宽度保持 GridSize 设定值，无水平滚动条。

---

## 五、拖拽重排

### TC-19: 拖拽片段重排
**前置条件**: 已导入视频，按源文件分组显示。

**操作步骤**:
1. 拖拽片段 A 到片段 B 上。

**预期结果**:
- 拖拽中源片段 A 半透明（opacity 0.3）。
- 目标片段 B 显示 accent 实线 3px 边框（**注意：是 `FramwiseTheme.accent` 紫色，不是蓝色**）。
- 松手后调用 `ImportSession.moveClip(draggedID, toTarget: targetID)`。
- **首次拖拽后视图切换为扁平网格**（`userClipOrder` 被建立），不再按源文件分组。

---

### TC-20: 恢复原始排序
**前置条件**: 已建立 `userClipOrder`（扁平视图）。

**操作步骤**:
1. 点击工具栏的 "Reset Order" 按钮（仅当 `userClipOrder != nil` 时出现）。

**预期结果**:
- `ImportSession.resetClipOrder()` 调用，`userClipOrder = nil`。
- 视图回到默认的按源文件分组显示。
- "Reset Order" 按钮消失。

---

## 六、预览播放（760×560 Sheet 模态）

> **设计原则**：预览与选择完全分离。
> - 预览：键盘焦点片段 → Space/Enter，或右键 → Preview，或 hover + Space。
> - 选择：鼠标点击切换选中态。
> - 预览不会改变哪些片段被选中用于导出。

### TC-21: 用 Space 打开预览
**前置条件**: 已导入视频，键盘焦点在片段 A（或鼠标悬停在 A 上）。

**操作步骤**:
1. 按 Space。

**预期结果**:
- 弹出 760×560 sheet 模态（`ClipPreviewModal.swift:243`）。
- 标题区显示 "PREVIEW MONITOR" + 文件名 + timecode 范围（mono 字体）。
- 视频区以 16:9 aspect fit 嵌入 22px 圆角黑色容器。
- 自动从片段开头开始播放，**默认 2.0x 倍速**（`PreviewViewModel.swift:20`）。
- 控制条：播放/暂停按钮 + 进度条（accent → warm 渐变）+ 时间显示（mono）+ 回到起点按钮。
- 底部 metric badges：IN / OUT / DURATION（timecode 格式）。
- 提示行 "SPACE play/pause  ·  ESC close"。
- 若该片段有标签，底部出现标签胶囊列表。
- 若该片段被标记为 waste，显示 waste 类型徽章。

---

### TC-22: 预览播放控制
**前置条件**: 预览已打开。

**操作步骤**:
1. 点击播放按钮（或按 Space）切换播放/暂停。
2. 拖动进度条到 50%。
3. 点击回到起点按钮。

**预期结果**:
- 播放按钮在 ▶ / ⏸ 间切换。
- 进度条拖动时 `viewModel.seek(to:)` 实时跟随。
- 回到起点按钮将播放头 seek 到片段开头。
- 时间显示更新为 `MM:SS / MM:SS`。

---

### TC-23: 播放到结尾自动停止
**前置条件**: 正在播放一个 5 秒片段。

**操作步骤**:
1. 等待播放到片段结尾。

**预期结果**:
- 播放自动暂停（不循环）。
- 播放头 seek 回片段开头（tolerance 为零）。
- 进度条归零，播放按钮恢复 ▶。

---

### TC-24: 循环切换播放倍速
**前置条件**: 预览已打开。

**操作步骤**:
1. 调用倍速切换（如点击倍速控件 / 快捷键）。

**预期结果**:
- 倍速按 **1.0 → 1.5 → 2.0 → 3.0 → 4.0 → 1.0** 循环（`PreviewViewModel.availableRates`）。
- 正在播放时立即生效（`player.rate = playbackRate`）。
- 暂停状态下切换倍速仅更新 `playbackRate` 字段，下次播放生效。

---

### TC-25: 预览内切换选中态
**前置条件**: 预览已打开，当前片段未选中。

**操作步骤**:
1. 点击底部 "Add to Selection" 按钮。

**预期结果**:
- 片段被加入 `appState.selectedClipIDs`。
- 按钮文案变为 "Selected"，配色切换为 accent soft 背景。
- chrome bar 的 "X selected" 计数同步增加。

---

### TC-26: 关闭预览
**前置条件**: 预览已打开。

**操作步骤**:
1. 点击右上角 × 按钮，或按 Esc。

**预期结果**:
- sheet 关闭，`viewModel.cleanupPlayer()` 释放 AVPlayer 资源。
- 返回网格视图，焦点 / 选中态保持不变。

---

### TC-27: 预览源已被移除
**前置条件**: 预览针对片段 A，但 A 在预览打开期间被从 session 中清除。

**操作步骤**:
1. 触发清除（例如另一窗口操作）使 `isClipMissingFromSession == true`。

**预期结果**:
- 视频区显示 `FramwiseStatePanel(.empty)` "Clip no longer in session"。
- 不尝试加载播放器，不崩溃。

---

### TC-28: 预览源加载失败
**前置条件**: 预览针对的源文件已被移动 / 删除 / 权限丢失。

**操作步骤**:
1. 打开预览。

**预期结果**:
- `AVPlayerItem.status == .failed` 触发错误面板（warning 色 + 描述）。
- 错误对象被记录到 `AppLogger.preview`（含 `clipID` / `sourceURL` 引用 / 耗时）。
- 不静默成功。

---

### TC-29: 预览不影响选择
**前置条件**: 片段 A 未选中。

**操作步骤**:
1. 焦点放在 A，按 Space 打开预览。
2. 关闭预览。

**预期结果**:
- A 仍未选中。
- chrome bar 选择计数不变。

---

## 七、键盘焦点与导航

### TC-30: 方向键移动焦点
**前置条件**: 网格已显示片段。

**操作步骤**:
1. 按 → / ← / ↑ / ↓。

**预期结果**:
- 焦点（`focusedClipID`）按当前列数（`columnCount`）在可见顺序中移动。
- 焦点片段显示 **warm 色（`FramwiseTheme.warm`）虚线边框 + 微弱阴影**，与选中态（accent 实线）视觉上明确区分。
- 自动滚动使焦点片段可见（`scrollToClipID` 同步）。
- 焦点首次进入时若无 current focus，自动落到第一个片段。

---

### TC-31: Enter 打开焦点预览
**前置条件**: 焦点在片段 A。

**操作步骤**:
1. 按 Enter。

**预期结果**:
- 打开 A 的预览 sheet（与 Space 行为一致）。

---

### TC-32: Escape 清除焦点
**前置条件**: 焦点在片段 A。

**操作步骤**:
1. 按 Esc。

**预期结果**:
- `focusedClipID = nil`，warm 虚线边框消失。
- 若此时没有焦点，Esc 不做任何事（`.ignored`）。
- 预览 sheet 打开时 Esc 优先关闭 sheet。

---

### TC-33: 数字键 1-9 切换标签
**前置条件**: 已加载至少 2 个标签，焦点在片段 A（或选中 / hover 任一）。

**操作步骤**:
1. 按 "2"。

**预期结果**:
- 对焦点片段（优先级：focus > selection > hover）切换第 2 个标签：已分配 → 移除；未分配 → 添加。
- 若超出已定义标签数量，按键被忽略。

---

### TC-34: 鼠标点击同步焦点
**前置条件**: 已导入视频。

**操作步骤**:
1. 点击片段 B。

**预期结果**:
- `isGridFocused = true` 且 `focusedClipID = B.id`。
- warm 虚线焦点框出现在 B 上。

---

## 八、废料检测与纠正

### TC-35: 自动废料标记
**前置条件**: 导入一段含黑屏 / 极暗 / 纯色 / 模糊镜头的视频。

**操作步骤**:
1. 等待分析完成。

**预期结果**:
- 检测到的废料片段在 `ClipCellView` 显示 danger 半透明覆盖 + 废料类型标签（BLACKOUT / DARK / SOLID / BLURRY）。
- 侧边栏 Statistics 的 "Waste" 计数 > 0。
- 算法：每片段 25% / 50% / 75% 三帧采样投票决定类型（`WasteDetector`）。

---

### TC-36: 隐藏 / 显示废料
**前置条件**: 存在废料片段。

**操作步骤**:
1. 点击工具栏 "Hide waste" 按钮。

**预期结果**:
- 废料片段从网格中过滤掉。
- 按钮文案切换为 "N hidden"，配色切换为 danger tint。
- 再次点击恢复显示。

---

### TC-37: 手动纠正废料（单条）
**前置条件**: 焦点 / 右键目标为自动检测的废料片段。

**操作步骤**:
1. 右键 → "Mark as Non-Waste"。

**预期结果**:
- 该片段 `effectiveWasteType` 变为 `.none`（KEPT 标记）。
- danger 覆盖消失。
- 再次右键时菜单出现 "Reset to Auto-detected"。

---

### TC-38: 批量废料纠正
**前置条件**: 多选 3 个废料片段 + 1 个正常片段。

**操作步骤**:
1. 右键多选集合中任一片段。

**预期结果**:
- 菜单显示批量文案："Mark N as Non-Waste" / "Mark N as Waste" / "Reset N to Auto-detected"。
- 仅作用于集合中"适用"的片段（已是废料才能 Non-Waste；非废料才能 Waste；已 override 才能 Reset）。
- 导出时 waste 片段被自动排除，KEPT 片段被保留。

---

## 九、相似片段分组

### TC-39: 相似组自动生成
**前置条件**: 导入包含重复镜位 / 多 take 的素材。

**操作步骤**:
1. 等待分析完成（pHash + Union-Find 在分析流水线中完成）。

**预期结果**:
- 同组片段（Hamming ≤ 10）在 `ClipCellView` 显示 "N TAKES" 标记。
- `ImportSession.similarityGroups` 非空。
- 每组选时长最长的片段为代表。
- 当存在相似组时，工具栏出现 "Group similar" 按钮。

---

### TC-40: 启用相似分组视图
**前置条件**: 存在相似组。

**操作步骤**:
1. 点击 "Group similar"。

**预期结果**:
- 视图按相似组聚合显示，按钮文案变为 "N groups"。
- 配色切换为 info tint。

---

### TC-41: 按相似组过滤
**前置条件**: 存在相似组。

**操作步骤**:
1. 右键片段 → "Show Similar Takes"。

**预期结果**:
- `gridViewModel.similarityGroupFilter = groupID`。
- 视图只显示该组片段，顶部出现 "N takes" 过滤 chip。
- 点击 chip 的 × 清除过滤。

---

## 十、标签系统

### TC-42: 空状态引导
**前置条件**: 全新 session（首次导入之前从未触发 ensureSession）。

**操作步骤**:
1. 导入首个视频（触发 ensureSession → 自动加载婚礼预设）。

**预期结果**:
- 侧边栏 Tags 区在首次导入时已包含婚礼预设标签：新娘准备 / 新郎准备 / 仪式 / 晚宴 / 第一支舞 / 花絮。
- 若 session 创建后用户手动清空标签，Tags 区显示 `TagsEmptyStateView`："Load Wedding Preset" + "New Tag" 引导按钮。

---

### TC-43: 创建自定义标签
**前置条件**: session 已存在。

**操作步骤**:
1. 点击侧边栏 "New Tag"。
2. 在 `TagCreateView` 输入名称、选择颜色、确认。

**预期结果**:
- 标签以 sheet 弹出（紧凑布局，颜色方块 4px 圆角）。
- 同名校验：与已有标签重名时被拒绝。
- 创建成功后标签出现在侧边栏列表，自动获得下一个快捷键编号（前 9 个）。

---

### TC-44: 重命名 / 删除标签
**前置条件**: 已有标签。

**操作步骤**:
1. 右键标签 → "Rename"（弹 `TagRenameView` sheet）。
2. 或 "Delete"（destructive 角色）。

**预期结果**:
- 重命名进行同名校验（排除自身）。
- 删除后该标签从所有片段的 `tagIDs` 中移除。

---

### TC-45: 按标签过滤
**前置条件**: 已为部分片段分配标签 T。

**操作步骤**:
1. 点击侧边栏标签 T 行。

**预期结果**:
- `activeTagFilter = T.id`。
- 主区域只显示带 T 的片段。
- 顶部出现 T 的过滤 chip（带颜色圆点）。

---

### TC-46: 标签快捷键提示
**前置条件**: 已加载 ≥1 个标签。

**操作步骤**:
1. 观察侧边栏 Tags 区底部。

**预期结果**:
- 显示 `TagsKeyboardHint`："Press 1–N to tag"（具体文案随标签数动态）。
- 每个标签行右侧显示快捷键编号（前 9 个）。

---

### TC-47: 右键分配 / 移除 / 全选标签
**前置条件**: 已有标签，已选中 ≥1 片段。

**操作步骤**:
1. 右键多选集合中任一片段。

**预期结果**:
- "Assign Tag" 子菜单列出全部标签，已分配的显示 ✓。
- "Remove Tag" 子菜单只列出该片段已有的标签。
- "Select All with Tag" 子菜单：点击后将所有带该标签的片段加入选中集。
- 批量分配 / 移除作用于整个选中集合。

---

## 十一、时间线导航

### TC-48: 时间线点击跳转
**前置条件**: 已导入视频，时间线可见（`showTimeline == true`，默认开）。

**操作步骤**:
1. 点击时间线（`CollapsedTimelineView`）上的某片段块。

**预期结果**:
- 调用 `proxy.scrollTo(clipID, anchor: .center)`。
- 主区域滚动到该片段，并居中。
- 0.3s `easeInOut` 过渡动画。

---

### TC-49: 时间线显隐切换
**前置条件**: 时间线当前可见。

**操作步骤**:
1. 点击工具栏 "Timeline On" 按钮。

**预期结果**:
- `showTimeline = false`，时间线区域消失。
- 按钮文案切换为 "Timeline Off"，配色变浅。
- 再次点击恢复显示。

---

## 十二、导出

### TC-50: 打开导出 sheet
**前置条件**: 已选中 ≥1 个非废料片段。

**操作步骤**:
1. 点击 chrome bar "Export" 按钮，或按 ⌘E。

**预期结果**:
- 弹出 560 宽的 `ExportSheetView` sheet。
- Metric badges：Selected / Exportable（去除 waste 后）/ Waste Excluded。
- 格式列表：EDL（CMX 3600）/ FCPXML 1.9。
- 默认状态面板 "Ready to export"。

---

### TC-51: 导出 EDL
**前置条件**: 已选 5 个非废料片段。

**操作步骤**:
1. 选择 EDL 格式。
2. 点击 "Export"。
3. 在 NSSavePanel 选择保存位置。

**预期结果**:
- 临时文件先生成，再由用户选择最终保存路径（`ExportSheetView.startExport`）。
- 文件包含 5 段时间码信息（CMX 3600）。
- 保存完成后 sheet 关闭，临时文件被清理。
- 智能命名：全部选中来自同一源 → 以源文件名为默认名；多源 → 时间戳命名。

---

### TC-52: 导出 FCPXML
**前置条件**: 已选 5 个非废料片段。

**操作步骤**:
1. 选择 FCPXML 格式 → Export → 选择保存。

**预期结果**:
- 生成 `.fcpxml` 文件（1.9 schema）。
- XML 属性正确转义。
- 兼容 DaVinci Resolve / Premiere Pro。

---

### TC-53: 选中全部为废料时导出
**前置条件**: 选中片段全部为 waste。

**操作步骤**:
1. 打开 Export sheet。

**预期结果**:
- Exportable = 0，状态面板 "Nothing exportable yet"（empty 状态）。
- Export 按钮 disabled。
- 提示 "All selected clips are marked as waste."

---

### TC-54: 未选中任何片段时导出
**前置条件**: `selectedClipIDs` 为空。

**操作步骤**:
1. 观察 chrome bar 的 Export 按钮。

**预期结果**:
- Export 按钮 disabled，配色为 muted。
- ⌘E 不触发 sheet（`ContentView.swift:61` 守卫 `!selectedClipIDs.isEmpty`）。

---

### TC-55: 部分选中为废料
**前置条件**: 选中 10 个片段，其中 3 个为 waste。

**操作步骤**:
1. 打开 Export sheet。

**预期结果**:
- Exportable = 7，Waste Excluded = 3。
- 状态面板出现 "Waste clips excluded" 警告（warning 色）。
- 导出文件只含 7 段。

---

## 十三、设置（Preview Tiles）

### TC-56: 打开设置
**前置条件**: 应用运行中。

**操作步骤**:
1. 菜单 Framwise → Settings…，或按 ⌘,

**预期结果**:
- 弹出 480×360 sheet（`FramwiseApp.swift:54`）。
- 显示 `Preview Tiles` 卡片，标题 + 当前值（默认 36）。
- 滑块范围 12~120，步进 12。
- 密度标签实时反馈：
  - ≤18：Broad overview
  - 19~48：Balanced
  - 49~84：Detailed
  - ≥85：Fine detail
- 提示："Changes apply to next import."

---

### TC-57: 调整 Preview Tiles 影响下次导入
**前置条件**: 已有片段（用旧设置导入）。

**操作步骤**:
1. 将滑块从 36 调到 60。
2. 清空 session，重新导入同一视频。

**预期结果**:
- 新导入按 60 片切片，灵敏度自动推导（60 → 约 0.6 sensitivity）。
- 已有片段不受影响（设置只对下次导入生效）。

---

## 十四、Session 持久化

### TC-58: 自动保存
**前置条件**: 已导入片段。

**操作步骤**:
1. 选中若干片段 / 添加标签 / 重排片段。
2. 等待 ≥0.5 秒（debounce）。

**预期结果**:
- `~/Library/Application Support/Framwise/session.json` 被写入。
- 包含：所有片段、选中状态、自定义排序、标签、废料纠正、相似分组。
- 日志（`AppLogger.persistence`）记录保存耗时 / sessionID / 计数。

---

### TC-59: 重启恢复
**前置条件**: 已存在持久化 session。

**操作步骤**:
1. 退出应用（⌘Q）。
2. 重新启动。

**预期结果**:
- `AppState.init` 自动从 `SessionStore.load()` 恢复。
- 片段 / 选中 / 标签 / 排序全部还原。
- 日志记录 "Restored persisted session" + removedSourceCount / removedClipCount / durationMs。

---

### TC-60: 源文件失效恢复
**前置条件**: 已持久化 session，其中部分源文件已被移动 / 删除 / 修改。

**操作步骤**:
1. 在 Finder 中删除或移动一个源文件。
2. 重启应用。

**预期结果**:
- 通过文件大小 + 修改时间校验失效的源。
- `RestoreReport` 非空，侧边栏显示 "Some restored sources were unavailable" 面板（`SidebarView.restoreWarningView`）。
- 失效片段被清理，不静默呈现为可用。
- 仍可访问的源正常恢复。

---

### TC-61: 退出 / 后台 flush
**前置条件**: session 有未保存的变更。

**操作步骤**:
1. 触发 `scenePhase == .inactive / .background` 或 `NSApplication.willTerminateNotification`。

**预期结果**:
- `flushSessionToDisk(reason:)` 被调用。
- 即使 debounce 未到期，关键退出时机也强制写盘。

---

## 十五、清除会话

### TC-62: Clear 操作
**前置条件**: 已导入 2 个视频，选中 10 个片段。

**操作步骤**:
1. 点击 chrome bar "Clear" 按钮（trash 图标）。

**预期结果**:
- `appState.clearSession()` 执行：
  - 取消正在进行的导入 / 源解析。
  - `store.delete()` 删除持久化文件。
  - `importSession = nil`、`selectedClipIDs = []`、`selectedSourceURL = nil`、`previewClip = nil`、`restoreReport = nil`。
- 主区域回到 `DropZoneView`。
- 侧边栏 Source Files 清空。
- **注意**：当前实现无二次确认弹窗（直接清空），UX 风险已在 review checklist 跟踪。

---

### TC-63: 清除失败
**前置条件**: 模拟 `store.delete()` 抛错（权限 / 磁盘满）。

**操作步骤**:
1. 点击 Clear。

**预期结果**:
- `persistenceError` 被设置，错误显式传导到 chrome bar 与侧边栏。
- 不静默成功。
- 返回 false，调用方不重置 UI 状态。

---

## 十六、边界与异常

### TC-64: 超大视频
**前置条件**: 2GB 4K 1 小时视频。

**操作步骤**:
1. 拖入。

**预期结果**:
- 流式分析，进度条逐步推进，主线程不阻塞。
- 片段逐个加入网格（`importVideosStreaming`）。
- 缩略图懒加载（`ThumbnailGenerator` 双层缓存：内存 500 / 磁盘 2GB）。

---

### TC-65: 快速连续切换预览
**前置条件**: 已导入视频。

**操作步骤**:
1. 快速焦点切换多个片段并按 Space。

**预期结果**:
- 单一 sheet 实例（`showPreviewModal`），不会叠加多个。
- 切换时 `cleanupPlayer()` 释放旧 AVPlayer。

---

### TC-66: 快速切换过滤 / 清空 session 时缩略图在加载
**前置条件**: 大量片段正在加载缩略图。

**操作步骤**:
1. 快速切换 source filter / tag filter。
2. 在缩略图未完成时点击 Clear。

**预期结果**:
- 不出现陈旧缩略图、过时进度、卡死 loading。
- `gridViewModel.resetTransientUIState()` 重置网格瞬态。

---

### TC-67: 网格为空时按 Space
**前置条件**: 鼠标未悬停在片段上，无焦点。

**操作步骤**:
1. 按 Space。

**预期结果**:
- `handleSpaceKey` 返回 `.ignored`，不弹预览。
- 事件继续传播（例如系统快捷键）。

---

### TC-68: 工程质量基线核对
（来自 `.agents/ENGINEERING_QUALITY_BASELINE.md`）

**核对范围**: 列表 / 详情 UI 必须实现四态；外部调用失败必须传导到 UI；日志必须保留关键上下文。

**预期结果**:
- 列表态（侧边栏 Source Files / Tags / 主网格）：均覆盖 loading / empty / error / success（通过 `FramwiseStatePanel` + `FramwiseLoadState`）。
- 导入 / 导出 / 持久化 / 预览失败：均显式设置 `error` 并显示，不静默吞掉（参见 TC-06 / TC-28 / TC-55 / TC-63）。
- 关键日志含入参 / ID / 耗时 / 原始 error（`AppLogger` 各 category）。

---

## 测试用例统计

| 模块 | 用例数 |
|------|--------|
| 通用前置 | （0，统一节） |
| 素材导入 | 6 |
| 源文件过滤 | 3 |
| 片段选择 | 5 |
| 视图模式与排序 | 4 |
| 拖拽重排 | 2 |
| 预览播放 | 9 |
| 键盘焦点与导航 | 5 |
| 废料检测与纠正 | 4 |
| 相似片段分组 | 3 |
| 标签系统 | 6 |
| 时间线导航 | 2 |
| 导出 | 6 |
| 设置 | 2 |
| Session 持久化 | 4 |
| 清除会话 | 2 |
| 边界与异常 | 5 |
| **总计** | **68** |

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| v2.0 | 2026-06-16 | 按 main 分支代码全量重写：订正切片机制（Preview Tiles 滑块）与预览（760×560 sheet）；新增拖拽重排、反选、相似分组、废料检测与纠正、标签系统、键盘焦点态、Session 持久化、文件访问错误、设置窗口等用例；对齐 `.agents/ENGINEERING_QUALITY_BASELINE.md` 四态与显式错误要求。 |
| v1.2 | 2026-03-14 | 修复编译错误，添加拖拽格式验证，更新 TC-27 预期为模糊匹配（已废弃）。 |
| v1.1 | 2026-03-14 | 预览改为弹窗模式（hover+space），选择与预览逻辑分离（已废弃）。 |
| v1.0 | 2026-03-13 | 初始版本（已废弃）。 |
