import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 抖音 / TikTok 解析器
/// 从页面 SSR 数据提取视频信息 + MP4 URL 正则兜底
class DouyinParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.douyin;

  static const String _tag = 'DouyinParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _shortUrlPattern = RegExp(r'https?://v\.douyin\.com/[a-zA-Z0-9]+');

  @override
  bool canParse(String url) {
    return _shortUrlPattern.hasMatch(url) || url.contains('douyin.com') || url.contains('iesdouyin.com');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析抖音: $url', name: _tag);

    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
      developer.log('重定向后: $url', name: _tag);
    }

    final html = await _fetchPage(url, cookie: cookie);
    final result = _parseFromSSR(html, url);
    if (result != null) return result;

    final regexResult = _parseFromRegex(html, url);
    if (regexResult != null) return regexResult;

    throw Exception('无法解析抖音视频\n请用 App 复制 https://v.douyin.com/ 开头的分享链接');
  }

  Future<String> _resolveRedirect(String url) async {
    try {
      final resp = await http.head(Uri.parse(url), headers: VideoParser.commonHeaders()).timeout(_timeout);
      final redirectUrl = resp.request?.url.toString() ?? url;
      return redirectUrl.contains('douyin.com') ? redirectUrl : url;
    } catch (_) { return url; }
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final resp = await http.get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie)).timeout(_timeout);
    if (resp.statusCode == 200) return resp.body;
    throw Exception('页面请求失败: HTTP ${resp.statusCode}');
  }

  VideoInfo? _parseFromSSR(String html, String sourceUrl) {
    try {
      // SSR 数据可能在 window.__INITIAL_STATE__ 或其他 script 标签中
      final patterns = [
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});\s*<', dotAll: true),
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*JSON\.parse\("([^"]+)"', dotAll: true),
        RegExp(r'<script\s+id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true),
      ];

      Map<String, dynamic>? data;
      for (final p in patterns) {
        final m = p.firstMatch(html);
        if (m == null) continue;
        String raw = m.group(1)!;
        if (raw.contains('&quot;')) raw = raw.replaceAll('&quot;', '"');
        try { data = jsonDecode(raw) as Map<String, dynamic>; break; }
        catch (_) {
          try { data = jsonDecode(raw.replaceAll('\\"', '"').replaceAll('\\n', '')) as Map<String, dynamic>; break; }
          catch (_) {}
        }
      }
      if (data == null) return null;

      return _extractFromData(data, sourceUrl);
    } catch (e) { developer.log('SSR异常: $e', name: _tag); return null; }
  }

  VideoInfo? _extractFromData(dynamic data, String sourceUrl) {
    String? title, author, coverUrl, videoUrl, noteId;
    int duration = 0;

    void search(dynamic obj, {int depth = 0}) {
      if (depth > 10 || obj == null || videoUrl != null) return;
      if (obj is Map) {
        // play_addr → url_list
        if (obj.containsKey('play_addr') && obj['play_addr'] is Map) {
          final addr = obj['play_addr'] as Map;
          final list = addr['url_list'] ?? addr['uri_list'];
          if (list is List && list.isNotEmpty) {
            for (final u in list) {
              final s = u.toString();
              if (s.contains('https://') && !s.contains('watermark')) { videoUrl = s; break; }
            }
            videoUrl ??= list.first.toString();
          }
          // uri 构造
          if ((videoUrl == null || videoUrl!.isEmpty) && addr['uri'] != null) {
            videoUrl = 'https://aweme.snssdk.com/aweme/v1/play/?video_id=${addr['uri']}&line=0';
          }
        }
        // video_id
        if (obj['video_id'] is String) noteId ??= obj['video_id'];
        if (obj['aweme_id'] is String) noteId ??= obj['aweme_id'];
        if (obj['item_id'] is String) noteId ??= obj['item_id'];
        // 标题
        if (obj['desc'] is String) title ??= obj['desc'];
        if (obj['title'] is String) title ??= obj['title'];
        // 作者
        if (obj['author'] is Map) author ??= (obj['author'] as Map)['nickname']?.toString();
        if (obj['nickname'] is String) author ??= obj['nickname'] as String;
        // 封面
        if (obj['cover'] is Map) {
          final cl = (obj['cover'] as Map)['url_list'];
          if (cl is List && cl.isNotEmpty) coverUrl ??= cl.first.toString();
        }
        // 时长
        if (obj['duration'] is int) duration = (obj['duration'] as int) ~/ 1000;

        for (final v in obj.values) { search(v, depth: depth + 1); }
      } else if (obj is List) {
        for (final item in obj) { search(item, depth: depth + 1); }
      }
    }

    search(data);
    if (videoUrl == null || videoUrl!.isEmpty) return null;

    return VideoInfo(
      noteId: noteId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ?? '抖音视频',
      author: author ?? '',
      coverUrl: coverUrl ?? '',
      videoUrl: videoUrl!,
      sourceUrl: sourceUrl,
      duration: duration,
      platform: VideoPlatform.douyin,
    );
  }

  VideoInfo? _parseFromRegex(String html, String sourceUrl) {
    try {
      final mp4Urls = RegExp(r'''https?://[a-zA-Z0-9./_\-%~]+\.mp4[^<>\s"']*''').allMatches(html);
      if (mp4Urls.isNotEmpty) {
        for (final m in mp4Urls) {
          final url = m.group(0)!;
          if (url.length > 30 && !url.contains('watermark')) {
            return VideoInfo(
              noteId: DateTime.now().millisecondsSinceEpoch.toString(),
              title: '抖音视频', author: '', coverUrl: '',
              videoUrl: url, sourceUrl: sourceUrl,
              platform: VideoPlatform.douyin,
            );
          }
        }
        final url = mp4Urls.first.group(0)!;
        return VideoInfo(
          noteId: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '抖音视频', author: '', coverUrl: '',
          videoUrl: url, sourceUrl: sourceUrl,
          platform: VideoPlatform.douyin,
        );
      }
      return null;
    } catch (e) { return null; }
  }
}
