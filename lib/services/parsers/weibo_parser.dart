import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 微博解析器
class WeiboParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.weibo;

  static const String _tag = 'WeiboParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _urlPattern = RegExp(
    r'https?://(?:www\.)?weibo\.com/\d+/(?:[a-zA-Z0-9]+)',
  );
  static final RegExp _tvUrlPattern = RegExp(
    r'https?://(?:www\.)?weibo\.(com|tv)/tv/show/[a-zA-Z0-9]+',
  );
  static final RegExp _shortUrlPattern = RegExp(
    r'https?://t\.cn/[a-zA-Z0-9]+',
  );

  @override
  bool canParse(String url) {
    return _urlPattern.hasMatch(url) ||
        _tvUrlPattern.hasMatch(url) ||
        _shortUrlPattern.hasMatch(url) ||
        url.contains('weibo.com') ||
        url.contains('t.cn');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析微博: $url', name: _tag);

    // 短链接
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
    }

    final html = await _fetchPage(url, cookie: cookie);

    // 尝试多种方法解析
    final patterns = [
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});', dotAll: true),
      RegExp(r'<script[^>]*>window\.\_\_render\_data\s*=\s*({.*?});?</script>',
          dotAll: true),
      RegExp(r'"pageConfig"\s*:\s*({[^}]+})'),
    ];

    for (final pattern in patterns) {
      final m = pattern.firstMatch(html);
      if (m == null) continue;
      try {
        final data = jsonDecode(m.group(1)!);
        final result = _extractVideoInfo(data, url);
        if (result != null) return result;
      } catch (_) {}
    }

    // Fallback: 正则提取
    final videoUrlMatch =
        RegExp(r'"video_url"\s*:\s*"([^"]+)"').firstMatch(html);
    final titleMatch =
        RegExp(r'"title"\s*:\s*"([^"]+)"').firstMatch(html);
    final coverMatch =
        RegExp(r'"cover_image"\s*:\s*"([^"]+)"').firstMatch(html);

    if (videoUrlMatch != null) {
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleMatch?.group(1)?.replaceAll('\\u002F', '/') ?? '微博视频',
        author: '',
        coverUrl: coverMatch?.group(1)?.replaceAll('\\u002F', '/') ?? '',
        videoUrl: videoUrlMatch.group(1)!.replaceAll('\\u002F', '/'),
        sourceUrl: url,
        platform: VideoPlatform.weibo,
      );
    }

    // 兜底：查找任何 .mp4 URL
    final mp4Match = RegExp(r'''https?://[a-zA-Z0-9./_\-%~]+\.mp4[^<>\s"']*''').firstMatch(html);
    if (mp4Match != null) {
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleMatch?.group(1)?.replaceAll('\\u002F', '/') ?? '微博视频',
        author: '',
        coverUrl: coverMatch?.group(1)?.replaceAll('\\u002F', '/') ?? '',
        videoUrl: mp4Match.group(0)!,
        sourceUrl: url,
        platform: VideoPlatform.weibo,
      );
    }

    throw Exception('无法从微博页面中解析出视频信息');
  }

  Future<String> _resolveRedirect(String url) async {
    try {
      final response = await http
          .head(Uri.parse(url), headers: VideoParser.commonHeaders())
          .timeout(_timeout);
      return response.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final response = await http
        .get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie))
        .timeout(_timeout);
    if (response.statusCode == 200) return response.body;
    throw Exception('微博页面请求失败: HTTP ${response.statusCode}');
  }

  VideoInfo? _extractVideoInfo(dynamic data, String sourceUrl) {
    try {
      String? title = '微博视频';
      String? coverUrl;
      String? videoUrl;
      String? author;
      String? noteId;

      void search(dynamic obj, {int depth = 0}) {
        if (depth > 8 || obj == null) return;
        if (obj is Map) {
          if (obj['video_url'] != null) {
            videoUrl ??= obj['video_url'].toString();
          }
          if (obj['title'] != null) title ??= obj['title'].toString();
          if (obj['cover_image'] != null) {
            coverUrl ??= obj['cover_image'].toString();
          }
          if (obj['nickname'] != null) author ??= obj['nickname'].toString();
          if (obj['id'] != null && obj['id'].toString().length > 8) {
            noteId ??= obj['id'].toString();
          }

          for (final val in obj.values) {
            search(val, depth: depth + 1);
          }
        } else if (obj is List) {
          for (final item in obj) {
            search(item, depth: depth + 1);
          }
        }
      }

      search(data);

      if (videoUrl == null || videoUrl!.isEmpty) return null;
      noteId ??= DateTime.now().millisecondsSinceEpoch.toString();

      return VideoInfo(
        noteId: noteId!,
        title: title!,
        author: author ?? '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl!,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.weibo,
      );
    } catch (_) {
      return null;
    }
  }
}
