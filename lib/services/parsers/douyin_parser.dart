import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 抖音 / TikTok 解析器
///
/// 解析思路：
/// 1. 桌面端 UA 请求页面
/// 2. 提取页面中嵌入式 JSON 数据
/// 3. 解析视频直链
class DouyinParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.douyin;

  static const String _tag = 'DouyinParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _urlPattern = RegExp(
    r'https?://(?:www\.)?(?:douyin\.com|iesdouyin\.com|t\.cn)/[a-zA-Z0-9_/?=&%-]+',
  );
  static final RegExp _shortUrlPattern = RegExp(
    r'https?://v\.douyin\.com/[a-zA-Z0-9]+',
  );

  @override
  bool canParse(String url) {
    return _urlPattern.hasMatch(url) ||
        _shortUrlPattern.hasMatch(url) ||
        url.contains('douyin.com') ||
        url.contains('iesdouyin.com');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析抖音: $url', name: _tag);

    // 短链接先重定向
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
    }

    final html = await _fetchPage(url, cookie: cookie);
    final videoInfo = _parseFromHtml(html, url);
    if (videoInfo == null) {
      throw Exception('无法从抖音页面中解析出视频信息');
    }

    developer.log('抖音解析成功: ${videoInfo.title}', name: _tag);
    return videoInfo;
  }

  Future<String> _resolveRedirect(String url) async {
    try {
      final response = await http
          .head(Uri.parse(url), headers: commonHeaders())
          .timeout(_timeout);
      return response.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final response = await http
        .get(Uri.parse(url), headers: commonHeaders(cookie: cookie))
        .timeout(_timeout);
    if (response.statusCode == 200) return response.body;
    throw Exception('抖音页面请求失败: HTTP ${response.statusCode}');
  }

  VideoInfo? _parseFromHtml(String html, String sourceUrl) {
    try {
      // 方法1: 尝试提取 SSR 数据
      // 抖音页面通常有 <script id="RENDER_DATA"> 或 __INITIAL_STATE__
      final patterns = [
        RegExp(r'<script[^>]*id="RENDER_DATA"[^>]*>(.*?)</script>',
            dotAll: true),
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});', dotAll: true),
        RegExp(r'<script[^>]*>window\._SSR_HYDRAT_DATA\s*=\s*({.*?})</script>',
            dotAll: true),
      ];

      for (final pattern in patterns) {
        final m = pattern.firstMatch(html);
        if (m == null) continue;

        String raw = m.group(1)!;
        // RENDER_DATA 可能是 URL-encoded
        if (raw.contains('%') || raw.contains('\\u')) {
          try {
            raw = Uri.decodeComponent(raw);
          } catch (_) {
            try {
              raw = raw
                  .replaceAll('\\u003C', '<')
                  .replaceAll('\\u003E', '>')
                  .replaceAll('\\u0026', '&')
                  .replaceAll('\\u0027', "'")
                  .replaceAll('\\"', '"')
                  .replaceAll('\\n', '\n')
                  .replaceAll('\\t', '\t');
            } catch (_) {}
          }
        }

        final data = jsonDecode(raw);
        return _extractVideoInfo(data, sourceUrl);
      }

      // 方法2: 从页面 JSON-LD 提取
      final ldPattern = RegExp(
          r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>',
          dotAll: true,
          caseSensitive: false);
      final ldMatch = ldPattern.firstMatch(html);

      // 方法3: 正则提取 video_id 然后构造 API
      final vidPattern =
          RegExp(r'video_id["\']?\s*[:=]\s*["\']([a-zA-Z0-9_-]+)["\']');
      final vidMatch = vidPattern.firstMatch(html);
      if (vidMatch != null) {
        final videoId = vidMatch.group(1)!;
        return VideoInfo(
          noteId: videoId,
          title: '抖音视频',
          videoUrl: 'https://www.douyin.com/video/$videoId',
          sourceUrl: sourceUrl,
          platform: VideoPlatform.douyin,
        );
      }

      return null;
    } catch (e) {
      developer.log('抖音解析异常: $e', name: _tag);
      return null;
    }
  }

  VideoInfo? _extractVideoInfo(dynamic data, String sourceUrl) {
    try {
      // 遍历查找 video 相关的数据结构
      String? title = '抖音视频';
      String? coverUrl;
      String? videoUrl;
      String? author;
      String? noteId;
      int duration = 0;

      // 递归搜索视频数据
      void search(dynamic obj, {int depth = 0}) {
        if (depth > 8 || obj == null) return;
        if (obj is Map) {
          // 检测视频相关字段
          if (obj['video'] is Map) {
            final v = obj['video'] as Map;
            videoUrl ??= v['play_addr']?['url_list']?.firstOrNull?.toString();
            videoUrl ??= v['playApi']?.toString();
            coverUrl ??= v['cover']?['url_list']?.firstOrNull?.toString() ??
                v['dynamic_cover']?['url_list']?.firstOrNull?.toString();
            duration = v['duration'] as int? ?? 0;
          }
          if (obj['video_id'] != null && noteId == null) {
            noteId = obj['video_id'].toString();
          }
          title ??= obj['desc']?.toString() ??
              obj['title']?.toString() ??
              obj['share_title']?.toString();
          author ??= obj['author']?['nickname']?.toString() ??
              obj['nickname']?.toString();

          if (obj['cover_url'] is List) {
            coverUrl ??= (obj['cover_url'] as List).firstOrNull?.toString();
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

      if (noteId == null) noteId = DateTime.now().millisecondsSinceEpoch.toString();

      return VideoInfo(
        noteId: noteId,
        title: title ?? '抖音视频',
        author: author ?? '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl ?? '',
        sourceUrl: sourceUrl,
        duration: duration,
        likes: 0,
        platform: VideoPlatform.douyin,
      );
    } catch (e) {
      developer.log('抖音数据提取失败: $e', name: _tag);
      return null;
    }
  }
}
