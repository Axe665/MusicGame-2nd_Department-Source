# 测试与性能

## 运行测试

`.godot/` 不进仓库，所以第一次运行测试前要先导入资源：

```bash
godot --headless --path . --import
```

CI（`.github/workflows/ci.yml`）在 PR 和 push 到 `main` 时运行下面这些套件，`tests` job 是合并的必需检查。CI 环境装了 ffmpeg，所以 atempo 和转码相关的用例也会真的运行；本地没有 ffmpeg 时，这些用例会被 `has_ffmpeg` 守卫跳过。

```bash
godot --headless --path . --script res://tests/test_runner.gd      # 主测试集
godot --headless --path . --script res://tests/path_judgement.gd   # Path 判定回归
godot --headless --path . --script res://tests/alpha_commands.gd   # 演出指令
godot --headless --path . --script res://tests/sfx_playback.gd     # 打击音效回归
godot --headless --path . res://tests/replay_integration.tscn      # 回放集成测试
```

## 覆盖范围

### `test_runner.gd`

**时间与网格**

- 120 BPM、变速和 offset 的时间换算与反解
- 新建谱面时 BPM 的三位小数、一位小数取整，以及 offset 的三位小数规范化
- 每拍小节线细分数的合法性（0、负数、小数、非数字），以及 N−1 条等分细线的偏移
- 竖线数量的合法性、21 条竖线的等分位置和最近竖线吸附
- 小节线细分的吸附目标随 N 变化（1/4、1/3、1/5）
- 画布默认吸附：拍轴常开、轨道开关控制角度、Shift 两轴全跳过；红区松手回吸（起点吸小节线、时长不变、弧宽不吸）；这些设置随谱面的 `editor` 字段存盘，旧谱回到默认值
- 分音表（标签、步长、吸附、回退），画布上下翻转的坐标映射与往返一致性

**音符**

- 音符镜像：+180° 角度回绕、Bell 的 `center_u`、Path 头尾、平面坐标和视觉偏移
- 长度体系：普通 Tap / Hold 头 = 0.5 l，大小 Tap 的 0–1.5 l 范围和两位小数吸附，环心 1/6 l，Path 不受影响，JSON 只给大小 Tap 写 `sized` / `size`
- 音符修饰：`hs` / `sv` / `head_speed` / `spawn` / `bounce` 的夹取与往返，弹跳公式两端归位，A–E 触摸区到 33 路传感器的映射和镜像互换，旧谱面缺省字段
- 演出指令：32 条目录（判定线 1、文本 2、滤镜 29），默认参数与夹取，三段包络和 `KALEIDOSCOPE` 的有界开关语义，近义指令折叠（雪花噪点、碎裂 → 故障；高斯模糊、拖影 → 径向模糊），同名指令取最强，JSON 往返与未知指令丢弃
- 圆的 C(u)、最近点反解、五角星 Path 的表现层
- Path 跳区擦除范围、擦除段不生成中段检查点、JSON 和 `.lbp` 都保留这些数据

**边界**

- 固定飞行时长 `P(T)=C(u,T)`（多形状、多事件）
- 设计文档 §7.2 的 1 秒收缩算例：`R(t)=330−150t`，t=1 时为 180px
- BoundaryEvent 的 restore 回到快照，以及插值
- 批量边界采样与逐点求值一致（乱序分段、缺口、局部事件、变形与恢复）；拖动通知按帧合并、提交后校验、撤销/重做和环网格复用
- BoundaryFrame 跨帧复用的采样与原始求值一致，与光标最近点一致，同一时刻编辑后缓存失效
- 环线自交、非凸、变形过激被拒绝；BoundaryEvent 过渡采样检查

**校验与存档**

- JSON 保存 → 加载 → 保存字节稳定
- 示例谱全量校验
- 角度交集、红区差集、同刻可打性（红区覆盖唯一落脚点时拒绝）、Trace 距离

**导入导出**

- osu!std 落道：合成谱面里左、中、右、上、左上五个 circle 按 Sentakki 的流和大跳落到 5/1/1/6/4 道，所有角度都落在 Sentakki 的 45° 道上
- osu!std 导入：offset、BPM、circle、slider、spinner 跳过、连续环流角度、可变宽度、Slide Trace/Hold 分类、B/L/C/P 曲线采样、负拍平移
- osu!std 的 45° 流步长、Slide wait 阶段、同刻去重和尾判吸附
- `.osz` 多难度列表和指定难度导入
- Simai 导入：难度列表、offset、按钮角度、Hold/Slide 时长、同刻去重、重叠星星缩短/降 Tap、Touch 外圈排布
- 舞萌鼠标层：尾判吸附、轨迹压短、超过 45° 的快速折返压到 45°、A-B-A-B 交互段锁定（45° 仍超速时整段叠成一处）、45° 以内邻键来回（不少于 3 颗）收成叠键、压角后补一遍、Bell 与近旁 Tap/Hold 同角度、轨外音符删除、Hold 缩短
- `.lbp` 导出的头部、段落、五角星 Path 和换行

**媒体与音频**

- FLAC 纳入可读取的音频格式（经 ffmpeg 解码缓存）
- 媒体格式识别和原生路径透传
- WAV 解码（立体声 16 位、重采样到 11 kHz）与音量、频率校验
- 128 BPM 和 87 BPM 合成点击轨的自动识别（BPM ±0.2、offset ±8 ms），以及静音拒绝
- 试玩打击音资源可以加载

### `path_judgement.gd`

快速经过、直接碰尾、弯折/回环/折返、等待段、输入中断、重叠轨迹、容差跳组、短滑条保护、AUTO、重开和轨迹消除。

### `sfx_playback.gd`

各类音效的总线输出；舞萌导入谱和自制谱在编辑器和试玩中的触发；卡帧后补发、跳转后不补播；试玩静音切换。不验证扬声器或耳机的实际输出。

## 性能基准

CI 的 `perf` job 是性能回退门禁，只锁定稳定的指标：拖动的 CPU 中位数、覆盖层单次绘制时间、节点数和内存。没有 GPU 的 runner 上毫秒数有 ±50% 的抖动，所以基线容差设为 2×。这个 job 目前设为 `continue-on-error`，不阻塞合并。

```bash
godot --headless --path . res://tests/perf_harness.tscn -- \
  --scenario=all --notes=10000 --keys=200 --frames=40 --warmup=15 \
  --baseline=res://tests/perf_baseline.json
```

`tests/` 下还有这些工具：

| 文件 | 用途 |
|---|---|
| `editor_audit.tscn` | 编辑器功能矩阵审计 |
| `editor_bench.tscn` | 编辑器性能基准 |
| `input_audit.tscn` | 输入审计 |
| `bench_canvas.gd` / `bench_preview.gd` | 画布 / 预览绘制基准 |
| `perf_harness.tscn` + `perf_baseline.json` | 回退门禁和基线 |

## 已做的性能优化

**渲染**

- 使用 Forward+ / Vulkan，帧率上限 60。
- 3D 网格在变形期间跟随渲染帧更新，静止时复用。静止时 SubViewport 自动禁用，3D 内部按 0.8× 渲染。
- 时间轴的静态层和播放头拆成两层，播放时只重绘播放头。
- 试玩时，被覆盖的编辑器和它的 3D 视口暂停。
- Path 索引在进入试玩/换谱时预建：万音符谱的一次性建表（约 14ms）不再落在首帧。
- 同屏超过 24 条 Path 时省略方向箭头和履带纹，只保留轨迹本体。
- 滤镜 `TRAIL` 只在生效时更新历史帧子视口，其余时间完全停掉。

**检查器与界面**

- 编辑器交互不会重建检查器的整页。中文 Label 进入场景树时要重新计算最小尺寸，单个标签约 17ms，整页要 0.2–2.3 秒。撤销、读取和选择音符只刷新数值，标签页结构不变时复用已经建好的页。
- 状态栏和校验栏只在文字或颜色变化时才修改主题（`add_theme_color_override` 单次约 20ms）。
- 检查器标签 20Hz 更新，事件轨 20Hz，最近点 96 个采样，字号预加载。

**计算**

- 撤销不会重复跑一遍全谱校验。
- 边界批量采样时只对分段排序一次，变形插值参数按事件计算一次。
- BoundaryFrame 缓存形状采样，当前时刻的网格、音符和光标共用精确的边界求值，编辑后失效。
- Path 固定造型的采样和相机适配半径都复用。
- 拖动音符时按帧合并通知，不重建环网格，完整校验在松开鼠标后执行。

更早期的审计数据（10k 音符、200 段等场景）见 [路线图](roadmap.md)。
