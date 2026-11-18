随程序带的 ffmpeg（GPL 构建，BtbN/FFmpeg-Builds）
=================================================

目录内容
--------
- linux64/ffmpeg.gz   Linux x86_64 的 ffmpeg 可执行文件，gzip 压缩
- win64/ffmpeg.gz     Windows x86_64 的 ffmpeg.exe，gzip 压缩
- LICENSE-FFmpeg.txt  FFmpeg 自己的许可证文本

为什么要压缩：单个可执行文件 170MB 左右，超过 GitHub 单文件 100MB 限制；
运行时 MediaIO 第一次用到 ffmpeg 时把它解压到
`user://tools/ffmpeg-<bundle>/ffmpeg`，之后直接复用（Linux 会 chmod +x）。

查找顺序（core/media_io.gd → MediaIO.exe()）
------------------------------------------
1. 设置里手动指定的 ffmpeg 路径（非默认值时优先，方便换成本机版本）；
2. 内置包（本目录）；
3. PATH 里的 `ffmpeg`。

许可与再分发
------------
构建来源：https://github.com/BtbN/FFmpeg-Builds （master-latest-*-gpl）
FFmpeg 源码：https://ffmpeg.org/download.html
本构建启用 GPL 组件（含 libx264），分发本目录里的二进制时需要：
1. 保留 LICENSE-FFmpeg.txt 与这段说明；
2. 指明源码获取方式（上面的 FFmpeg 链接）；
3. 不要把 ffmpeg 静态链进主程序（本程序用子进程调用，符合该要求）。

导出成正式版本时，记得把 `tools/ffmpeg/*` 作为非资源文件打进安装包
（Godot 导出预设的 include filter 里加上 `tools/ffmpeg/*`），
否则导出后的程序只会去 PATH 找 ffmpeg。
