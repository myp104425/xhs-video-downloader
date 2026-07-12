import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// yt-dlp API 解析器 — 使用公开 Cobalt API
///
/// 调用 yt-dlp 的公开 REST 服务解析任意网页视频。
/// 维护说明：如果 API 失效，替换以下 _endpoints 列表中的 URL 即可。
class YtDlpParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'YtDlpParser';
  static const Duration _timeout = Duration(seconds: 30);

  // 多个公开 API 端点，依次尝试
  static const List<String> _endpoints = [
    'https://cobalt.tools/api/json',
    'https://api.cobalt.tools/',
  ];

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('yt-dlp API 解析: $url', name: _tag);

    final errors = <String>[];

    for (final endpoint in _endpoints) {
      try {
        return await _tryEndpoint(endpoint, url);
      } catch (e) {
        errors.add('$endpoint: $e');
        developer.log('端点 $endpoint 失败: $e', name: _tag);
      }
    }

    throw Exception('解析失败\n'
        '已尝试以下 API 端点均未成功：\n'
        '${errors.map((e) => '• $e').join('\n')}\n\n'
        '请稍后重试，或检查链接是否有效');
  }

  Future<VideoInfo> _tryEndpoint(String endpoint, String url) async {
    final resp = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({
        'url': url,
        'vCodec': 'h264',
        'vQuality': '1080',
        'aFormat': 'mp3',
        'isAudioOnly': false,
        'isNoTTWatermark': true,
      }),
    ).timeout(_timeout);

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map;

      // Cobalt v2 响应格式
      if (data['status'] == 'success' || data['status'] == 'stream') {
        final videoUrl = data['url']?.toString() ?? data['stream']?.toString() ?? '';
        final title = data['filename']?.toString() ?? data['title']?.toString() ?? '';
        if (videoUrl.isNotEmpty) {
          return VideoInfo(
            noteId: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            author: '',
            coverUrl: '',
            videoUrl: videoUrl,
            sourceUrl: url,
            platform: VideoPlatform.unknown,
          );
        }
      }

      // Cobalt v1 响应格式（兼容）
      if (data['text'] != null) {
        final videoUrl = data['text'].toString();
        if (videoUrl.startsWith('http')) {
          return VideoInfo(
            noteId: DateTime.now().millisecondsSinceEpoch.toString(),
            title: data['filename']?.toString() ?? '',
            author: '',
            coverUrl: '',
            videoUrl: videoUrl,
            sourceUrl: url,
            platform: VideoPlatform.unknown,
          );
        }
      }
    }
    throw Exception('HTTP ${resp.statusCode}');
  }
}
