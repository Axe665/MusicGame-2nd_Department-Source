# 媒体与音频

## 支持的格式

| 类型 | 直接支持 | 自动转码（需要 ffmpeg） |
|---|---|---|
| 音频 | WAV / OGG / MP3 | FLAC / M4A / AAC / OPUS / WebM / MP4 |
| 视频 | Ogg Theora（`.ogv`），以及经 gdffmpeg 直接解码的 MP4 / M4V / WebM / MOV / MKV / AVI | 缺少解码库时，兜底转为 OGG Theora |

### 音频

- 转码结果缓存在 `user://media/`，按「源路径 + 文件 mtime + 文件大小」的哈希命名；替换同一路径的源文件后会自动重新转码。谱面保存的仍然是原始路径，便于重新链接。
- FLAC 经 ffmpeg 解码后缓存。
- 应用自动识别结果的条件：BPM 检测成功、offset 在一拍范围以内，并且播放流的时长和解码后音频的时长一致。

### 视频（BGA）

- 视频用作环后面的背景层，默认 35% 不透明度，再乘以全局的「背景明暗」。`videoOffset` 独立于音频的 offset。
- 导入入口：「文件 → 导入视频…」，或检查器里的「视图/设置 → 视频 → 选择视频…」。导入时显示百分比进度，谱面仍然保存原始路径。
- 检测到 BGA 时，不再叠加谱面的静态背景图。
- 视频只在出现漂移时才 seek。

**直接解码**

`addons/ffmpeg` 里带有 [EIRTeam.FFmpeg](https://github.com/EIRTeam/EIRTeam.FFmpeg)（MIT 许可，GDExtension + libav）。仓库里已经提交了 Windows 和 Linux x86_64 的库以及 FFmpeg 运行时，克隆下来就能用。

- `.ogv` 仍然使用引擎自带的 Theora 解码。
- mp4、webm、mov、mkv、avi 直接交给 gdffmpeg 解码，所以**导入带 BGA 的谱面不会卡住，也不会产生转码缓存**。

**兜底转码**

如果当前平台没有对应的二进制（macOS、Android、arm64），或者解码库加载失败，会自动退回 ffmpeg 后台转码：540p、30fps，显示进度，结果写到 `user://media`。这时 `.ogv` 以外的格式仍然可以播放。

要补充平台支持，把上游 release 里对应平台的目录放进 `addons/ffmpeg/`，再在 `ffmpeg.gdextension` 的 `[libraries]` 和 `[dependencies]` 里各加一行。

「设置 → 转码 / 变速缓存」可以查看缓存占用并一键清理。

## 内置 ffmpeg

`tools/ffmpeg/<平台>/ffmpeg.gz` 随仓库附带一份 GPL 构建（来自 BtbN/FFmpeg-Builds）。第一次用到时解压到 `user://tools/ffmpeg-<版本>/`（Linux 上会 `chmod +x`），之后复用。

查找顺序：

1. 设置里手动指定的路径
2. 内置包
3. `PATH` 里的 `ffmpeg`

BPM 检测、FLAC 转码、变速不变调和视频封装都走同一个入口 `MediaIO.exe()`，不要求系统另外安装 ffmpeg。

许可和再分发说明见 `tools/ffmpeg/README.txt`。

## BPM 自动检测

### 使用

- 导入歌曲或新建谱面时自动识别基准 BPM 和首拍 offset。结果用弹窗给出，可以用倍数按钮处理半速或倍速，手动修改后点「应用」或「只取 BPM」。
- 分析在后台线程运行，不卡界面，结果按音频路径缓存。
- 识别需要拿到 PCM 数据：WAV 直接解析；其他格式（包括 mp3 和 ogg）用 ffmpeg 解成 11 kHz 单声道，缓存到 `user://analysis/`。导入弹窗里可以指定 ffmpeg 路径，存在 `user://editor.cfg`。

### 算法

三频带起始包络 → 自相关 → 梳状相位 → 拍点跟踪，最后用原始采样的攻击位置对齐。

### 倍数校正

导入窗口和新建窗口都有 **÷4 / ÷2 / ÷1.5 / 原值 / ×1.5 / ×2 / ×4** 按钮。

- 永远相对「检测值」计算，不会叠加；offset 保持同一个锚点。
- 1.5 是专门为「三拍被当成两拍」准备的，例如 150 → 100、238 → 158、196 → 131。
- 已经有谱面时，检测结果会自动吸附到谱面 BPM 的最近倍数（±4% 以内），所以「重新识别当前音频」不会把原来的 BPM 改坏。

### 准确度

用 68 张已有谱面实测（谱面 BPM 与官方 wiki 一致，并用 Oshama Scramble! 190、ENERGY SYNERGY MATRIX 160、PANDORA PARADOXXX 150 核对过）：

- **39 张**在原值 ±0.5 BPM 以内
- 加上倍数校正后，**63 张**能凑回原值

识别结果只是初始值，半速/倍速和弱起前奏仍然需要人工确认。

## 打击音效

编辑器播放和 F5 试玩共用 `charter/hit_sfx.gd` 里的 `HitSfx` 音效池：10 路播放器轮转，加轻微的随机音高。音效文件都在 `audio/sfx/`。

| 文件 | 用途 |
|---|---|
| `tap_don.ogg` | 普通 Tap / don、Hold 头部 |
| `hold_end.ogg` | Hold 完成（头尾都不再额外调整音高） |
| `path.wav` | Path 头部、滑动型 Trace 的起点 |
| `path_tail.wav` | Path 终点 |
| `trace.wav` | Trace 完成；编辑器预听时在起点触发 |
| `anchor.wav` | Anchor 命中 |
| `bell.ogg` | 金键命中 |
| `slide.wav` | 星星开始沿轨迹移动（`beat + wait`）时的「起划」提示音 |

- Hold、Path 和 Anchor 使用分层音色（合成的 WAV，由瞬态、音体和短尾组成）。
- 打击音是 Freesound 上的 CC0 素材（Wood block hit / wood block / ShiningRinging / Fast swipe / Thin bell ding），来源和授权见 [`audio/sfx/ATTRIBUTION.md`](../audio/sfx/ATTRIBUTION.md)。

### 音量与风格

- `HitSfx.KIND_DB` 控制各类音效的音量（dB）。
- `STYLE_PITCH` / `STYLE_DB` 控制「原声、清脆、厚重」三种风格的音高和音量，它们共用上面这些文件。
- 编辑器运输条的「音效」滑杆控制共用的 SFX 总线；「打击音」复选框只控制编辑器预听。
- 外观设置里的「打击音效 → 静音」同时影响编辑器和试玩，改回「原声」即可解除。
- 音量滑杆目前是会话级的，不写入谱面或配置文件，重启后回到 100%。

### 替换音效

1. 准备 WAV（建议 44.1 kHz、16 位 PCM）或 OGG Vorbis 文件。短音效建议去掉开头的静音。
2. 用同名文件覆盖 `audio/sfx/` 里对应的文件。
3. 回到 Godot，等待重新导入，然后重新运行游戏。

注意：

- 保留 `.import` 文件，它记录了导入设置。
- 不要修改 `.godot/imported/` 里的缓存。
- 如果使用新的文件名或格式，要同步修改 `HitSfx.PATHS` 里对应的路径。

## 音频延迟

- 项目设置为 `audio/driver/output_latency=3`、`mix_rate=48000`。在 PC 上实测，缓冲设置直接决定总延迟：`output_latency` 为 10 时约 39ms，为 3 时约 12ms。
- 如果某台机器出现爆音或咔哒声，在「设置 → 音频缓冲」里改为「标准 10ms」。这个设置写入 `override.cfg`，重启后生效。
- 判定偏移和输出延迟的校准见 [试玩与判定](playtest.md#偏移与校准)。
