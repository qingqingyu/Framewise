# Design System — Framwise

## Product Context
- **What this is:** `Framwise` 是一个 macOS 原生专业创意桌面工具，用来在正式剪辑前快速导入素材、自动切镜、筛掉废片、打标签、预览片段，并导出到 Premiere / DaVinci 等后续流程。
- **Who it's for:** 婚礼剪辑师、视频编辑师、需要高频浏览和判断大量素材的影像创作者。
- **Space / industry:** 创意工具、视频素材管理、粗剪前整理工作流。参考方向包含 [Eagle](https://www.eagle.cool/)、[Kyno](https://www.lesspain.software/kyno/)、[KeyFlow Pro](https://keyflowpro.com/)。
- **Project type:** macOS 原生专业创意桌面应用，不是营销站，也不是通用后台。

## Aesthetic Direction
- **Direction:** `Digital Light Table / 数字灯箱工作台`
- **Decoration level:** `intentional`
- **Mood:** 像一张暗房里的数字灯箱，暖黑底、精密读数、素材发光、工具退后。整体要专业、克制、有温度，像给影像工作者用的工作台，而不是另一个默认灰色工具壳子。
- **Why this direction works:** `Framwise` 的核心不是“管理文件”，而是“判断镜头是否值得保留”。界面应该服务于画面比较、节奏判断和快速筛选，所以要让缩略图和 timecode 成为主角。

## Typography
- **Display / Hero:** `Söhne`
  - 用于主标题、关键区块标题、核心数字。
  - 理由：比常见无衬线更有器材感和高级工业气质。
- **Body:** `Söhne` 或 `Instrument Sans`
  - 用于正文、表单、按钮、工具栏标签。
  - 理由：需要清晰、稳定、长时间观看不累。
- **Chinese UI:** `Source Han Sans SC`
  - 用于中文界面文本。
  - 理由：结构稳定，和英文 grotesk 混排时不容易散。
- **Data / Timecode:** `IBM Plex Mono` 或 `Berkeley Mono`
  - 用于 `timecode`、时长、计数、元数据。
  - 理由：这些信息必须像设备读数，而不是普通辅助文字。
- **Code / diagnostics:** `IBM Plex Mono`
- **Loading strategy:**
  - 首选：如果项目可合法使用商业字体，优先 `Söhne` + `Berkeley Mono`。
  - 默认可落地方案：`Instrument Sans` + `Source Han Sans SC` + `IBM Plex Mono`。
  - **当前实际实现**：使用 macOS 系统字体（`.system` + `.monospaced` design），无打包自定义字体。待获取字体授权并打入 bundle 后再切换到自定义字体方案。
  - 未明确获得授权前，不要把商业字体当作唯一线上依赖。
- **Scale (当前实际使用):**
  - `hero`: 34–42px — Drop zone 主图标/数字（仅 DropZoneView）
  - `display-lg`: 24px / semibold — 区块标题、统计大字
  - `display-md`: 18px / semibold — Metric badge 数字、次级标题
  - `body-lg`: 16px / semibold — 按钮强调、sheet 标题
  - `body-md`: 14px — 正文、表单控件、设置描述
  - `body-sm`: 13px — 按钮文字、sidebar 标签、常规 UI 文本
  - `meta`: 12px / medium — 过滤按钮、chip 文字
  - `micro-mono`: 11px / monospaced — timecode、帧号、badge
  - `nano-mono`: 10px / monospaced — 次级 timecode、元数据标签
  - `pico-mono`: 8–9px / monospaced — 极小辅助信息（tag shortcut 数字）
- **Line-height:** 当前未系统性地使用 line-height token，视觉间距由 padding/spacing 控制。待后续统一。
- **原始设计 scale (供未来对齐参考):**
  - `display-xl`: 56px / 0.96
  - `display-lg`: 40px / 1.02
  - `title-lg`: 28px / 1.1
  - `title-md`: 22px / 1.15
  - `body-lg`: 16px / 1.6
  - `body-md`: 14px / 1.55
  - `body-sm`: 13px / 1.45
  - `meta`: 12px / 1.35
  - `micro-mono`: 11px / 1.25

## Color
- **Approach:** `restrained with warm-dark neutrals`
- **Core neutrals:**
  - Primary background: `#0D0F12`
  - Background elevated (toolbar chrome): `#11141B`
  - Surface: `#151922`
  - Raised surface / hover: `#1D2330`
  - Divider / structural line: `#2A3142`
- **Text:**
  - Primary text: `#E7ECF3`
  - Muted text: `#9AA6B8`
- **Brand accents:**
  - Accent: `#8C7CFF` — 选中、高亮、主动作、活跃状态。
  - Accent soft: `#8C7CFF` @ 16% opacity — 用于浅底高亮、选中行背景。
  - Warm highlight: `#F3D2A7` — 少量高光、强调边界、灯箱感，不作大面积底色。
- **Semantic colors:**
  - Success: `#4DE2C5`
  - Warning: `#FFB84D`
  - Danger (waste / destructive): `#FF6B6B`
  - Info: `#7FB3FF`
- **Tag colors:**
  - Tag pink: `#E58ACF`
  - Tag gray: `#6E778A`
  - 其余标签颜色复用 semantic colors 和 accent。
- **Gradients (代码中的命名 token):**
  - `appGradient`: background → `#10131A` → background，对角线渐变，用于主工作区底色。
  - `subtleHighlight`: warm@18% → accent@6% → clear，用于 drop zone 和空状态的微妙光感。
  - `monitorGradient`: black@0 → @55% → @84%，用于 clip card 底部信息条的暗角遮罩。
- **Dark mode:** 这是主模式，不是附属模式。所有视觉判断都以暗色工作环境为基准。
- **Light mode:** 只作为补充展示或设计预览存在，不作为默认工作模式。
- **Usage rules:**
  - 80% 以上视觉面积保持暗中性。
  - 颜色只给决策状态，不拿来装饰页面。
  - 不使用大面积紫色渐变、糖果色控件、泛滥高饱和背景。

## Spacing
- **Base unit:** `8px`
- **Density:** `compact-comfortable`
- **Scale:**
  - `2xs`: 4
  - `xs`: 8
  - `sm`: 12
  - `md`: 16
  - `lg`: 24
  - `xl`: 32
  - `2xl`: 48
  - `3xl`: 64
- **实际补充值:** 在紧凑控件（按钮 padding、toolbar 内边距、badge 间距）中，也使用 2、6、9、10、14、18、20 等中间值。这些不属于核心 scale，但在专业工具的紧凑布局中是必要的灵活性。
- **Principle:** 这是高吞吐工具，不能为了“高级感”牺牲每屏可判断的片段数量。允许精致，不允许松散。优先使用核心 scale；当核心 scale 无法精确适配紧凑 UI 时，允许使用偶数像素中间值。

## Layout
- **Approach:** `grid-disciplined with local editorial emphasis`
- **Global structure:**
  - 左侧：`Sidebar`，承担来源、标签、统计、导入入口。
  - 顶部：全局工具条，承担 import / export / status / clear 等动作。
  - 中央：高密度 clip grid，是主工作区。
  - 模态预览：clip preview 以 sheet 弹出，承担单片段确认和播放。非常驻面板，按需触发（Space 或 Enter）。
- **Grid philosophy:** 全局布局稳定、可预测；局部信息层可以更有编辑感，比如 clip card 的 timecode 和状态带。
- **Max content width:** 以桌面应用自适应为主，不使用网站式固定内容宽度。
- **Border radius scale:**
  - `xs`: 4px — 极小元素（标签色块、内嵌指示器）
  - `sm`: 8px — 紧凑控件（设置卡片内部、chips）
  - `md`: 12px — 中等面板（设置卡片、sidebar 区块）
  - `card`: 14px — Clip card 标准圆角（缩略图、metric badge）
  - `lg`: 16px — 较大面板（modal、sheet 内容区）
  - `panel`: 18px — `framwisePanel` 默认值（toolbar、主面板）
  - `pill`: 999px — 按钮、筛选 chip
- **Radius rule:** 专业工具不使用过度圆角。卡片和胶囊可有柔和边角，但整体仍应偏器材感矩形。clip card 统一使用 14px，面板统一使用 18px，按钮使用 pill。

## Motion
- **Approach:** `minimal-functional`
- **Purpose:** 动效只用于帮助理解状态变化，不用于表演。
- **Easing:**
  - 当前实现统一使用 `ease-in-out`，适用于所有交互场景（hover、selection、filter、drop target）。
  - 原始设计区分了 enter=ease-out / exit=ease-in / move=ease-in-out，但实践中统一 easing 更易维护且视觉差异极小。
- **Duration:**
  - micro: `100ms` — clip card hover 状态切换
  - short: `120ms` — 按钮 press 反馈
  - medium: `150ms` — drop target 高亮、焦点切换
  - long: `300ms` — 选中态展开、模态出现
- **Motion rules:**
  - hover、selection、filter 切换、preview load 可以动。
  - 动效应该像仪表响应，不像展示动画。
  - 不做大面积弹跳、夸张缩放、装饰性过场。

## Visual System Rules
- **素材优先：** 缩略图和画面判断必须优先于 UI 装饰。
- **Timecode 升级：** `timecode` 和 metadata 是一级视觉语言，不是普通 caption。
- **Waste context preserved：** 废片不直接“消失”，而是在上下文中被明确但克制地标记。
- **No generic SaaS language：** 避免把桌面工具做成网站控制台气质。
- **No AI slop patterns：**
  - 不要默认紫色渐变大背景
  - 不要 3 列图标功能宫格
  - 不要所有元素都圆滚滚
  - 不要把所有内容都居中
  - 不要用玻璃态覆盖缩略图判断区域

## Module Guidance
- **`SidebarView`**
  - 目标：从默认列表感升级成状态分区。
  - 做法：增强区块标题层级，让选中来源和 tag filter 更像状态条，不依赖普通 `checkmark` 逻辑。
  - `drop zone` 要像 ingest bay / 收纳仓口，而不是普通虚线框。
  - **Tags 区域**：空状态时显示引导文案（"Drop a video above, then tag clips here"）+ Wedding Preset 按钮；有标签时显示标签列表 + 键盘快捷键提示（"Press 1-N to tag selected clips"）。引导应克制，不做大面积插图。

- **`ContentView` 顶部工具栏**
  - 目标：形成更明确的三段式动作条。
  - 做法：左侧主动作、中间状态反馈、右侧结果动作。
  - `Export` 必须是视觉上的完成动作，不能和普通按钮等权。

- **`ClipGridView`**
  - 目标：把散控件整理成控制带。
  - 做法：搜索与过滤一组，视图控制一组，网格密度与选择动作一组。
  - 筛选状态必须始终显性。
  - **键盘导航**：方向键移动焦点，焦点态以 warm 色虚线边框 + 微弱阴影呈现，和选中态（accent 实线）视觉上有明确区分。Enter 打开预览，Escape 清除焦点，数字键 1-9 快速打标签。

- **`ClipCellView`**
  - 目标：成为品牌识别核心。
  - 做法：让缩略图主导视觉，底部信息层承载 `duration + timecode + tags`。
  - 选中态（accent 边框）、hover 态（surfaceRaised 边框）、waste 态（danger 半透明覆盖 + 标记）、焦点态（warm 虚线边框）都需要稳定、克制、可一眼识别的规则。

- **`ClipPreviewView` (Modal)**
  - 目标：像监看区，不像系统面板。
  - 做法：以 sheet 弹出，播放器区域更沉浸，控制条更像设备控制，timecode 范围与 clip info 更像专业读数。
  - 默认 2x 播放速度，符合快速筛选工作流。

- **`ExportSheetView`**
  - 目标：像交付前确认台。
  - 做法：突出格式差异、导出总量、被排除的 waste clips，以及最终交付动作。

- **`SettingsView`**
  - 目标：像工作台参数调节面板，不像系统偏好设置。
  - 做法：以 sheet 弹出（Cmd + ,），单个 "Preview Tiles" 滑块控制切片数量，密度提示（Broad overview → Fine detail）实时反馈，场景检测灵敏度自动推导。
  - 使用 `framwisePanel` 样式卡片，保持暗色工具感。

- **`TagCreateView`**
  - 目标：轻量快速的标签创建/编辑。
  - 做法：以 sheet 弹出，颜色选择网格 + 名称输入，保持紧凑。颜色方块使用 xs 圆角（4px），选中态用 accent 边框。

- **`DropZoneView`**
  - 目标：像 ingest bay / 收纳仓口。
  - 做法：暗色底 + subtleHighlight 渐变，拖拽时高亮边框。支持的格式以 chip 形式排列。自动触发婚礼预设标签加载。

## Safe Choices
- 深色主界面仍然是基础，因为这是行业共同语言。
- 保持高信息密度和强状态可见性，不为风格牺牲吞吐量。
- 使用熟悉的播放、选择、筛选交互，不重新发明专业工具的基本动作。

## Risks Worth Taking
- **暖黑底而不是纯冷灰**
  - 收益：更贴近婚礼和人物素材，更有记忆点。
  - 代价：需要更精确地控制对比和脏感。
- **timecode 作为一级视觉语言**
  - 收益：更像工作台，更专业。
  - 代价：如果使用过量，会显得过于技术化。
- **waste clips 保留上下文**
  - 收益：增强比较感和判断信心。
  - 代价：必须控制红色覆盖，避免网格躁动。

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-18 | 采用 `Digital Light Table` 作为主设计方向 | 与 `Framwise` 的素材判断工作流最匹配 |
| 2026-04-18 | 主工作模式以暖黑暗色系统为准 | 更利于影像判断，也比通用冷灰更有产品识别度 |
| 2026-04-18 | timecode / metadata 升级为一级视觉语言 | 强化专业工作台气质 |
| 2026-04-18 | 允许保留 waste clips 的上下文标记 | 服务对比、粗筛和决策信心 |
| 2026-04-19 | clip preview 采用 modal sheet 而非常驻面板 | 最大化网格工作区面积，按需查看 |
| 2026-04-19 | clip card 圆角统一 14px，面板统一 18px | 比原始 scale 更精细地区分卡片与面板层级 |
| 2026-04-19 | 动效 easing 统一 ease-in-out | 简化维护，enter/exit 分开在实践中视觉差异极小 |
| 2026-04-19 | 键盘焦点使用 warm 虚线边框区分于选中态 | 焦点态和选中态同时存在时不能混淆 |
| 2026-04-19 | 设置窗口合并为单滑块 Preview Tiles | 两参数控制一件事让用户困惑，自动推导灵敏度更直觉 |
| 2026-04-19 | Tags 空状态显示引导文案而非空白 | 婚礼摄影师用户不一定知道标签功能的存在 |
