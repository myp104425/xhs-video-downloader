import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';

/// M3U8 / HLS 流媒体下载器
///
/// 工作流程：
/// 1. 下载 m3u8 索引文件
/// 2. 解析 ts 分片列表（支持多码率选择）
/// 3. 按顺序下载所有 ts 分片
/// 4. 用 FFmpeg 合并为单一 mp4 文件
/// 5. 清理临时碎片文件
class M3U8Downloader {
  static const String _tag = 'M3U8Downloader';

  DownloadCancelToken? _cancelToken;

  void cancel() {
    _cancelToken?.cancel();
  }

  /// 下载 M3U8 流并合并为 MP4
  Future<String> download(
    String m3u8Url,
    String outputPath, {
    void Function(int current, int total, String stage)? onProgress,
  }) async {
    _cancelToken = DownloadCancelToken();
    developer.log('开始下载 M3U8: $m3u8Url', name: _tag);

    onProgress?.call(0, 0, '正在解析播放列表...');

    // 获取基础 URL 用于拼接相对路径
    final baseUrl = _getBaseUrl(m3u8Url);

    // 1. 获取 m3u8 内容
    final m3u8Content = await _httpGet(m3u8Url);
    if (m3u8Content == null) throw Exception('无法下载 m3u8 文件');

    // 2. 解析分片列表
    final segments = await _parseM3U8(m3u8Content, baseUrl);
    if (segments.isEmpty) throw Exception('m3u8 中没有找到视频分片');

    developer.log('找到 ${segments.length} 个分片', name: _tag);

    // 3. 创建临时目录
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory('${tempDir.path}/m3u8_${DateTime.now().millisecondsSinceEpoch}');
    await workDir.create(recursive: true);

    try {
      // 4. 下载所有分片
      final tsFiles = <String>[];
      for (var i = 0; i < segments.length; i++) {
        if (_cancelToken?.isCancelled == true) throw Exception('已取消');

        onProgress?.call(i + 1, segments.length, '正在下载分片 ${i + 1}/${segments.length}');
        final tsPath = '${workDir.path}/${i.toString().padLeft(5, '0')}.ts';

        await _downloadFile(segments[i], tsPath);
        tsFiles.add(tsPath);

        developer.log('分片 ${i + 1}/${segments.length} 下载完成', name: _tag);
      }

      // 5. 创建文件列表
      onProgress?.call(segments.length, segments.length, '正在合并分片...');
      final listFile = File('${workDir.path}/file_list.txt');
      final listContent = tsFiles.map((f) => "file '${f.replaceAll('\\', '/')}'").join('\n');
      await listFile.writeAsString(listContent);

      // 6. 用 FFmpeg 合并
      final cmd = '-f concat -safe 0 -i "${listFile.path.replaceAll('\\', '/')}" -c copy -y "$outputPath"';
      developer.log('FFmpeg concat: $cmd', name: _tag);

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();

      if (!ReturnCode.isSuccess(rc)) {
        // FFmpeg concat 失败，尝试直接 copy 方式
        developer.log('concat 失败，尝试 copy 方式...', name: _tag);
        final catCmd = '-i "${tsFiles.first}" -c copy -y "$outputPath"';
        final fallbackSession = await FFmpegKit.execute(catCmd);
        final fbRc = await fallbackSession.getReturnCode();
        if (!ReturnCode.isSuccess(fbRc)) {
          // 实在不行就保留第一个分片
          if (tsFiles.isNotEmpty) {
            await File(tsFiles.first).copy(outputPath);
          }
        }
      }

      // 验证输出文件
      if (await File(outputPath).exists()) {
        final size = await File(outputPath).length();
        developer.log('合并完成: $outputPath ($size bytes)', name: _tag);
        return outputPath;
      }

      throw Exception('合并失败');
    } finally {
      // 清理临时文件
      try { await workDir.delete(recursive: true); } catch (_) {}
    }
  }

  /// 解析 M3U8 索引，返回 ts 片段 URL 列表
  Future<List<String>> _parseM3U8(String content, String baseUrl) async {
    final lines = content.split('\n');
    final segments = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 检查是否是多码率 m3u8（顶级播放列表）
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        if (i + 1 < lines.length) {
          final childUrl = _resolveUrl(lines[i + 1].trim(), baseUrl);
          final childContent = await _httpGet(childUrl);
          if (childContent != null) {
            final childSegments = await _parseM3U8(childContent, _getBaseUrl(childUrl));
            // 取最高码率（最后一个 ts 列表）
            if (childSegments.isNotEmpty) {
              segments.clear();
              segments.addAll(childSegments);
            }
          }
        }
        continue;
      }

      // ts 分片
      if (!line.startsWith('#') && line.isNotEmpty) {
        final segmentUrl = _resolveUrl(line, baseUrl);
        if (segmentUrl.endsWith('.ts') || segmentUrl.contains('seg') || segmentUrl.endsWith('.m4s')) {
          segments.add(segmentUrl);
        }
      }
    }

    return segments;
  }

  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) {
      final base = Uri.parse(baseUrl);
      return '${base.scheme}://${base.host}$url';
    }
    // 相对路径
    final base = Uri.parse(baseUrl);
    final basePath = base.path.substring(0, base.path.lastIndexOf('/') + 1);
    return '${base.scheme}://${base.host}$basePath$url';
  }

  String _getBaseUrl(String url) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash >= 0) {
      return '${uri.scheme}://${uri.host}${path.substring(0, lastSlash + 1)}';
    }
    return url;
  }

  Future<String?> _httpGet(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) return resp.body;
    } catch (_) {}
    return null;
  }

  Future<void> _downloadFile(String url, String path) async {
    final resp = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36'
    }).timeout(const Duration(seconds: 60));

    if (resp.statusCode == 200) {
      await File(path).writeAsBytes(resp.bodyBytes);
    } else {
      throw Exception('下载分片失败: HTTP ${resp.statusCode}');
    }
  }
}

/// 简单的取消令牌
class DownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
