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
