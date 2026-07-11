import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// yt-dlp API 兜底解析器
///
/// 当平台专用解析器失败时，使用 yt-dlp 的公开 REST API 进行解析。
/// yt-dlp 支持 1000+ 网站，包括小红书/抖音/B站等。
class YtDlpParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'YtDlpParser';
  static const Duration _timeout = Duration(seconds: 30);

  // yt-dlp API 端点（自托管或公开服务）
  // 默认使用 cobalt.tools API（基于 yt-dlp，免费）
  static const String _apiEndpoint = 'https://cobalt-api.deno.dev';

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('尝试 yt-dlp API 解析: $url', name: _tag);

    // 方法1: Cobalt API
    try {
      return await _parseViaCobalt(url);
    } catch (e) {
      developer.log('Cobalt API 失败: $e', name: _tag);
    }

    // 方法2: yt-dlp REST API (通用接口)
    try {
      return await _parseViaYtDlpApi(url);
    } catch (e) {
      developer.log('yt-dlp API 失败: $e', name: _tag);
    }

    throw Exception('所有解析方式均失败，请确认链接有效');
  }

  /// Cobalt API (cobalt.tools 的公开 API)
  Future<VideoInfo> _parseViaCobalt(String url) async {
    try {
      final resp = await http.post(
        Uri.parse('$_apiEndpoint/'),
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
        if (data['status'] == 'success' || data['status'] == 'stream') {
          final videoUrl = data['url']?.toString() ?? data['stream']?.toString() ?? '';
          final title = data['filename']?.toString() ?? data['title']?.toString() ?? '';

          if (videoUrl.isNotEmpty) {
            developer.log('Cobalt 解析成功: $title', name: _tag);
            return VideoInfo(
              noteId: DateTime.now().millisecondsSinceEpoch.toString(),
              title: title,
              author: '',
              videoUrl: videoUrl,
              sourceUrl: url,
              platform: VideoPlatform.unknown,
            );
          }
        }
      }
      throw Exception('Cobalt API 返回异常');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Cobalt 请求失败: $e');
    }
  }

  /// yt-dlp REST API (通用接口)
  Future<VideoInfo> _parseViaYtDlpApi(String url) async {
    // 尝试不同的 yt-dlp API 接口
    final endpoints = [
      'https://yt-dlp-api.vercel.app/api/info?url=$url',
    ];

    for (final endpoint in endpoints) {
      try {
        final resp = await http.get(
          Uri.parse(endpoint),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 15));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final videoUrl = data['url']?.toString() ??
              data['download_url']?.toString() ??
              data['webpage_url']?.toString() ??
              '';
          final title = data['title']?.toString() ?? '';

          if (videoUrl.isNotEmpty) {
            return VideoInfo(
              noteId: data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
              title: title,
              author: data['uploader']?.toString() ?? '',
              coverUrl: data['thumbnail']?.toString() ?? '',
              videoUrl: videoUrl,
              sourceUrl: url,
              platform: VideoPlatform.unknown,
            );
          }
        }
      } catch (_) {}
    }
    throw Exception('yt-dlp API 均不可用');
  }
}
