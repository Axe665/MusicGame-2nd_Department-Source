# Tamaki₃ 剩余工作清单

> 基线：分支 `feat/tamaki3-charter`，测试 253 passed / 0 failed。
> 最近提交：Path 平面化、Hold 弯条、osu/Simai 平面 Path、编辑器平面绘制。

## A. Path 平面化重构（最高优先）

已确认方案：

- Path 头在环上，身体/尾在平面；尾默认落在 0.65–0.75R 内圈。
- 头部：鼠标到头 + 按键。
- 中段：鼠标到 2D 轨迹距离，FULL / FRAY / LOST。
- 尾部：鼠标到 2D 尾点 + 时间窗口。
- 跳区：鼠标向前跳过时削掉该段轨迹，且不累计距离。
- 删除环 Path 支持；旧环 Path 需要迁移/重画。
- 视觉：V 形箭头列 + 大号发光球拖尾；已过段变暗。
- 双押继续删一侧，保持单手可玩。

任务：

- [x] `Note` 增加 `space="plane"` Path 采样，复用 `trace_pts` 归一化 `(x,y)`。
- [x] 平面 Path 渲染：头从环上飞入，身体/尾在平面。
- [x] 中段 2D 距离判定 + FULL/FRAY/LOST。
- [x] 尾部 2D 点判定。
- [x] 按鼠标实际扫过区间擦除；相邻区间合并，远离头部的接触不会误删整条轨迹。
- [x] 删除平面 Path 的环上尾提示弧。
- [x] 删除环 Path 支持；旧环 Path 自动迁移成 1.0R→0.72R 的平面弧。

## B. 导入改造

- [x] osu 滑条 → 平面 Path（Sentakki：head tap + wait/shoot delay + B/L/C/P 采样），不再生成滑条 Trace。
- [x] Simai Slide → 平面 Path：按 Sentakki 思路区分形状，圆角平滑 + 自交回退 + 超速退化直线，尾落回按钮环位。
- [x] 双押继续删一侧。
- [x] 导入报告改为 Path 计数；不再生成滑条 Trace。
- [x] `Trace` 仅保留给手绘擦带，不再由 osu 滑条生成。

## C. 编辑器

- [x] Path 工具改为平面拖点；头从环上开始。
- [x] 拖动节点更新 `trace_pts`，不再用 `tail_angle` 作为判定依据。
- [x] 检查器 Path 页：头部角度/宽度、尾部半径/角度、容差、采样密度、滑动速度。
- [x] Path 中间判定点设计：采样点显示 + 手动加/删/调 beat/角度，判定仍为滑到即可。
- [x] 旧环 Path 打开时自动按平面弧读取，不再渲染环上体。

## D. Hold 视觉

- [x] 直 Hold / 弯 Hold 两种形态；osu、Simai 导入默认直 Hold。
- [x] 头部圆头 + 端环更明确。
- [x] 体段沿环弯曲；保留端环 + 游标 + 渐隐。
- [x] 与 Tap 形状/描边明确区分（弯胶囊 vs 圆环）。
- [x] 直 Hold 使用内圈→环上的圆头胶囊；弯 Hold 沿环弯曲。

## E. 音符视觉语言

形状照搬图示，颜色保留语义：

- [x] Tap：固定粉色圆环 + 暗芯（宽度只用于判定，不再拉成长条）。
- [x] Hold：金色胶囊 + 粉色圆环头（参考 maimai 实机帧 BV1C34y187NU）。
- [x] Path/Slide：细线 + 密集 V 形箭头 + 星头/星尾。
- [ ] Break：橙色强调环（当前只加宽）。
- [x] 四套音符外观（糖霜/霓虹/玻璃/贴纸），F6 实时切换；`design/note_lab.html` 网页对比台。
- [ ] BOTH：不做判定类型，保持单手。

## F. 在线谱面

已完成：

- [x] adxdls 目录、搜索、版本/曲风筛选、下载、难度选择、curl 超时。
- [x] majdata 搜索、下载、难度选择、curl 绕过 Cloudflare。
- [x] 实时下载进度：KB / 总大小 / 百分比 + 进度条。

未完成：

- [ ] majdata 分页（目前只 page 0）。
- [ ] majdata 按等级/标签筛选。
- [x] 下载百分比进度（HEAD Content-Length + 后台 curl 轮询）。
- [ ] 失败重试 UI / 取消下载。

## G. 性能

已完成：

- [x] 光标 `nearest_u` 缓存。
- [x] 六类 note 按拍二分裁剪。
- [x] Trace 点缓存、Path 体点缓存（视图旋转/resize 失效）。

未完成：

- [x] Path 运行缓存按缺口/形变失效；下层 Path 简化绘制；时间轴只画可视音符。
- [ ] 每帧只算一次环中心与 `note_scale`。
- [ ] Overlay 静态/动态拆层（评估后收益低，暂缓）。
- [x] 3D 环网格变形限频 30Hz。

## H. Simai

已完成：

- [x] 指令 slot 修正（音画同步）。
- [x] V/p 折点、`*` 取最长单分支。
- [x] 难度选择、直接读文件夹 track、OGG 转码。
- [x] 14 个难度实测 0 校验错误。

未完成：

- [ ] wifi 扇形 / 多分支同时展开的精确视觉（只做视觉、不判定）。
- [ ] TouchHold / 中心 Touch 完整映射（当前 Bell/跳过）。

## I. 判定 / 音频

已完成：

- [x] Tap 100 / 170 / 260ms，Great/Good 不断连（鼠标谱放宽）。
- [x] Hold 绑定起手键、端环、游标。
- [x] Bell 112px 收取、300ms 窗口。
- [x] 打击音整体 +4–6dB。
- [x] FULL/FRAY/LOST 尾端文字。
- [x] 四套打击特效（迸裂/圆环/棱镜/墨滴），F7 实时切换；Bell 吸附收缩环 + 四向吸点。
- [x] 八套音效按类型调电平。

未完成：

- [x] 平面 Path 中段改为“滑到即可”，不再逐点扣分。
- [x] 非 Tap 判定半径放大：Path 头 92px / 尾 96px、Trace 接触 56px、Bell 112px。
- [ ] 平面 Path 尾部容差仍需实机校准。
- [ ] 打击音进一步分层重编（当前只是电平调整）。

## J. 已确认但未移植 / 暂缓

- [x] DaChuTim BPM/offset 自动检测 + 歌曲导入。
- [ ] DaChuTim `ChartOverlay` 拆分（评估低收益，暂缓）。
- [x] 主线性能修复（Quartex246）已合并。

## 已知风险

- 平面 Path 会改变所有 osu/Simai 滑条手感，必须重新试玩校准容差。
- 删除环 Path 会让旧 `.json` / `.lbp` 谱面中的环 Path 失效，需要迁移或重画。
- majdata 依赖外部 `curl`；未安装 curl 的机器无法下载。
