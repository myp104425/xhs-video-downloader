import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 抖音 / TikTok 解析器
///
/// 解析思路（借鉴 Video Download Helper）：
/// 1. 用桌面端 UA 请求页面，获取 HTML
/// 2. 从 SSR 数据中提取 aweme_id 和视频信息
/// 3. 使用抖音 web API 获取视频直链
/// 4. 兜底策略：从页面正则提取视频地址
class DouyinParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.douyin;

  static const String _tag = 'DouyinParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _shortUrlPattern = RegExp(
    r'https?://v\.douyin\.com/[a-zA-Z0-9]+',
  );

  @override
  bool canParse(String url) {
    return _shortUrlPattern.hasMatch(url) ||
        url.contains('douyin.com') ||
        url.contains('iesdouyin.com');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析抖音: $url', name: _tag);

    // 短链接先重定向获取真实 URL
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
      developer.log('短链接解析后: $url', name: _tag);
    }

    // 从 URL 中提取 aweme_id
    final awemeId = _extractAwemeId(url);

    // 方法1: 使用抖音 Web API 获取视频信息
    if (awemeId != null) {
      try {
        return await _parseViaApi(awemeId, url, cookie: cookie);
      } catch (e) {
        developer.log('抖音 API 解析失败: $e', name: _tag);
      }
    }

    // 方法2: 从页面 HTML 解析
    final html = await _fetchPage(url, cookie: cookie);
    final videoInfo = _parseFromHtml(html, url);
    if (videoInfo != null) {
      developer.log('抖音页面解析成功: ${videoInfo.title}', name: _tag);
      return videoInfo;
    }

    throw Exception('无法从抖音页面中解析出视频信息\n'
        '原因：页面结构可能已更新，请尝试复制最新的分享链接');
  }

  /// 获取跳转后的真实 URL
  Future<String> _resolveRedirect(String url) async {
    try {
      final response = await http.head(Uri.parse(url), headers: VideoParser.commonHeaders()).timeout(_timeout);
      return response.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }

  /// 从 URL 提取 aweme_id
  String? _extractAwemeId(String url) {
    // /video/738204729374 (数字 ID)
    final videoIdMatch = RegExp(r'/video/(\d+)').firstMatch(url);
    if (videoIdMatch != null) return videoIdMatch.group(1);

    // 从路径最后一段取数字
    final segments = Uri.tryParse(url)?.pathSegments ?? [];
    for (final seg in segments.reversed) {
      if (RegExp(r'^\d+$').hasMatch(seg)) return seg;
    }
    return null;
  }

  /// 通过抖音 Web API 解析
  Future<VideoInfo> _parseViaApi(String awemeId, String sourceUrl, {String? cookie}) async {
    developer.log('尝试抖音 API 解析: aweme_id=$awemeId', name: _tag);

    // 方式A: 直接用 aweme/v1/web/aweme/detail/ API
    final apiUrl = 'https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id=$awemeId';
    final response = await http
        .get(Uri.parse(apiUrl), headers: VideoParser.commonHeaders(cookie: cookie, referer: 'https://www.douyin.com'))
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('API 请求失败: HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final awemeDetail = data['aweme_detail'] as Map?;
    if (awemeDetail == null) {
      throw Exception('API 返回数据异常');
    }

    // 提取基本信息
    final desc = awemeDetail['desc']?.toString() ?? '';
    final author = awemeDetail['author']?['nickname']?.toString() ?? '';
    final authorAvatar = awemeDetail['author']?['avatar_thumb']?['url_list']?.first?.toString() ?? '';

    // 提取封面
    final coverUrl = awemeDetail['video']?['cover']?['url_list']?.first?.toString() ?? '';

    // 提取视频直链 - 优先无水印
    String videoUrl = '';
    final video = awemeDetail['video'] as Map?;
    if (video != null) {
      final playAddr = video['play_addr'] as Map?;
      if (playAddr != null) {
        final uriList = playAddr['uri_list'] ?? playAddr['url_list'];
        if (uriList is List && uriList.isNotEmpty) {
          // 优先取无水印的 uri
          for (final uri in uriList) {
            final urlStr = uri.toString();
            if (!urlStr.contains('watermark')) {
              videoUrl = urlStr;
              break;
            }
          }
          if (videoUrl.isEmpty) {
            videoUrl = uriList.first.toString();
          }
        }
      }
    }

    // 构建完整的视频 URL（抖音 CDN 需要添加 scheme）
    if (videoUrl.isNotEmpty && videoUrl.startsWith('//')) {
      videoUrl = 'https:$videoUrl';
    }

    // 时长
    final duration = (video?['duration'] as int? ?? 0) ~/ 1000;

    return VideoInfo(
      noteId: awemeId,
      title: desc,
      author: author,
      authorAvatar: authorAvatar,
      coverUrl: coverUrl,
      videoUrl: videoUrl,
      sourceUrl: sourceUrl,
      duration: duration,
      resolution: '1080p',
      platform: VideoPlatform.douyin,
    );
  }

  /// 获取页面 HTML
  Future<String> _fetchPage(String url, {String? cookie}) async {
    final response = await http
        .get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie))
        .timeout(_timeout);
    if (response.statusCode == 200) return response.body;
    throw Exception('抖音页面请求失败: HTTP ${response.statusCode}');
  }

  /// 从页面 HTML 解析
  VideoInfo? _parseFromHtml(String html, String sourceUrl) {
    try {
      // 方法1: 尝试提取 SSR 数据中的 video_id
      final patterns = [
        RegExp(r'<script[^>]*id="RENDER_DATA"[^>]*>(.*?)</script>', dotAll: true),
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});', dotAll: true),
      ];

      for (final pattern in patterns) {
        final m = pattern.firstMatch(html);
        if (m == null) continue;

        String raw = m.group(1)!;
        if (raw.contains('%') || raw.contains('\\u')) {
          try {
            raw = Uri.decodeComponent(raw);
          } catch (_) {
            raw = raw
                .replaceAll('\\u003C', '<')
                .replaceAll('\\u003E', '>')
                .replaceAll('\\u0026', '&')
                .replaceAll('\\u0027', "'")
                .replaceAll('\\"', '"')
                .replaceAll('\\n', '\n')
                .replaceAll('\\t', '\t');
          }
        }

        final data = jsonDecode(raw);
        final result = _extractVideoInfo(data, sourceUrl);
        if (result != null && result.videoUrl.isNotEmpty) return result;
      }

      // 方法2: 从页面文本中正则提取视频地址
      final urlMatches = RegExp(
        r'https?://[a-zA-Z0-9\./-]+\.(?:mp4|m3u8)[^"\']*',
      ).allMatches(html);
      if (urlMatches.isNotEmpty) {
        final noteId = DateTime.now().millisecondsSinceEpoch.toString();
        return VideoInfo(
          noteId: noteId,
          title: '抖音视频',
          videoUrl: urlMatches.first.group(0)!,
          sourceUrl: sourceUrl,
          platform: VideoPlatform.douyin,
        );
      }

      return null;
    } catch (e) {
      developer.log('抖音页面解析异常: $e', name: _tag);
      return null;
    }
  }

  /// 递归提取视频信息
  VideoInfo? _extractVideoInfo(dynamic data, String sourceUrl) {
    try {
      String? title;
      String? coverUrl;
      String? videoUrl;
      String? author;
      String? noteId;
      int duration = 0;

      void search(dynamic obj, {int depth = 0}) {
        if (depth > 10 || obj == null) return;
        if (obj is Map) {
          // 检测视频 URL
          if (obj['src'] is String && (obj['src'] as String).contains('.mp4')) {
            videoUrl ??= obj['src'].toString();
          }
          // play_addr
          if (obj['play_addr'] is Map) {
            final addr = obj['play_addr'] as Map;
            final list = addr['url_list'] ?? addr['uri_list'];
            if (list is List && list.isNotEmpty) {
              var url = list.first.toString();
              if (url.startsWith('//')) url = 'https:$url';
              videoUrl ??= url;
            }
          }
          // video_id
          if (obj['aweme_id'] != null) noteId ??= obj['aweme_id'].toString();
          if (obj['video_id'] != null) noteId ??= obj['video_id'].toString();
          // title/desc
          title ??= obj['desc']?.toString() ?? obj['title']?.toString();
          // author
          author ??= obj['author']?['nickname']?.toString() ?? obj['nickname']?.toString();
          // cover
          if (obj['cover_urls'] is List) {
            coverUrl ??= (obj['cover_urls'] as List).first?.toString();
          }
          if (obj['cover'] is Map) {
            final list = obj['cover']['url_list'];
            if (list is List && list.isNotEmpty) coverUrl ??= list.first.toString();
          }
          // duration
          if (obj['duration'] is int) duration = obj['duration'] ~/ 1000;

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
        title: title ?? '抖音视频',
        author: author ?? '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl!,
        sourceUrl: sourceUrl,
        duration: duration,
        platform: VideoPlatform.douyin,
      );
    } catch (e) {
      developer.log('抖音数据提取失败: $e', name: _tag);
      return null;
    }
  }
}
