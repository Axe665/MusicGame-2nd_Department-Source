EIRTeam.FFmpeg（BGA 直接解码）
================================

来源：https://github.com/EIRTeam/EIRTeam.FFmpeg
许可：MIT（扩展本身）
二进制版本：autobuild-2026-10-07（eirteam-ffmpeg-84ea333）

目录内容
--------
- win64/  Windows x86_64 的 libgdffmpeg 与 FFmpeg 运行时（avcodec/avformat/avutil/
          avfilter/swresample/swscale DLL）
- linux64/ Linux x86_64 的 libgdffmpeg 与同一套 FFmpeg .so（RUNPATH=$ORIGIN）
- ffmpeg.gdextension  只声明 Windows / Linux x86_64；其他平台（macOS / Android /
                      arm64）运行时会退回 ffmpeg 后台转码

FFmpeg 部分为 LGPL 构建（EIRTeam/FFmpeg-Builds，ffmpeg-master-latest-*-lgpl-godot），
随程序动态链接，未做静态链接。分发本项目时需要：
1. 保留本说明和 FFmpeg 的 LGPL 许可文本；
2. 保持 av* 库为可替换的动态库（不要合并进主程序）；
3. 提供 FFmpeg 源码获取方式（https://ffmpeg.org/download.html）。

h264 解码涉及专利；是否可分发请按你所在地区的法律自行判断。
