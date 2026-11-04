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
- 1–8：Tap / Hold / Path / Trace / Anchor / Bell / Red / 大小 Tap
- B：边界编辑；E：事件；H：HUD；Delete：删除选中
- 右键单击音符 / 红区 / 事件：直接删除；右键按住拖动仍是框选
- 右键拖拽：框选音符；随后左键松开结束选择（结束动作不会放置音符）
- 预览窗：拖动边界控制点；双击分段拆分；Trace 工具在预览窗拖拽绘制擦带

## 界面

- 顶部：文件/编辑/视图/插入/事件/试玩菜单与工具组
- 左 47%：事件轨 + u×时间画布（波形、BPM 线、播放头）
- 中 24%：八张音符类型卡 + 音符 / 区域 / 边界 / 事件 / 视图 / 时间 / 谱面七页检查器
- 右 29%：3D 预览（SubViewport + Camera3D + 环网格 + 视频背景）
- 底部：运输条（播放、时间、进度、BPM、速率、循环、节拍器）与状态栏

检查器“时间”页是设计文档表 14 中 A 曲目层的时间部分，参考 osu! editor：基准 BPM、offset、固定预读、BPM 点列表和选中点编辑都在同一页；“谱面”页只保留标题/曲师/谱师/难度、音频/视频路径和保存。其余页对应 B–E 层。

## 已实现

- `core/`：TimingMap、BoundaryShape/Segment/Event、ViewState、Region、Note、Chart、ChartIO、Validator、JudgeMath、UndoStack
- 小节线：顶部“小节线”输入每拍等分份数 N（1–64），画布用 N−1 条细线等分每拍（如 4 → 3 条）；0、负数、小数、非数字提示“数据有误”
- 竖线：顶部“竖线”输入内部竖线数量 N（1–64，默认 21），画布等距绘制 N 条竖线，与左右编辑区边界共同构成 N+2 条竖向边界；0、负数、小数、非数字提示“数据有误”
- 音符固定：放置 Tap/Hold/Path/Trace/Anchor/Bell 时，位置靠近横向小节线或竖线会吸附到最近的线，两者都靠近时落在交点；拖动结束（含批量拖动）会再次吸附；按住 Alt 仍可临时绕过
- 批量剪贴：选中音符后 Ctrl+C 复制、Ctrl+X 剪切，半透明预览跟随鼠标时间；Ctrl+V 粘贴，Ctrl+A 镜像粘贴，粘贴成功后清除预览并选中新音符；单个音符选中时按 A 原地镜像
- 纵向拉伸：顶部“纵向拉伸”支持 0–10 的整数/小数输入与滑条；每 bar 距离变为原来的 `1 + n×0.5` 倍，小节线等比拉伸，音符头/图标尺寸不变
- 音频：支持 WAV/OGG/MP3/FLAC（FLAC 经 ffmpeg 解码缓存）；应用条件为 BPM 检测成功、offset 在单拍范围内、播放流时长与解码音频时长一致
- 新建谱面：选择音频后自动测量 BPM 与 offset；BPM 最多保留 3 位小数，只有 1 位小数时四舍五入取整；offset 保留 3 位小数
- 打击音效：试玩命中与编辑器播放共用 `HitSfx` 音效池（don/kat/铃/Path 尾/擦带），10 路播放器轮转 + 轻微随机音高；资源在 `audio/sfx/`
- 编辑器播放打击音：运输条“打击音”开关，播放时按音符时间触发 Tap、Hold 头/尾、Path 头/尾、Anchor、Bell、Trace；不影响试玩
- 光标：Estella 风格白色环 + 青色内环 + 旋转弧 + 深色描边 + 拖尾；预览内始终隐藏系统光标并绘制自定义光标
- 流速：运输条“流速”0.5×–2.0×，只缩放预读速度（`pre_read_ms ÷ flow_scale`），不改判定窗口；试玩沿用当前设置
- 星速：运输条“星速”0.75×–1.5×，同时缩放滑条引导星移动速度与所需跟随距离
- 视角：视图页“正对镜头（忽略倾斜）”默认开启，试玩时环面始终正对相机；需要作者镜头时可关闭
- 打击音：新增 Hold / Path / Anchor 分层音色（合成 WAV，瞬态 + 音体 + 短尾）；Trace 离开轨迹超过 250ms 会重置累计距离（FRAY）
- 环：正对镜头 + 鼠标倾斜/视差；所有 note 厚度与星头按环半径等比缩放，Tap/Path/Trace 统一 32px 外圈、13px 主色
- Simai：可直接选解压后的 `maidata.txt` 或文件夹，音频直接使用同目录 `track.*`；zip 导入仍解包并转 OGG；同刻冲突只保留最宽一侧
- 滑条判定：谱面页“滑条判定”可切“连续跟随 / 舞萌扫圈”；舞萌导入默认扫圈，osu!std 默认连续跟随
- 音量：运输条“音乐”“音效”两个滑杆，分别控制 `Music` / `SFX` 总线；编辑器播放、试玩、打击音共用总线设置
- 游玩范围：所有 note 以**八角舞台安全矩形**为准；手绘 Trace 在落点时夹到安全区，环上 note 保持在环内
- 接近表现：所有音符（Tap / Hold / Path / Trace / Anchor / Bell）都从圆心飞向判定环并随预读放大，轨迹和星尾一起长出，不再原地出现；Hold 完成后 0.24 拍渐隐
- 长度体系：l = 旧版 Tap 与判定环重合时的条带长度（即 `note.width`）。新版普通 Tap 与 Hold 头都是 **0.5 l**，且"看到多长 = 能打多长"（绘制与判定共用 `Note.arc_width()`）；**大小 Tap**（第 8 张卡）可用检查器"长度 ×l" 调到 **0.00–1.50 l**（两位小数），0 长度仍保留一个点标记；Tap / Hold 在环心出现时只有 **1/6 l**，飞近判定环时长到 1 l
- Path / Trace 视觉尺寸统一 ×2（`PATH_SIZE_SCALE` / `TRACE_SIZE_SCALE`）：笔画、V 形箭头、星头、尾环、进度球、Trace 端点与宽度全部放大，轨迹几何与判定不变
- Hold 外观：头部与 Tap 用同一条"长度条"（`_draw_length_band`），只是主体色换成黄色，缩放节奏与 Tap 完全一致（环心 1/6 l → 判定环 1 l）；身体从**圆心**画到 **1.44R**（旧版 0.28R→1R 的 0.72R 的 2 倍，外端越过判定环 0.44R），飞入时同样跟着 `grow` 长出来
- osu!std 落道：circle 的角度改成 Sentakki 式 **8 道 45°** 对齐（`_std_closest_lane`），流向用它的中点法（`_std_stream_direction`：同向保持、共线归零、否则取角差符号），大跳按两端道差（`jumpLaneOffset`），间隔超过 1 拍重新回绝对位置；slider / hold 的映射不变
- 试玩设置「星显」：运输条新增 **星显**（-1.0–1.0，步进 0.1，单位拍），只影响星星轨迹的出现时间（`pre + 星显`），Tap / Hold 的预读不受影响
- 星星启动时间：Path 新增 **启动时间 ms**（`start_delay_ms`，0–2000，步进 10，默认 0）。星头落线后这段时间里只显示星头，**轨迹与尾判都不存在**；到点后轨迹出现、才允许划 Path、尾判也才开门。实际起滑时间取 `max(wait_beat, delay)`，尾判与整条轨迹按同样的量整体后移（滑动速度不变）
- Path 擦除：检查器“跳区 / 擦除”可擦掉中段 0–80%；擦除段不渲染、不生成中段检查点，断裂处自动断开轨迹
- Trace 表现：宽笔刷 + 流动高光 + 星头/尾环同色，去掉中心虚线；鼠标向前跳区时跳过的轨迹从画面削掉且不累计移动距离
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
- 视觉：石墨黑 + 安全黄 UI、浅色切角音符卡、深空径向渐变、终末地式分段圆环（白色开口弧 + 琥珀细环 + 凹槽刻度 + 暗色外圈，不再使用八角外框/八束光）、圆盘刻度/十字准星、音符投影；试玩时环放大到屏幕短边约 86–88%，环外整片仍可判定；音符保留珊瑚/琥珀/青/薄荷/紫/金/红语义色
- 性能：Forward+ / Vulkan、60fps 上限；边界批量采样时只排序一次分段，变形插值参数按事件计算一次；BoundaryFrame 缓存形状采样，当前时刻的网格、音符和光标共用精确边界求值，编辑后失效；Path 固定造型采样与相机适配半径复用；3D 网格在变形期间跟随渲染帧更新，静止时复用；音符拖动按帧合并通知、不重建环网格，完整校验在松开鼠标后执行；试玩时暂停被覆盖的编辑器及其 3D 视口；静止时 SubViewport 自动禁用，3D 内部渲染 0.8×；时间轴静态层与播放头拆成两层，播放时只重绘播放头；检查器标签 20Hz 更新、事件轨 20Hz、最近点 96 采样、字号预加载、视频仅在漂移时 seek
- 试玩：音频主时钟（输出延迟补偿 + 单调防回跳）、按键事件时间戳判定（减少一帧输入延迟）、PERFECT ±65ms / GREAT ±115ms / GOOD ±170ms 三档、超过 170ms 判 Miss、Great/Good 不断连、早按跨帧保留 300ms、任意键 Tap/Hold/Anchor、Hold 绑定起手键、鼠标 Path/Tail/Bell/Trace、Red 200ms、FULL/FRAY/LOST、COMBO、命中扩散环/火花/环弧闪光、PERFECT/GREAT/GOOD/MISS 判定字、试玩内 note 类型标签、结果面板
- osu!std 混合层导入：circle → 环上 Tap（连续 u）；slider → 环内平面 Slide Trace（星头按键 + 沿轨迹移动，尾部是轨迹终点不单独判定）；lazy/短/重复 → Hold；滑条带 Sentakki 式 wait 阶段，Hold 与下一个 note 重叠时夹短、不足 0.5 拍降级 Tap
- 连续角度：流内按 Sentakki 式 45° 步进，jump 用压缩角度差，360°/s 限速；不吸固定轨
- 可变 Tap 宽度：按相邻角度/时间补偿（45–75°），密集段更容易跟，jump 略窄
- 负拍前奏：最早 note 自动平移到 beat 0，并调整 offset；F5 从头不会漏前奏
- 试玩延迟：`audio/driver/output_latency=10`；顶部 `OFF` 与 `[` / `]` 可手动校准音频/输入综合延迟，Path 头尾改为窗口内可命中而不是窗口一开始就判 Miss
- 存档：JSON 主格式、原子写、`.bak.1..5`、60 秒/20 条命令自动保存、`user://autosave.json` 手动恢复
- 演示：32 音符示例谱、示例点击轨、3D 预览、五角星 Path 示例、试玩事件日志

## 格式互通

- **导入 `.osz`**：支持 osu!std 与 osu!taiko；circle → Tap、slider → Slide Trace/Hold、drumroll → Hold；spinner 跳过；多难度包会弹窗选择 `.osu`；导入报告列出保留/丢弃原因。
- **导入 Simai**：支持舞萌 `maidata.txt`（`.zip` 或 `.txt`）；Tap/Hold/Slide→环上 Path/Break→加宽 Tap/Touch→Bell 会导入，双押只保留顺流向一侧，中心 Touch 跳过；复杂轨迹先近似为圆弧；音频导入时转成 OGG，避免 MP3 在部分驱动上静音。
- **osu!std 混合层**：circle → 环上 Tap（连续 u、45–75° 宽度）；slider 用 B/L/C/P 判断方向和长度，能跟随的转成**环内平面 Slide Trace**，星头/圆环尾/轨迹一起出现，尾部只是轨迹终点、不单独判定；lazy/短/多重复转 Hold。没有 8 轨吸附，也没有全平面模式。
- **宽度补偿**：Tap/Path 头宽按相邻角度差和时间差自动变宽（52–110°），密集流加宽、jump 收窄；这是无轨环用来吸收 osu 不可打配置的主要手段。
- **taiko 映射**：don/kat 按 hitsound（whistle/clap = kat，finish = 大音符）分色；就近取 0/90/180/270 两车道，密集段（<0.32 拍）堆叠不甩圈；短滑条拆成拍点，长滑条（≥1.5 拍）→ Hold；spinner 跳过。
- **导出 `.lbp` v2**：按设计文档第 7 章输出 `[General] / [Video] / [Metadata] / [TimingPoints] / [BoundaryShapes] / [BoundaryEvents] / [ViewStates] / [Regions] / [Notes] / [Editor]`，保留 Path 五角星、Trace 二维点、Bell、Anchor 配对和颜色/锁定选项。
- 导入时会把 `.osz` 内的音频、背景、视频解包到 `user://imports/`；音频仍可用 ffmpeg 转码。
- Simai 的 V/wifi/p/q 等复杂轨迹先近似为圆弧；中心 Touch 和部分多段同头 Slide 会跳过并在报告里计数。
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

当前结果：**334 passed, 0 failed**。测试覆盖：

- 120 BPM / 变速 / offset 的时间换算与反解
- 新建谱面 BPM 三位小数/一位小数取整与 offset 三位小数规范化
- 每拍小节线细分数的合法性（0/负数/小数/非数字）与 N−1 条等分细线偏移
- 竖线数量合法性、21 条竖线的等分位置与最近竖线吸附
- 音符镜像的 Tap 角度、Bell center_u、Path 头尾/轨迹点/视觉偏移
- 长度体系：普通 Tap / Hold 头 = 0.5 l、大小 Tap 的 0–1.5 l 范围与两位小数吸附、环心 1/6 l、Path 不受影响、JSON 只给大小 Tap 写 `sized`/`size`
- 星星启动时间：ms→拍换算（120/60 BPM）、延迟期间星头不动、延迟后按原速滑动、尾判整体后移、`wait_beat` 更长时不额外推后、`delay_ms` 序列化与零值不写
- osu!std 落道：合成谱面里左/右/上/左上四个 circle 分别落到 4/0/6/5 道，且所有角度都是 45° 的整数倍
- FLAC 纳入可读取音频格式（经 ffmpeg 解码缓存）
- 圆的 C(u)、最近点反解、五角星 Path 表现层
- `.lbp` 导出头部/段落/Path 五角星/换行
- osu!std 导入的 offset/BPM/circle/slider/spinner 跳过、连续环流角度、可变宽度、Slide Trace/Hold 分类、B/L/C/P 曲线采样、负拍平移
- osu!taiko 导入的 don/kat 车道、密集堆叠、短滑条拆点、长滑条鼓滚、spinner 跳过
- Path 跳区擦除范围、擦除段不生成中段检查点、JSON / `.lbp` 保留
- 试玩打击音资源可加载
- Simai 导入的难度列表、offset、按钮角度、Hold/Slide 时长、双押删除、Path 尾冲突删除、Touch→Bell
- osu!std 的 45° 流步长、Slide wait 阶段、Hold 重叠夹短/降级
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
audio/     示例点击轨（脚本生成，18s）与试玩打击音（CC0）
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
- osu!std 的 slider 转成环内平面 Slide Trace（星头按键 + 沿轨迹，尾部只是终点）或 Hold（lazy/短/重复）；circle 仍是环上 Tap，角度连续、宽度 45–75°。星头和圆环尾与轨迹一起出现，尾部没有单独 Hit/Miss。
- 试玩判定偏移只在当前会话生效，不做自动延迟测量；如果设备/耳机延迟大，用 `[` / `]` 手动校准，或启动时加 `--audio-output-latency 5` 覆盖 10ms 缓冲。
- 命中窗口固定 40ms，尚未做 Perfect/Great/Good 分级；评分规则仍等文档冻结。
- 拍号分母固定 4；3/8、6/8 需要后续 BeatUnit 扩展。
- 示例音频是节拍点击轨，不是正式曲目；可以用“谱面”页替换音频路径。
- `.osz` 多难度包会弹出选择框；如果包内难度没有音频，仍可导入但预览无声。
- taiko 的 don/kat 会合并为 Tap，用宽度（58/76/90）区分 don/kat/大音符，不保留原颜色语义；车道按两车道就近分配，密集段堆叠。这是当前约定的导入映射。
- 打击音是 Freesound CC0 素材（Wood block hit / wood block / ShiningRinging / Fast swipe / Thin bell ding），来源与授权见 `audio/sfx/ATTRIBUTION.md`。
- 流速是编辑器/试玩会话选项，不写入谱面；谱面仍只保存固定预读 `pre_read_ms`。
- 音量滑杆目前是会话级，不写入谱面/配置文件；重启后回到 100%。
- osu!std 混合层是“可玩性重解释”，不是原谱 1:1 还原；Tap 角度经过方向步进/限速，宽度是自动补偿值；slider 的环内平面轨迹由原曲线方向/长度近似，不是原图逐点复刻。

## 字体与资源

- `assets/fonts/NotoSansSC-Regular.ttf` / `-Bold.ttf`：从系统 Noto Sans CJK SC 提取，随工程分发
- `assets/fonts/NotoSansMono-Regular.ttf` / `-Medium.ttf`：数值/拍号/时间读数
- `audio/demo_click.wav`：脚本生成的 120 BPM 示例点击轨
- `charts/demo.json`：示例谱，可另存或替换
