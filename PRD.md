# Framwise 产品需求文档 v2

## 产品定位

一个Mac原生桌面App（Swift + SwiftUI），面向画面感剪辑师，帮助他们快速浏览和筛选本地视频素材，然后导出到PR/达芬奇进行精剪。

## 核心工作流

```
导入本地素材 → 自动切割成镜头网格 → 浏览筛选镜头 → 导出EDL/XML → 进PR/达芬奇精剪
```

## 功能需求

### 1. 素材导入
- 支持拖拽或选择本地视频文件导入
- 素材文件始终保留在用户本地，不上传服务器
- 支持常见格式：MP4、MOV、MXF等

### 2. 自动切割逻辑（两层叠加）
- **第一层**：按镜头cut点自动切割，每个自然镜头为一格
- **第二层**：超过5秒的长镜头，每5秒再切一格
- 目的是保证网格里每一格时长大致均匀

### 3. 网格浏览界面
- 所有镜头以动态缩略图形式展示在网格中
- 每格自动循环播放
- 只渲染用户视野内的格子（懒加载），保证流畅度
- 用户可像浏览图片墙一样扫描所有镜头

### 4. 镜头选择
- 单击选中/取消某一格镜头
- 支持多选
- 选中的镜头高亮显示

### 5. 导出
- 用户选好镜头后，导出EDL或XML文件
- 文件内记录原始素材文件名、每段片段的入点和出点时间码
- 导出的文件可直接导入Premiere Pro和DaVinci Resolve

## 技术要求

- **平台**：macOS原生，Swift + SwiftUI
- **视频处理**：AVFoundation框架（帧提取、缩略图生成）
- **渲染**：利用Metal保证网格滚动流畅
- **无需服务器**，纯本地运行

## 不做的事情（明确边界）

- 不做废料自动过滤（第二阶段再做）
- 不做时间轴剪辑功能
- 不做云端存储
- 不做自动成片
- 不做口播/字幕相关功能

---

## 技术实现说明

### 场景检测算法
使用帧差分直方图比较法：
1. 对视频进行采样（约每秒10-15帧）
2. 计算每帧的颜色直方图
3. 比较相邻帧的直方图差异
4. 差异超过阈值则判定为场景切换点

### 缩略图生成
- 使用 AVAssetImageGenerator 提取视频帧
- 缓存最多500张缩略图到内存
- 每个clip生成5张缩略图用于动画循环

### 导出格式
1. **EDL (CMX 3600)**：行业标准编辑决策列表格式
2. **FCPXML 1.9**：Final Cut Pro XML格式，兼容DaVinci Resolve和Premiere Pro

---

## 项目结构

```
Framwise/
├── App/
│   └── FramwiseApp.swift          # App入口、全局状态
├── Models/
│   ├── VideoClip.swift            # 视频片段模型
│   └── ImportSession.swift        # 导入会话管理
├── ViewModels/
│   ├── VideoImportViewModel.swift # 导入+切割逻辑
│   ├── ClipGridViewModel.swift    # 网格+选择逻辑
│   └── ExportViewModel.swift      # EDL/FCPXML导出
├── Views/
│   ├── ContentView.swift          # 主界面+侧边栏
│   ├── DropZoneView.swift         # 拖拽导入区域
│   ├── ClipGridView.swift         # 网格视图
│   └── ClipCellView.swift         # 单格视图+动画缩略图
├── Services/
│   ├── SceneDetector.swift        # 场景检测(cut点识别)
│   └── ThumbnailGenerator.swift   # 缩略图生成+缓存
└── Utils/
    └── TimecodeUtils.swift        # 时间码格式化
```
