import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 快手解析器
class KuaishouParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.kuaishou;

  static const String _tag = 'KuaishouParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _urlPattern = RegExp(
    r'https?://(?:www\.)?kuaishou\.com/(?:short-video|photo|live)/[a-zA-Z0-9]+',
  );
  static final RegExp _shortUrlPattern = RegExp(
    r'https?://(?:v\.)?kuaishou\.com/[a-zA-Z0-9]+',
  );

  @override
  bool canParse(String url) {
    return _urlPattern.hasMatch(url) ||
        _shortUrlPattern.hasMatch(url) ||
        url.contains('kuaishou.com') ||
        url.contains('kwai.com');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析快手: $url', name: _tag);

    final html = await _fetchPage(url, cookie: cookie);
    final videoInfo = _parseFromHtml(html, url);
    if (videoInfo == null) {
      throw Exception('无法从快手页面中解析出视频信息');
    }

    developer.log('快手解析成功: ${videoInfo.title}', name: _tag);
    return videoInfo;
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final response = await http
        .get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie))
        .timeout(_timeout);
    if (response.statusCode == 200) return response.body;
    throw Exception('快手页面请求失败: HTTP ${response.statusCode}');
  }

  VideoInfo? _parseFromHtml(String html, String sourceUrl) {
    try {
      // 尝试多种数据嵌入模式
      final patterns = [
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});', dotAll: true),
        RegExp(r'<script[^>]*>window\.__NUXT__\s*=\s*({.*?});?</script>',
            dotAll: true),
        RegExp(r'window\.__APOLLO_STATE__\s*=\s*({.*?});', dotAll: true),
      ];

      for (final pattern in patterns) {
        final m = pattern.firstMatch(html);
        if (m == null) continue;
        final data = jsonDecode(m.group(1)!);
        final result = _extractVideoInfo(data, sourceUrl);
        if (result != null) return result;
      }

      // Fallback: 正则提取
      final photoIdRegExp = RegExp(r'"photoId"\s*:\s*"([^"]+)"');
      final photoMatch = photoIdRegExp.firstMatch(html);
      final titleRegExp = RegExp(r'"caption"\s*:\s*"([^"]+)"');
      final titleMatch = titleRegExp.firstMatch(html);
      final coverRegExp = RegExp(r'"coverUrl"\s*:\s*"([^"]+)"');
      final coverMatch = coverRegExp.firstMatch(html);

      // 尝试提取视频 URL
      final urlRegExp = RegExp(r'"srcNoMark"\s*:\s*"([^"]+)"');
      final urlMatch = urlRegExp.firstMatch(html);

      if (urlMatch != null || photoMatch != null) {
        return VideoInfo(
          noteId: photoMatch?.group(1) ?? '',
          title: titleMatch?.group(1)?.replaceAll('\\u002F', '/') ?? '快手视频',
          author: '',
          coverUrl: coverMatch?.group(1) ?? '',
          videoUrl: urlMatch?.group(1)?.replaceAll('\\u002F', '/') ?? '',
          sourceUrl: sourceUrl,
          platform: VideoPlatform.kuaishou,
        );
      }

      return null;
    } catch (e) {
      developer.log('快手解析异常: $e', name: _tag);
      return null;
    }
  }

  VideoInfo? _extractVideoInfo(dynamic data, String sourceUrl) {
    try {
      String? title = '快手视频';
      String? coverUrl;
      String? videoUrl;
      String? author;
      String? noteId;

      void search(dynamic obj, {int depth = 0}) {
        if (depth > 8 || obj == null) return;
        if (obj is Map) {
          if (obj['photoId'] != null) noteId ??= obj['photoId'].toString();
          if (obj['caption'] != null) title ??= obj['caption'].toString();
          if (obj['coverUrl'] != null) coverUrl ??= obj['coverUrl'].toString();
          if (obj['srcNoMark'] != null) {
            videoUrl ??= obj['srcNoMark'].toString();
          }
          if (obj['user'] is Map) {
            author ??= (obj['user'] as Map)['name']?.toString();
          }
          if (obj['author'] is Map) {
            author ??= (obj['author'] as Map)['name']?.toString();
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
      if (noteId == null) noteId = DateTime.now().millisecondsSinceEpoch.toString();

      return VideoInfo(
        noteId: noteId!,
        title: title!,
        author: author ?? '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl!,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.kuaishou,
      );
    } catch (_) {
      return null;
    }
  }
}
