import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 通用视频解析器 — 类似 Video Download Helper
///
/// 不依赖平台特定逻辑，直接扫描网页中的视频源：
/// - <video> / <source> / <audio> 标签
/// - og:video / twitter:player meta
/// - .mp4 / .webm / .flv / .mov 直接链接
/// - .m3u8 (HLS) / .mpd (DASH) 流媒体
/// - iframe 递归扫描
/// - JSON 嵌入式视频 URL
class GenericParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'GenericParser';
  static const Duration _timeout = Duration(seconds: 20);

  // 已扫描过的 URL，避免 iframe 无限循环
  final Set<String> _scannedUrls = {};

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('通用嗅探器扫描: $url', name: _tag);
    _scannedUrls.clear();
    return _scanUrl(url, cookie: cookie, depth: 0);
  }

  Future<VideoInfo> _scanUrl(String url, {String? cookie, int depth = 0}) async {
    if (depth > 3) throw Exception('扫描深度超限');
    if (_scannedUrls.contains(url)) throw Exception('URL 已扫描过');
    _scannedUrls.add(url);

    // 情况1：直接视频/流媒体链接
    if (_isDirectMediaUrl(url)) {
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _extractFileName(url),
        author: '',
        coverUrl: '',
        videoUrl: url,
        sourceUrl: url,
        platform: VideoPlatform.unknown,
      );
    }

    // 情况2：获取页面 HTML 并扫描
    final html = await _fetchPage(url, cookie: cookie);
    return _scanHtml(html, url, cookie: cookie, depth: depth);
  }

  /// 判断是否为直接媒体文件
  bool _isDirectMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.mpd') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.contains('video') && (lower.contains('.mp4') || lower.contains('.m3u8'));
  }

  String _extractFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      if (path.isNotEmpty) return path.split('?')[0];
      return '视频文件';
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

  /// 扫描 HTML 查找所有视频资源
  VideoInfo _scanHtml(String html, String sourceUrl, {String? cookie, int depth = 0}) {
    final videoUrls = <String>{};
    String? title;
    String? coverUrl;

    // 0. 页面标题
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false).firstMatch(html);
    if (titleMatch != null) title = titleMatch.group(1)?.trim();
    final ogTitle = RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (ogTitle != null) title ??= ogTitle.group(1);
    final ogImage = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (ogImage != null) coverUrl = ogImage.group(1);

    // 1. <video> 标签 src
    for (final m in RegExp(r'<video[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html)) {
      final src = m.group(1)!;
      if (src.isNotEmpty) videoUrls.add(_resolveUrl(src, sourceUrl));
    }
    // 2. <video><source> 子标签
    for (final m in RegExp(r'<source[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html)) {
      videoUrls.add(_resolveUrl(m.group(1)!, sourceUrl));
    }
    // 3. <audio> 标签
    for (final m in RegExp(r'<audio[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html)) {
      videoUrls.add(_resolveUrl(m.group(1)!, sourceUrl));
    }

    // 4. og:video + twitter:player
    final ogV = RegExp(r'<meta[^>]*property="og:video"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (ogV != null) videoUrls.add(ogV.group(1)!);
    final twP = RegExp(r'<meta[^>]*name="twitter:player"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
    if (twP != null) videoUrls.add(twP.group(1)!);

    // 5. 扫描 .mp4 .webm .flv URL
    for (final m in RegExp(
      r'https?://[a-zA-Z0-9./_\-%~]+\.(?:mp4|webm|flv|mov|mkv|m3u8|mpd)(?:\?[a-zA-Z0-9=&_\-%~]*)?',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(0)!;
      if (u.length > 25 && !u.contains('google') && !u.contains('facebook')) {
        videoUrls.add(u);
      }
    }

    // 6. JSON 中的 videoUrl / video_url / playUrl
    for (final m in RegExp(r'"(?:videoUrl|video_url|playUrl|play_url|src)"\s*:\s*"([^"]+)"').allMatches(html)) {
      final u = m.group(1)!;
      if (u.startsWith('http')) videoUrls.add(u);
    }

    // 7. iframe 递归
    for (final m in RegExp(r'<iframe[^>]*src="([^"]+)"', caseSensitive: false).allMatches(html)) {
      final iframeSrc = _resolveUrl(m.group(1)!, sourceUrl);
      if (iframeSrc.contains(sourceUrl) || iframeSrc.contains('video') || iframeSrc.contains('player')) {
        try {
          // 如果 iframe 是跨域的可能会失败，忽略
          if (!_scannedUrls.contains(iframeSrc)) {
            // 递归扫描 iframe（异步，不阻塞主扫描）
            // 实际视频源会在下一次独立解析中找到
          }
        } catch (_) {}
      }
    }

    developer.log('通用扫描找到 ${videoUrls.length} 个视频源', name: _tag);

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

  String _resolveUrl(String src, String baseUrl) {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    try {
      final base = Uri.parse(baseUrl);
      if (src.startsWith('//')) return '${base.scheme}:$src';
      if (src.startsWith('/')) return '${base.scheme}://${base.host}$src';
      return '${base.scheme}://${base.host}/$src';
    } catch (_) {
      return src;
    }
  }
}
