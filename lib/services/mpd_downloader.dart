import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'm3u8_downloader.dart';

/// DASH MPD 流媒体下载器（纯 Dart，无 FFmpeg）
///
/// 工作流程：
/// 1. 下载 mpd 清单文件
/// 2. 解析视频和音频轨道
/// 3. 分别下载各分段
/// 4. 纯 Dart 拼接合并
class MPDDownloader {
  static const String _tag = 'MPDDownloader';

  CancelToken? _cancelToken;

  void cancel() {
    _cancelToken?.cancel();
  }

  /// 下载 MPD 流并合并为 MP4
  Future<String> download(
    String mpdUrl,
    String outputPath, {
    void Function(int current, int total, String stage)? onProgress,
  }) async {
    _cancelToken = CancelToken();
    developer.log('开始下载 MPD: $mpdUrl', name: _tag);

    onProgress?.call(0, 0, '正在解析 DASH 清单...');

    final baseUrl = _getBaseUrl(mpdUrl);
    final mpdContent = await _httpGet(mpdUrl);
    if (mpdContent == null) throw Exception('无法下载 mpd 文件');

    final videoSegments = <String>[];
    final audioSegments = <String>[];

    await _parseMPD(mpdContent, baseUrl, videoSegments, audioSegments);

    if (videoSegments.isEmpty) throw Exception('MPD 中没有找到视频轨');

    onProgress?.call(0, videoSegments.length + audioSegments.length, '正在下载...');

    final tempDir = await getTemporaryDirectory();
    final workDir = Directory('${tempDir.path}/mpd_${DateTime.now().millisecondsSinceEpoch}');
    await workDir.create(recursive: true);

    try {
      // 下载视频分段
      final videoFiles = <String>[];
      for (var i = 0; i < videoSegments.length; i++) {
        if (_cancelToken?.isCancelled == true) throw Exception('已取消');
        onProgress?.call(i + 1, videoSegments.length + audioSegments.length, '下载视频 ${i + 1}/${videoSegments.length}');
        final path = '${workDir.path}/v${i.toString().padLeft(5, '0')}.m4s';
        await _downloadFile(videoSegments[i], path);
        videoFiles.add(path);
      }

      // 下载音频分段
      final audioFiles = <String>[];
      for (var i = 0; i < audioSegments.length; i++) {
        if (_cancelToken?.isCancelled == true) throw Exception('已取消');
        onProgress?.call(videoSegments.length + i + 1, videoSegments.length + audioSegments.length,
          '下载音频 ${i + 1}/${audioSegments.length}');
        final path = '${workDir.path}/a${i.toString().padLeft(5, '0')}.m4s';
        await _downloadFile(audioSegments[i], path);
        audioFiles.add(path);
      }

      onProgress?.call(0, 0, '正在合成...');

      // 纯 Dart 拼接合并
      if (videoFiles.isNotEmpty) {
        final output = File(outputPath);
        final sink = output.openWrite();
        try {
          for (final f in videoFiles) {
            final bytes = await File(f).readAsBytes();
            sink.add(bytes);
          }
          // 如果有音频，追加在视频后面
          for (final f in audioFiles) {
            final bytes = await File(f).readAsBytes();
            sink.add(bytes);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      }

      if (await File(outputPath).exists()) {
        return outputPath;
      }
      throw Exception('DASH 下载失败');
    } finally {
      try { await workDir.delete(recursive: true); } catch (_) {}
    }
  }

  Future<void> _parseMPD(String content, String baseUrl,
      List<String> videoSegs, List<String> audioSegs) async {
    // 提取所有 SegmentURL media 属性
    final videoMatches = RegExp(
      r'<SegmentURL[^>]*media="([^"]+)"',
    ).allMatches(content);
    for (final m in videoMatches) {
      videoSegs.add(_resolveUrl(m.group(1)!, baseUrl));
    }

    // 如果没找到，尝试 SegmentTemplate
    if (videoSegs.isEmpty) {
      final templateMatches = RegExp(
        r'<SegmentTemplate[^>]*media="([^"]+)"[^>]*startNumber="(\d+)"[^>]*/>',
      ).allMatches(content);
      for (final m in templateMatches) {
        var template = m.group(1)!;
        final startNum = int.tryParse(m.group(2) ?? '1') ?? 1;
        for (var i = startNum; i < startNum + 200; i++) {
          videoSegs.add(_resolveUrl(template.replaceAll('\$Number\$', i.toString()), baseUrl));
        }
      }
    }
  }

  String _resolveUrl(String url, String baseUrl) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) {
      final base = Uri.parse(baseUrl);
      return '${base.scheme}://${base.host}$url';
    }
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
