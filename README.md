# Tamaki₃ 制谱器

[![CI](https://github.com/Axe665/MusicGame-2nd_Department-Source/actions/workflows/ci.yml/badge.svg)](https://github.com/Axe665/MusicGame-2nd_Department-Source/actions/workflows/ci.yml)

《Tamaki₃》的谱面编辑器，基于 Godot 4.7 开发。Tamaki₃ 是一款环形判定的节奏游戏：音符从圆心飞向一个可以变形的判定环，玩家用键盘按键，同时用鼠标在环上瞄准、滑动和滚动。

这个编辑器可以完成写谱、预览和试玩的整个流程，也可以把 osu! 和舞萌（Simai）谱面转换成 Tamaki₃ 谱面。

## 功能

- **编辑**：u×时间画布，吸附到「小节线 × 角度格线」；支持框选、批量剪贴、镜像和 200 步撤销（按音符总量限内存）
- **8 种音符**：Tap、Hold、Path（滑条）、Seek（滚轮）、Anchor（双押）、Bell（扫键）、Limit（红区）和 Trace
- **边界与镜头**：分段曲线边界，在环编辑器的时间轴上编排形状、镜头关键帧和演出指令（判定线、文本、24 种全屏滤镜）
- **3D 预览**：GPU 绘制的环网格、相机投影、BGA 视频和 osu! storyboard
- **试玩**：按 F5 进入，使用真实判定（PERFECT / GREAT / GOOD / BAD / MISS），支持 AUTO 演示、判定偏移校准、结算统计和回放视频导出
- **导入导出**：支持 osu!std、舞萌 `maidata.txt`；可以浏览和下载在线谱面库；可以导出 `.lbp` v2
- **媒体**：支持主流音频和视频格式，内置 ffmpeg；可以自动识别 BPM 和 offset

## 快速开始

需要 [Godot 4.7.2](https://godotengine.org/download/)。

```bash
git clone https://github.com/Axe665/MusicGame-2nd_Department-Source.git
cd MusicGame-2nd_Department-Source
godot --path .
```

也可以在 Godot 编辑器里打开 `project.godot`，然后按 F5 运行。

首次启动会载入示例谱 `charts/夜に駆ける（示例）/`。

### 常用快捷键

| 按键 | 作用 |
|---|---|
| 空格 | 播放 / 暂停 |
| 1–7 | 切换音符工具：Tap / Hold / Path / Seek / Anchor / Bell / Limit |
| F5 / Shift+F5 | 从播放头试玩 / 从头试玩 |
| K | 打开环编辑器 |
| Ctrl+S / Ctrl+Z / Ctrl+Y | 保存 / 撤销 / 重做 |
| Shift（按住） | 本次操作不吸附 |

完整的快捷键列表见 [上手指南](docs/getting-started.md#快捷键)。

## 文档

| 文档 | 内容 |
|---|---|
| [上手指南](docs/getting-started.md) | 运行、界面布局、全部快捷键、命令行参数 |
| [编辑器](docs/editor.md) | 画布、吸附、放置与拖动、Path 编辑、检查器、分组 |
| [音符](docs/notes.md) | 各类音符的语义、长度体系和视觉表现 |
| [环编辑器](docs/ring-editor.md) | 形状和镜头关键帧、演出指令 |
| [试玩与判定](docs/playtest.md) | 判定窗口、输入规则、校准、AUTO、HUD、画质 |
| [导入与导出](docs/import-export.md) | osu!、舞萌、在线谱面、转谱优化规则、`.lbp` 导出 |
| [故事板与回放导出](docs/storyboard-and-replay.md) | osu! storyboard、故事板编辑器、回放视频导出 |
| [谱面格式](docs/chart-format.md) | 谱面文件夹、紧凑代码、难度套组、存档 |
| [媒体与音频](docs/media-and-audio.md) | 支持的格式、ffmpeg、BPM 检测、打击音效 |
| [测试与性能](docs/testing.md) | 测试命令、覆盖范围、性能基准 |
| [已知限制](docs/limitations.md) | 未实现的功能和已知问题 |
| [路线图](docs/roadmap.md) | 早期开发的工作记录 |

设计文档在 [`环 GameDesign/`](<环 GameDesign/>)（docx 和 pdf）。当前版本是：

- 《Tamaki₃ 制谱器设计文档 v3.2（适配玩法 v6.4）》
- 《Tamaki₃ 玩法 v6.4—修订图文版》

旧版本在 `修订前备份/` 中；[`Path设计图/`](<环 GameDesign/Path设计图/>) 是原始的 SVG/PNG 视觉参考。

## 项目结构

```text
core/       引擎无关的谱面模型：时间/边界数学、校验、读写、导入转换
charter/    编辑器 UI、3D 预览、画布、检查器、试玩
tests/      无头测试、审计和性能基准
charts/     示例谱面
assets/     内置字体（Noto Sans CJK SC / Noto Sans Mono）
audio/      示例点击轨和打击音效
addons/     EIRTeam.FFmpeg（BGA 视频解码）
tools/      内置 ffmpeg 可执行文件
design/     视觉参考和音符对比台
docs/       项目文档
```

`core/` 不依赖窗口、音频或皮肤，可以直接在游戏本体中复用。编辑器、预览和试玩共用同一套边界求值 `C(u,t)`、预读 `P(u,q,t)`、最近点计算和校验器。

## 测试

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/test_runner.gd
```

CI 会在每个 PR 上运行全部测试套件。其他测试套件和性能基准见 [测试与性能](docs/testing.md)。

## 第三方组件

| 组件 | 用途 | 许可 |
|---|---|---|
| [EIRTeam.FFmpeg](https://github.com/EIRTeam/EIRTeam.FFmpeg) | BGA 视频直接解码 | MIT |
| [FFmpeg](https://ffmpeg.org/)（[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds)） | 转码、变速、视频导出 | GPL，见 [`tools/ffmpeg/README.txt`](tools/ffmpeg/README.txt) |
| Noto Sans CJK SC / Noto Sans Mono | 界面字体和数值读数（`assets/fonts/NotoSansSC-*.ttf`、`NotoSansMono-*.ttf`） | SIL OFL |
| Freesound 音效 | 打击音 | CC0，见 [`audio/sfx/ATTRIBUTION.md`](audio/sfx/ATTRIBUTION.md) |

osu! 滑条转换和落道算法参考了 [Sentakki](https://github.com/LumpBloom7/sentakki)；storyboard 解码移植自 [ppy/osu](https://github.com/ppy/osu) 和 osu-framework；演出滤镜的语义对齐 MajdataPlay。

## 许可证

本项目尚未指定许可证。
