import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 通用视频解析器 — 类似 Video Download Helper
///
/// 扫描网页中所有可能的视频源线索：
/// - <video> / <source> / <audio> 标签
/// - meta 标签（og:video, twitter:player）
/// - .mp4 / .webm / .m3u8 / .mpd 直接 URL
/// - JSON 中的 videoUrl / playUrl / src 字段
/// - 常见 CDN 视频路径模式
class GenericParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'GenericParser';
  static const Duration _timeout = Duration(seconds: 20);

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('通用嗅探器扫描: $url', name: _tag);

    // 情况1：直接视频/流媒体文件链接
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

    // 情况2：获取页面 HTML 全面扫描
    final html = await _fetchPage(url, cookie: cookie);
    final result = _scanHtml(html, url);
    if (result != null) return result;

    throw Exception('页面中未找到视频资源\n'
        '支持扫描以下格式：\n'
        '- <video> / <source> HTML 标签\n'
        '- .mp4 / .webm / .m3u8 / .mpd 链接\n'
        '- og:video / twitter:player meta 标签\n'
        '- JSON 嵌入式视频地址\n\n'
        '如果页面有视频但未识别到，建议使用各平台专用解析器');
  }

  bool _isDirectMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.m3u8') ||
        lower.endsWith('.mpd') || lower.endsWith('.webm') ||
        lower.endsWith('.flv') || lower.endsWith('.mov') || lower.endsWith('.mkv');
  }

  String _extractFileName(String url) {
    try {
      final path = Uri.parse(url).pathSegments;
      if (path.isNotEmpty) return path.last.split('?')[0];
    } catch (_) {}
    return '网页视频';
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: VideoParser.commonHeaders(cookie: cookie),
    ).timeout(_timeout);
    if (resp.statusCode == 200) return resp.body;
    throw Exception('页面请求失败: HTTP ${resp.statusCode}');
  }

  /// 全面扫描 HTML 查找视频资源
  VideoInfo? _scanHtml(String html, String sourceUrl) {
    final foundUrls = <String>{};
    String? title;
    String? coverUrl;

    // 0. 标题
    try {
      final t = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false).firstMatch(html);
      if (t != null) title = t.group(1)?.trim();
      final og = RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
      if (og != null) title ??= og.group(1);
      final oc = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
      if (oc != null) coverUrl = oc.group(1);
    } catch (_) {}

    // 1. HTML 标签
    _addMatches(html, RegExp(r'<video[^>]*src="([^"]+)"', caseSensitive: false), foundUrls, sourceUrl);
    _addMatches(html, RegExp(r'<source[^>]*src="([^"]+)"', caseSensitive: false), foundUrls, sourceUrl);
    _addMatches(html, RegExp(r'<audio[^>]*src="([^"]+)"', caseSensitive: false), foundUrls, sourceUrl);

    // 2. Meta 标签
    _addMatch(html, RegExp(r'<meta[^>]*property="og:video"[^>]*content="([^"]*)"', caseSensitive: false), foundUrls);
    _addMatch(html, RegExp(r'<meta[^>]*name="twitter:player"[^>]*content="([^"]*)"', caseSensitive: false), foundUrls);

    // 3. 直接扫描 .mp4 / .m3u8 URL（VDH 核心方式）
    _addMatches(html, RegExp(
      r'https?://[a-zA-Z0-9./_\-%~]+\.(?:mp4|m3u8|webm|flv|mpd|mov|mkv)(?:\?[a-zA-Z0-9=&_\-%~]*)?',
      caseSensitive: false,
    ), foundUrls, sourceUrl, minLen: 25);

    // 4. JSON 中的视频 URL 字段（VDH 常用方式）
    _addMatches(html, RegExp(r'"(?:videoUrl|video_url|playUrl|play_url|mp4_url|src|file|url)"\s*:\s*"(https?://[^"]+)"'), foundUrls, sourceUrl);

    // 5. CDN 路径模式
    _addMatches(html, RegExp(
      r'''https?://[a-zA-Z0-9.-]*?(?:video|media|vod|cdn|stream|play)[a-zA-Z0-9.-]*/[^<>\s"']+''',
      caseSensitive: false,
    ), foundUrls, sourceUrl, minLen: 30);

    developer.log('通用扫描找到 ${foundUrls.length} 个视频源', name: _tag);

    if (foundUrls.isNotEmpty) {
      final bestUrl = _pickBestUrl(foundUrls.toList());
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title ?? '网页视频',
        author: '',
        coverUrl: coverUrl ?? '',
        videoUrl: bestUrl,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.unknown,
      );
    }

    return null;
  }

  /// 从匹配结果中提取并添加到集合
  void _addMatch(String html, RegExp pattern, Set<String> urls) {
    final m = pattern.firstMatch(html);
    if (m != null && m.group(1)!.isNotEmpty) urls.add(m.group(1)!);
  }

  void _addMatches(String html, RegExp pattern, Set<String> urls, String baseUrl, {int minLen = 0}) {
    for (final m in pattern.allMatches(html)) {
      var url = m.groupCount >= 1 ? (m.group(1) ?? m.group(0)!) : m.group(0)!;
      url = _resolveUrl(url, baseUrl);
      if (url.length >= minLen && url.startsWith('http')) {
        urls.add(url);
      }
    }
  }

  /// 智能选择最佳视频 URL
  String _pickBestUrl(List<String> urls) {
    // 优先选 .mp4
    for (final url in urls) {
      if (url.contains('.mp4')) return url;
    }
    // 其次选 .m3u8
    for (final url in urls) {
      if (url.contains('.m3u8')) return url;
    }
    // 第一个非广告 URL
    for (final url in urls) {
      if (!url.contains('google') && !url.contains('facebook')) return url;
    }
    return urls.first;
  }

  String _resolveUrl(String src, String baseUrl) {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    if (src.startsWith('//')) return 'https:$src';
    try {
      final base = Uri.parse(baseUrl);
      if (src.startsWith('/')) return '${base.scheme}://${base.host}$src';
      return '${base.scheme}://${base.host}/$src';
    } catch (_) {
      return src;
    }
  }
}
