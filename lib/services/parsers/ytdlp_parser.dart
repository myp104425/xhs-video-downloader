import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// yt-dlp API 兜底解析器
/// 当平台专用解析器失败时，使用公开 REST API 尝试解析
class YtDlpParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'YtDlpParser';
  static const Duration _timeout = Duration(seconds: 30);

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('yt-dlp API 解析: $url', name: _tag);
    return await _parseViaApi(url);
  }

  Future<VideoInfo> _parseViaApi(String url) async {
    final resp = await http.post(
      Uri.parse('https://cobalt-api.deno.dev/'),
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
    }
    throw Exception('API 返回异常，请稍后重试');
  }
}
