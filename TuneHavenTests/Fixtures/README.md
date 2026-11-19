# 音频测试夹具

- `sine-2s.mp3`：既有导入测试夹具。
- `tagged.flac`：从上述夹具转换的 0.2 秒 FLAC，用于验证真实音频文件的中文标签、曲目号、日期、流信息，不依赖外网。

生成命令（在项目根目录执行）：

```sh
ffmpeg -i TuneHavenTests/Fixtures/sine-2s.mp3 -t 0.2 -c:a flac \
  -metadata title='测试夜曲' -metadata artist='TuneHaven Artist' \
  -metadata album='标签专辑' -metadata track='3/12' \
  -metadata date='2026-11-17' -metadata genre='Ambient' \
  TuneHavenTests/Fixtures/tagged.flac
```

FLAC 元数据格式依据 [RFC 9639 §8](https://www.rfc-editor.org/rfc/rfc9639.html#section-8)。

- `vbr-32s.mp3`：前 2 秒噪声、后 30 秒静音的 VBR MP3（约 130 KB）。码率前高后低，逐帧拷出又没有 Xing 帧时，AVFoundation 按开头码率估算的时长比实际短约 1.8 秒；文件太小时系统会扫完整个文件，看不出差异。用于验证 Apple Music MP3 导出补写的 Xing 帧。

```sh
ffmpeg -f lavfi -i "anoisesrc=d=2:a=0.3" -f lavfi -i "anullsrc=r=44100:cl=mono:d=30" \
  -filter_complex "[0][1]concat=n=2:v=0:a=1" -ac 1 -ar 44100 -c:a libmp3lame -q:a 6 \
  TuneHavenTests/Fixtures/vbr-32s.mp3
```
