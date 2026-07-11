import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 通用视频解析器 — 类似 Video Download Helper
///
/// 不依赖平台特定逻辑，直接扫描网页中的视频源：
/// 1. <video> 标签的 src
/// 2. og:video / twitter:player meta 标签
/// 3. .mp4 / .m3u8 直接链接
/// 4. 常见视频 CDN 模式
class GenericParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'GenericParser';
  static const Duration _timeout = Duration(seconds: 20);

  @override
  bool canParse(String url) {
    // 通用解析器作为最后的兜底，接受任何 http(s) URL
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('通用解析器扫描: $url', name: _tag);

    // 情况1：链接直接指向视频文件
    if (_isDirectVideoUrl(url)) {
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _extractFileName(url),
        author: '',
        videoUrl: url,
        sourceUrl: url,
        platform: VideoPlatform.unknown,
      );
    }

    // 情况2：获取页面 HTML 并扫描
    try {
      final html = await _fetchPage(url, cookie: cookie);
      return _scanHtml(html, url);
    } catch (e) {
      developer.log('通用解析失败: $e', name: _tag);
    }

    throw Exception('无法在页面中找到视频资源');
  }

  /// 判断是否为直接视频 URL
  bool _isDirectVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.contains('video') && (lower.contains('.mp4') || lower.contains('.m3u8'));
  }

  String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      return path.isNotEmpty ? path.split('?')[0] : '视频文件';
    } catch (_) {
      return '视频文件';
    }
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final resp = await http
        .get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie))
        .timeout(_timeout);
    if (resp.statusCode == 200) return resp.body;
    throw Exception('页面请求失败: HTTP ${resp.statusCode}');
  }

  /// 扫描 HTML 查找视频资源（类似 VDH 的页面嗅探）
  VideoInfo _scanHtml(String html, String sourceUrl) {
    final videoUrls = <String>{};
    String? title;
    String? coverUrl;

    // 1. 提取页面标题
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false).firstMatch(html);
    if (titleMatch != null) title = titleMatch.group(1)?.trim();

    // 2. og:title
    final ogTitle = RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (ogTitle != null) title ??= ogTitle.group(1);

    // 3. og:image（封面）
    final ogImage = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (ogImage != null) coverUrl = ogImage.group(1);

    // 4. <video> 标签
    final videoTags = RegExp(r'<video[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html);
    for (final m in videoTags) {
      final src = m.group(1)!;
      if (src.isNotEmpty) videoUrls.add(_resolveUrl(src, sourceUrl));
    }
    // <video><source> 子标签
    final sourceTags = RegExp(r'<source[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html);
    for (final m in sourceTags) {
      final src = m.group(1)!;
      if (src.isNotEmpty) videoUrls.add(_resolveUrl(src, sourceUrl));
    }

    // 5. og:video
    final ogVideo = RegExp(r'<meta[^>]*property="og:video"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (ogVideo != null) videoUrls.add(ogVideo.group(1)!);

    // 6. twitter:player
    final twPlayer = RegExp(r'<meta[^>]*name="twitter:player"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (twPlayer != null) videoUrls.add(twPlayer.group(1)!);

    // 7. 直接扫描 .mp4 / .m3u8 URL
    final mp4Urls = RegExp(
      r'https?://[a-zA-Z0-9./_\-%~]+\.(?:mp4|m3u8|webm|flv)(?:\?[a-zA-Z0-9=&_\-%~]*)?',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in mp4Urls) {
      final url = m.group(0)!;
      // 过滤广告 / 太短的 URL
      if (url.length > 30 && !url.contains('google') && !url.contains('facebook')) {
        videoUrls.add(url);
      }
    }

    // 8. 检查 JSON 数据中的视频 URL
    final jsonVideo = RegExp(r'"video[Uu]rl"\s*:\s*"([^"]+)"').allMatches(html);
    for (final m in jsonVideo) {
      final url = m.group(1)!;
      if (url.startsWith('http')) videoUrls.add(url);
    }

    developer.log('通用解析找到 ${videoUrls.length} 个视频源', name: _tag);

    if (videoUrls.isNotEmpty) {
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title ?? '网页视频',
        author: '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrls.first,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.unknown,
      );
    }

    throw Exception('页面中没有找到视频资源');
  }

  /// 解析相对 URL 为绝对 URL
  String _resolveUrl(String src, String baseUrl) {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    try {
      final base = Uri.parse(baseUrl);
      if (src.startsWith('//')) return '${base.scheme}:$src';
      if (src.startsWith('/')) return '${base.scheme}://${base.host}$src';
      return '${base.scheme}://${base.host}/${src}';
    } catch (_) {
      return src;
    }
  }
}
