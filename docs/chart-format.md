# 谱面格式

## 谱面文件夹

编辑器默认使用**三文件谱面文件夹**：

- 一个 `.json` 谱面文件
- 一个音频文件（`.wav` 或 `.ogg`）
- 一张曲绘（`.jpg`、`.jpeg` 或 `.png`）

示例见 `charts/夜に駆ける（示例）/`。

谱面文件内部仍然保存分组代码、组 BPM、颜色、形状、storyboard、commands 和音符修饰。

打开时兼容以下格式：

- 旧版的单个 `.json` 谱面
- 第二代的多 JSON 工程
- 新版的多 TMC 工程

新版 TMC 的读写代码仍然保留，但默认的「另存为」只生成三文件文件夹。

## 谱面 JSON

谱面 JSON 的顶层字段：

```text
format, version, general, metadata, default_shape, shapes, events,
boundary_keys, view_states, regions, timing, notes, groups,
group_bpm_points, current_group, editor, note_extras
```

其他会出现的字段：

- `commands`：演出指令，见 [环编辑器](ring-editor.md#演出指令)。
- `editor`：保存编辑器状态，例如小节线细分、轨道吸附和 `editor.flow_down`（写谱方向）。
- `note_extras`：音符修饰（`hs`、`sv`、`spawn` 等），旁挂保存，不改变紧凑代码。Path 的 `show_trail`、`trail_rgb`、`custom_shape` 也在这里。
- `metadata.storyboard`：故事板素材路径。

JSON 往返（保存 → 加载 → 保存）是字节稳定的。

## 紧凑代码

notes 和 shapes 使用紧凑代码。`timing` 位于 `notes` 之前。

```text
[id]tap(beat,angle[,width[,1,size]])
[id]hold(beat,end,angle[,width])
[id]path{(part0,beat,angle,end,end_angle,centrifuge,axis[,wait,id]);...}
[id]seek(beat,orien)
[id]anchor(beat,angle,pair_id[,pair])
[id]bell(beat,angle[,width[,radius]])
[id]red(beat,end_beat,width[,angle][,shape=S][,polarity=N])
shape{[id,closed,segments{...}];...}
```

- `shape` 写成单块、无缩进。
- 宽度和大小 Tap 的字段只在非默认值时追加：
  - 普通 Tap 不写宽度（60°，0.5 l）
  - 普通 Hold 不写宽度（60°）
  - 普通 Bell 不写宽度和半径（30°，26px）
- 旧版程序读到这些追加的尾部字段时会忽略，旧谱面照常载入。
- Path 的 `wait` 字段可选，没有这个字段的旧谱面同样兼容。

音符 ID 的编号规则见 [编辑器](editor.md#剪贴镜像与-id)。

## 难度套组 `.set.json`

一个文件装下一首歌的所有难度：

```json
{"format": "tamaki3-set", "difficulties": [{"name": "...", "chart": {}}]}
```

- 用 `ChartIO.load_set` / `ChartIO.save_set` 读写。
- 「文件 → 打开」会自动识别套组文件；Ctrl+S 保存整个套组。
- 「文件 → 新增难度（复制当前）」复制当前难度，新增一份。
- 「文件 → 另存为」把当前难度单独存成普通的 `.json`。

## 存档与自动保存

- 主格式是 JSON，采用原子写入，保留 `.bak.1` 到 `.bak.5` 五份备份。
- 每 60 秒或每 20 条命令自动保存一次，写到 `user://autosave.json`，需要时手动恢复。
- 转谱子窗口的自动保存写到 `user://autosave_import.json`，见 [导入与导出](import-export.md#转谱流程)。

## 用户数据目录

编辑器在 Godot 的 `user://` 目录下保存这些文件：

| 路径 | 内容 |
|---|---|
| `settings.json` | 画质、HUD、判定偏移、试玩设置等 |
| `editor.cfg` | 手动指定的 ffmpeg 路径等 |
| `autosave.json` / `autosave_import.json` | 自动保存 |
| `sets/` | 导入后生成的难度套组 |
| `imports/` | 从 `.osz` 等解包的素材 |
| `media/` | 转码和变速缓存 |
| `analysis/` | BPM 检测用的 PCM 缓存 |
| `tools/` | 解压后的内置 ffmpeg |
| `chart_cache/` / `chart_favorites.json` | 舞萌在线谱面的缓存和收藏 |
| `osu_covers/` | osu! 封面缓存 |
| `storyboards/` | 故事板编辑器的工作目录 |
| `logs/` | Path 输入诊断日志 |
