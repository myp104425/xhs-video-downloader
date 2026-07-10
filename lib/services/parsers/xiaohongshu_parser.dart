import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 小红书解析器
///
/// 解析思路（借鉴 Video Download Helper）：
/// 1. 用桌面端 UA 请求页面（避免手机端弹 App 跳转）
/// 2. 提取 __INITIAL_STATE__ 中的嵌入式 JSON 数据
/// 3. 提取视频直链（最高画质）
/// 4. 回退策略：JSON-LD → Meta 标签
class XiaohongshuParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.xiaohongshu;

  static const String _tag = 'XiaohongshuParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _noteUrlPattern = RegExp(
    r'https?://(?:www\.)?xiaohongshu\.com/(?:explore|discovery/item|user)/[a-zA-Z0-9]+',
  );
  static final RegExp _shortUrlPattern = RegExp(
    r'https?://xhslink\.com/[a-zA-Z0-9]+',
  );

  @override
  bool canParse(String url) {
    return _noteUrlPattern.hasMatch(url) || _shortUrlPattern.hasMatch(url);
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析小红书: $url', name: _tag);

    // 短链接解析
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveShortUrl(url);
      developer.log('短链接解析后: $url', name: _tag);
    }

    final noteId = _extractNoteId(url);
    if (noteId == null || noteId.isEmpty) {
      throw Exception('无法从小红书链接中提取笔记ID');
    }

    final html = await _fetchPage(url, cookie: cookie);
    final videoInfo = _parseVideoFromHtml(html, noteId, url);
    if (videoInfo == null) {
      throw Exception('无法从小红书页面中解析出视频信息\n'
          '可能的原因：该笔记不包含视频 / 页面结构已更新 / 需要登录 Cookie');
    }

    developer.log('小红书解析成功: ${videoInfo.title}', name: _tag);
    return videoInfo;
  }

  /// 解析短链接
  Future<String> _resolveShortUrl(String shortUrl) async {
    try {
      final response = await http
          .get(Uri.parse(shortUrl), headers: VideoParser.commonHeaders())
          .timeout(_timeout);
      return response.request?.url.toString() ?? shortUrl;
    } catch (e) {
      return shortUrl;
    }
  }

  /// 提取笔记 ID
  String? _extractNoteId(String url) {
    final segments = Uri.parse(url).pathSegments;
    return segments.isNotEmpty ? segments.last : null;
  }

  /// 获取页面 HTML（桌面端 UA）
  Future<String> _fetchPage(String url, {String? cookie}) async {
    final response = await http
        .get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie))
        .timeout(_timeout);

    if (response.statusCode == 200) return response.body;
    throw Exception('页面请求失败: HTTP ${response.statusCode}');
  }

  /// 从 HTML 解析视频信息
  VideoInfo? _parseVideoFromHtml(String html, String noteId, String sourceUrl) {
    // 方法1: __INITIAL_STATE__
    final result = _parseFromInitialState(html, noteId, sourceUrl);
    if (result != null) return result;

    // 方法2: JSON-LD
    final result2 = _parseFromJsonLd(html, noteId, sourceUrl);
    if (result2 != null) return result2;

    // 方法3: Meta
    return _parseFromMeta(html, noteId, sourceUrl);
  }

  VideoInfo? _parseFromInitialState(String html, String noteId, String sourceUrl) {
    try {
      final patterns = [
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});\s*</script>',
            dotAll: true),
        RegExp(r'__INITIAL_STATE__\s*=\s*({.*?});?\s*</script>', dotAll: true),
      ];

      String? jsonStr;
      for (final p in patterns) {
        final m = p.firstMatch(html);
        if (m != null) {
          jsonStr = m.group(1);
          break;
        }
      }
      if (jsonStr == null) return null;

      jsonStr = jsonStr
          .replaceAll('undefined', 'null')
          .replaceAll('\\\n', '')
          .replaceAll('\\\r', '');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      Map<String, dynamic>? noteData;

      // 路径1: note -> noteDetailMap
      final note = data['note'];
      if (note is Map) {
        final detailMap = note['noteDetailMap'];
        if (detailMap is Map) {
          noteData = detailMap[noteId] ?? detailMap.values.firstOrNull;
        }
      }

      // 路径2: 直接 noteDetailMap
      if (noteData == null) {
        final detailMap = data['noteDetailMap'];
        if (detailMap is Map) {
          noteData = detailMap[noteId] ?? detailMap.values.firstOrNull;
        }
      }

      if (noteData == null) return null;
      final noteCard = noteData['noteCard'] as Map<String, dynamic>?;
      if (noteCard == null) return null;

      final info = _extractNoteInfo(noteCard);

      // 取最高画质视频 URL
      String? videoUrl;
      final video = noteCard['video'] as Map?;
      if (video != null) {
        final media = video['media'] as Map?;
        if (media != null) {
          final stream = media['stream'] as Map?;
          if (stream != null) {
            final h264 = stream['h264'] as List?;
            if (h264 != null && h264.isNotEmpty) {
              final last = h264.last as Map;
              videoUrl = last['master_url']?.toString() ??
                  last['url']?.toString();
            }
          }
        }
      }

      videoUrl ??= noteCard['video_url']?.toString();
      if (videoUrl == null || videoUrl.isEmpty) return null;

      return VideoInfo(
        noteId: noteId,
        title: info['title'] ?? '',
        author: info['author'] ?? '',
        authorAvatar: info['authorAvatar'] ?? '',
        coverUrl: info['coverUrl'] ?? '',
        videoUrl: videoUrl,
        sourceUrl: sourceUrl,
        duration: info['duration'] ?? 0,
        resolution: info['resolution'] ?? '1080p',
        fileSize: info['fileSize'] ?? 0,
        likes: info['likes'] ?? 0,
        description: info['description'] ?? '',
        platform: VideoPlatform.xiaohongshu,
      );
    } catch (e) {
      developer.log('__INITIAL_STATE__ 解析失败: $e', name: _tag);
      return null;
    }
  }

  Map<String, dynamic> _extractNoteInfo(Map<String, dynamic> card) {
    final info = <String, dynamic>{};
    try {
      info['title'] = card['title']?.toString().trim() ?? '';

      final user = card['user'] as Map?;
      if (user != null) {
        info['author'] = user['nickname']?.toString() ?? '';
        info['authorAvatar'] = user['avatar']?.toString() ?? '';
      }

      final imageList = card['imageList'] as List?;
      if (imageList != null && imageList.isNotEmpty) {
        final first = imageList[0] as Map?;
        if (first != null) {
          info['coverUrl'] = first['urlDefault']?.toString() ??
              first['url']?.toString() ??
              '';
          if ((info['coverUrl'] as String).contains('~')) {
            info['coverUrl'] = (info['coverUrl'] as String).split('~')[0];
          }
        }
      }

      final video = card['video'] as Map?;
      if (video != null) {
        info['duration'] = video['duration'] as int? ?? 0;
        info['resolution'] = '1080p';
        final media = video['media'] as Map?;
        if (media != null) {
          final stream = media['stream'] as Map?;
          if (stream != null) {
            final h264 = stream['h264'] as List?;
            if (h264 != null && h264.isNotEmpty) {
              final last = h264.last as Map;
              info['fileSize'] = last['size'] as int? ?? 0;
              info['resolution'] =
                  last['quality']?.toString() ?? '1080p';
            }
          }
        }
      }

      final interactInfo = card['interactInfo'] as Map?;
      if (interactInfo != null) {
        info['likes'] = interactInfo['likedCount'] as int? ??
            interactInfo['likeCount'] as int? ??
            0;
      }

      info['description'] = card['desc']?.toString().trim() ?? '';
    } catch (_) {}
    return info;
  }

  VideoInfo? _parseFromJsonLd(String html, String noteId, String sourceUrl) {
    try {
      final pattern = RegExp(
          r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>',
          dotAll: true,
          caseSensitive: false);
      final m = pattern.firstMatch(html);
      if (m == null) return null;

      final data = jsonDecode(m.group(1)!.trim());
      String? title, coverUrl, videoUrl;

      void extract(Map d) {
        if (d['@type'] == 'VideoObject') {
          title ??= d['name']?.toString();
          coverUrl ??= d['thumbnailUrl']?.toString();
          videoUrl ??= d['contentUrl']?.toString();
        }
      }

      if (data is List) {
        for (final item in data) {
          if (item is Map) extract(item);
        }
      } else if (data is Map) {
        extract(data);
      }

      if (videoUrl == null) return null;
      return VideoInfo(
        noteId: noteId,
        title: title ?? '',
        author: '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl!,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.xiaohongshu,
      );
    } catch (_) {
      return null;
    }
  }

  VideoInfo? _parseFromMeta(String html, String noteId, String sourceUrl) {
    try {
      String? title, coverUrl, videoUrl;

      final titleMatch = RegExp(
        r'<meta[^>]*property="og:title"[^>]*content="([^"]*)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (titleMatch != null) title = titleMatch.group(1);

      final coverMatch = RegExp(
        r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (coverMatch != null) coverUrl = coverMatch.group(1);

      final videoMatch = RegExp(
        r'<meta[^>]*property="og:video"[^>]*content="([^"]*)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (videoMatch != null) videoUrl = videoMatch.group(1);

      if (videoUrl == null) return null;

      return VideoInfo(
        noteId: noteId,
        title: title ?? '',
        author: '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl!,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.xiaohongshu,
      );
    } catch (_) {
      return null;
    }
  }
}
