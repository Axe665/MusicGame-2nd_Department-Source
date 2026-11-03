# Tamaki₃ 制谱器 v0.1

Godot 4.7.2 实现的《Tamaki₃》谱面编辑器纵向切片。设计依据为：

- `环 GameDesign/新版图文文档_修订版/Tamaki₃ 制谱器设计文档 v2.1（适配玩法 v6.1）.docx`（正文 v2.2）
- `环 GameDesign/新版图文文档_修订版/Tamaki₃ 玩法 v6.1—修订图文版.docx`（正文 v6.2）
- `环 GameDesign/Path设计图/` 的原始 SVG/PNG 视觉参考

首版目标是“能写、能看、能打”：三栏编辑器、u×时间画布、分段边界、六类音符、Red、3D 预览、F5 二值试玩、JSON 存档，以及一套可被文档算例证伪的 `core/` 数学层。

## 运行

```bash
godot --path .
```

或用 Godot 4.7.2 打开 `project.godot` 后按 F6/F5。首次启动会载入 `charts/demo.json`（32 个音符、2 个 BoundaryEvent、2 个 Red、RingState 关键帧），并自动生成 `audio/demo_click.wav` 的示例音频。

- 空格：播放/暂停；Shift+空格：从头播放；Ctrl+空格：循环
- F5：从播放头试玩；Shift+F5：从头试玩
- F6：打开“时间”页（基准 BPM / offset / BPM 列表）
- Esc：结束试玩 / 退出试玩结果 / 停止播放
- 试玩中 `[` / `]`：判定偏移 -5 / +5 ms（±200ms），顶部显示当前 OFF
- Ctrl+S：保存；Ctrl+Shift+S：另存为；Ctrl+O：打开；Ctrl+N：新建
- Ctrl+Z / Ctrl+Y：撤销 / 重做（200 步）
- 1–7：Tap / Hold / Path / Trace / Anchor / Bell / Red
- B：边界编辑；E：事件；H：HUD；Delete：删除选中
- 预览窗：拖动边界控制点；双击分段拆分；Trace 工具在预览窗拖拽绘制擦带

## 界面

- 顶部：文件/编辑/视图/插入/事件/试玩菜单与工具组
- 左 47%：事件轨 + u×时间画布（波形、BPM 线、播放头）
- 中 24%：七张音符类型卡 + 音符 / 区域 / 边界 / 事件 / 视图 / 时间 / 谱面七页检查器
- 右 29%：3D 预览（SubViewport + Camera3D + 环网格 + 视频背景）
- 底部：运输条（播放、时间、进度、BPM、速率、循环、节拍器）与状态栏

检查器“时间”页是设计文档表 14 中 A 曲目层的时间部分，参考 osu! editor：基准 BPM、offset、固定预读、BPM 点列表和选中点编辑都在同一页；“谱面”页只保留标题/曲师/谱师/难度、音频/视频路径和保存。其余页对应 B–E 层。

## 已实现

- `core/`：TimingMap、BoundaryShape/Segment/Event、ViewState、Region、Note、Chart、ChartIO、Validator、JudgeMath、UndoStack
- 时间：beat↔毫秒分段积分、BPM 变化、offset、固定预读 D、拍号分子 1–16
- 边界：分段曲线 l/s/si/so/b、闭合/缺口、局部 BoundaryEvent、restore/hold、控制点拖动、双击拆分、圆/椭圆/竖椭圆/切一刀预设；按本次要求限制为**简单凸轮廓**，自交/非凸/星形/折返/局部半径过激会被拒绝
- 音符：Tap / Hold / Path / Trace / Anchor / Bell、可视节点、Trace 二维点、Path 头尾、Hold 仅判头部
- 区域：Red 时间/角度/宽度、4 拍上限、同刻公共角度减红区校验；预览中 Red 是填充扇区 + 高亮外弧 + RED 标签，进入前会显示淡色 RED IN
- 音符视觉：Tap 为可变角宽的切向宽条；Hold 为琥珀色六边形头 + 长体；Path 为珊瑚五角星头 + 琥珀圆环尾 + 灰色厚轨迹 + 青色虚线中轴/方向箭头，并支持“弧线 / 五角星”两种表现层（五角星只改画面，头尾仍各自判定）；Trace 为宽幅薄荷色擦带 + 中心虚线 + 方向箭头 + 起止端点 + 已擦过进度；Anchor 为紫色菱形；Bell 为金币；Red 为红色扇区
- 类型卡：检查器上方七张浅色切角卡（黑色背板、黄色选中态）图标 + 标签 + 快捷键，点击即切工具
- 时间页：基准 BPM、offset、固定预读、BPM 点列表（双击跳转）、选中点的起始拍/BPM/拍号、Tap Tempo、播放头加 BPM、删除、播放头设为起始拍
- Path/Hold 编辑：弧线 Path 与 Hold 选中后可在预览中拖动青色体节点；五角星 Path 不含可拖节点
- 格式：File 菜单可导入 osu!std/taiko `.osz`、导出 `.lbp` v2；导入报告用对话框显示
- Path 造型：选中 Path 后在检查器“路径造型”切换弧线/五角星；五角星在环内画出五条弦，头尾圆环仍落在环上，中段判定仍走头尾弦
- 预览：默认开启 3D 环网格；环、八边形舞台、八束光、刻度、外圈、投影阴影全部走 GPU 网格；相机投影 tilt/zoom/ellipse/rotation + 鼠标倾斜/视差；固定预读 P(u,q,t)、单光标最近点、HUD 60° 弧、误差刻度、视频层；视图页可关闭“3D 环网格”回退到投影环线
- Red 表现与绘制：填充红色扇区、亮色外弧、扇区斜纹、RED/RED IN 标签；Red 工具在预览中横向拖角度、纵向拖时长（最多 4 拍）；Trace 表现：宽幅薄荷擦带、双层边线、虚线中轴、连续箭头、起止端点、已擦进度与高亮擦头
- 媒体：原生 WAV/OGG/MP3 音频、Ogg Theora 视频；FLAC/M4A/AAC/OPUS/WebM/MP4 音频与 MP4/WebM/MOV/MKV/AVI 视频通过 ffmpeg 自动转码到 `user://media/` 后预览
- 视觉：石墨黑 + 安全黄 UI、浅色切角音符卡、深空径向渐变、八角舞台与八束光、金色八边形外框、圆盘刻度/十字准星、音符投影；参考 maimai 的环上 HUD 与 Path 构成、Estella 的八角 3D 舞台；音符保留珊瑚/琥珀/青/薄荷/紫/金/红语义色
- 性能：Forward+ / Vulkan、60fps 上限；边界批量采样时只排序一次分段，变形插值参数按事件计算一次；BoundaryFrame 缓存形状采样，当前时刻的网格、音符和光标共用精确边界求值，编辑后失效；Path 固定造型采样与相机适配半径复用；3D 网格在变形期间跟随渲染帧更新，静止时复用；音符拖动按帧合并通知、不重建环网格，完整校验在松开鼠标后执行；试玩时暂停被覆盖的编辑器及其 3D 视口；静止时 SubViewport 自动禁用，3D 内部渲染 0.8×；时间轴静态层与播放头拆成两层，播放时只重绘播放头；检查器标签 20Hz 更新、事件轨 20Hz、最近点 96 采样、字号预加载、视频仅在漂移时 seek
- 试玩：音频主时钟（输出延迟补偿 + 单调防回跳）、按键事件时间戳判定（减少一帧输入延迟）、40ms 二值窗口、任意键 Tap/Hold/Anchor、鼠标 Path/Tail/Bell/Trace、Red 200ms、FULL/FRAY/LOST、COMBO、命中扩散环、二值日志、结果面板
- 试玩延迟：`audio/driver/output_latency=10`；顶部 `OFF` 与 `[` / `]` 可手动校准音频/输入综合延迟，Path 头尾改为窗口内可命中而不是窗口一开始就判 Miss
- 存档：JSON 主格式、原子写、`.bak.1..5`、60 秒/20 条命令自动保存、`user://autosave.json` 手动恢复
- 演示：32 音符示例谱、示例点击轨、3D 预览、五角星 Path 示例、试玩事件日志

## 格式互通

- **导入 `.osz`**：支持 osu!std 与 osu!taiko；circle → Tap、slider → Path 头尾/visual、drumroll → Hold；spinner 跳过；多难度包会弹窗选择 `.osu`；导入报告列出保留/丢弃原因。
- **taiko 映射**：don/kat 合并为 Tap，按四象限 0/90/180/270 轮转；drumroll → Hold；spinner 跳过。
- **导出 `.lbp` v2**：按设计文档第 7 章输出 `[General] / [Video] / [Metadata] / [TimingPoints] / [BoundaryShapes] / [BoundaryEvents] / [ViewStates] / [Regions] / [Notes] / [Editor]`，保留 Path 五角星、Trace 二维点、Bell、Anchor 配对和颜色/锁定选项。
- 导入时会把 `.osz` 内的音频、背景、视频解包到 `user://imports/`；音频仍可用 ffmpeg 转码。
- 不做 `.mcz`、osu!mania/catch、`.lbp` 反向导入、Malody 4.3.7 运行时。

## 未实现（本轮范围之外）

- `.mcz`、osu!mania / osu!catch 导入
- Malody 4.3.7 运行时接入
- 英文 UI、皮肤/世代编辑器、在线谱面平台
- 10,000 音符专项性能调优、MCP 对外接口
- 自由三维飞行/大幅镜头摆动（按文档非目标）；鼠标倾斜限制在 ±11°
- 自由手绘边界轮廓（当前仍受简单凸轮廓与分段工具约束；Red 已支持预览手绘）

## 测试

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/test_runner.gd
```

当前结果：**108 passed, 0 failed**。测试覆盖：

- 120 BPM / 变速 / offset 的时间换算与反解
- 圆的 C(u)、最近点反解、五角星 Path 表现层
- `.lbp` 导出头部/段落/Path 五角星/换行
- osu!std 导入的 offset/BPM/circle/slider/visual/spinner 跳过
- osu!taiko 导入的四象限/鼓滚/spinner 跳过
- `.osz` 多难度列表与指定难度导入
- 固定预读 `P(T)=C(u,T)`（多形状/事件）
- 文档 §7.2 的 1 秒收缩算例（`R(t)=330−150t`，t=1 时 180px）
- BoundaryEvent restore 回快照与插值
- 批量边界采样与逐点求值一致（乱序分段、缺口、局部事件、变形与恢复）；拖动通知按帧合并、提交后校验、撤销/重做与环网格复用
- BoundaryFrame 跨帧复用采样与原始求值一致、光标最近点一致、同一时刻编辑后缓存失效
- JSON 保存→加载→保存字节稳定
- 示例谱全量校验
- 角度交集/红区差集、同刻可打性（红区覆盖唯一落脚点时拒绝）、Trace 距离
- 环线自交/非凸/变形过激拒绝，BoundaryEvent 过渡采样检查
- 媒体格式识别与原生路径透传

## 结构

```text
core/      引擎无关的谱面模型、时间/边界数学、校验、JSON
charter/   编辑器 UI、3D 预览、画布、检查器、试玩
assets/    内置 Noto Sans CJK SC / Noto Sans Mono 字体
audio/     示例点击轨（脚本生成，18s）
charts/    示例谱 demo.json
tests/     SceneTree 无头测试
```

`core/` 不依赖窗口/音频/皮肤，后续 game 项目可直接复用；编辑器、预览、试玩共用同一套 `C(u,t)`、`P(u,q,t)`、最近点求值与校验器。

## 媒体格式

| 类型 | 直接支持 | 自动转码（需要 ffmpeg） |
|---|---|---|
| 音频 | WAV / OGG / MP3 | FLAC / M4A / AAC / OPUS / WebM / MP4 |
| 视频 | Ogg Theora（.ogv） | MP4 / WebM / MOV / MKV / AVI |

转码结果缓存到 `user://media/`，按源路径哈希命名；谱面仍保存原始路径。视频用于环后背景层，默认 35% 不透明度，`videoOffset` 独立于音频。

## 已知限制

- 非原生音频/视频格式依赖 `ffmpeg` 在 PATH 中；没有 ffmpeg 时原生 WAV/OGG/MP3 与 OGV 仍可用，其他格式会给出明确提示。转码缓存位于 `user://media/`，谱面保存的是原始路径，便于重新链接。
- 预览默认开启 3D 环网格；环/舞台/刻度是 GPU 网格，音符与 HUD 仍是 2D 叠加（按本轮取舍，保证编辑精度）。旧机器或集显可在“视图”页关闭 3D 环网格回退到投影环线。
- 视频是背景层，音频仍是唯一判定时钟。
- 边界编辑器是“分段参数 + 控制点 + 预设”，按本次要求只允许**简单凸轮廓**；凹口、星形、折返、自交、局部半径过激都会被校验拒绝。`b` 插值按平滑曲线处理，语法保留。
- 局部 BoundaryEvent 仍可用，但若过渡中产生凹口/自交也会被拒绝；首版示例使用整环事件。
- 试玩是文档 §8.9 的“最小判定模拟器”：二值命中/失误 + 事件日志 + 调试准确率/评级，不是正式评分公式。Path 中段已改为屏幕距离判定（容差 24px × tolerance/0.24），头尾仍是独立点判定。
- 试玩判定偏移只在当前会话生效，不做自动延迟测量；如果设备/耳机延迟大，用 `[` / `]` 手动校准，或启动时加 `--audio-output-latency 5` 覆盖 10ms 缓冲。
- 命中窗口固定 40ms，尚未做 Perfect/Great/Good 分级；评分规则仍等文档冻结。
- 拍号分母固定 4；3/8、6/8 需要后续 BeatUnit 扩展。
- 示例音频是节拍点击轨，不是正式曲目；可以用“谱面”页替换音频路径。
- `.osz` 多难度包会弹出选择框；如果包内难度没有音频，仍可导入但预览无声。
- taiko 的 don/kat 会合并为 Tap 并分布到四象限，不保留原颜色语义；这是当前约定的导入映射。

## 字体与资源

- `assets/fonts/NotoSansSC-Regular.ttf` / `-Bold.ttf`：从系统 Noto Sans CJK SC 提取，随工程分发
- `assets/fonts/NotoSansMono-Regular.ttf` / `-Medium.ttf`：数值/拍号/时间读数
- `audio/demo_click.wav`：脚本生成的 120 BPM 示例点击轨
- `charts/demo.json`：示例谱，可另存或替换
