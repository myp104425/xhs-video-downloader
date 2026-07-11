import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 通用视频嗅探器 — 类似 Video Download Helper
///
/// VDH 的核心原理是监控浏览器网络请求，根据 Content-Type 识别视频文件。
/// 本解析器在 Flutter 中模拟这个行为：
/// 1. 下载页面 HTML
/// 2. 全面扫描所有可能的视频 URL 候选（标签、属性、JSON、正则）
/// 3. 对每个候选发送 HEAD 请求，检查 Content-Type
/// 4. 返回第一个确认为 video/* 或 media 类型的 URL
/// 5. 若没有验证通过的，返回最佳猜测
class GenericParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.unknown;

  static const String _tag = 'GenericParser';
  static const Duration _timeout = Duration(seconds: 15);

  /// 媒体 MIME 类型前缀（VDH 就是靠这些识别视频）
  static const _mediaTypes = [
    'video/',
    'audio/',
    'application/vnd.apple.mpegurl',
    'application/x-mpegurl',
    'application/dash+xml',
    'application/vnd.ms.apple.mpegurl',
  ];

  @override
  bool canParse(String url) {
    return url.startsWith('http://') || url.startsWith('https://');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('VDH嗅探器扫描: $url', name: _tag);

    // 情况1：直接是媒体文件链接
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

    // 情况2：获取页面 HTML 进行 VDH 风格嗅探
    final html = await _fetchPage(url, cookie: cookie);
    return _vdhSniff(html, url);
  }

  // ─── 直接媒体链接检测 ─────────────────────────────

  bool _isDirectMediaUrl(String url) {
    final lower = url.toLowerCase();
    // VDH 检查的文件后缀
    return lower.endsWith('.mp4') || lower.endsWith('.m3u8') ||
        lower.endsWith('.mpd') || lower.endsWith('.webm') ||
        lower.endsWith('.flv') || lower.endsWith('.mov') ||
        lower.endsWith('.mkv') || lower.endsWith('.avi') ||
        lower.endsWith('.ts') || lower.endsWith('.m4s') ||
        lower.endsWith('.m4v') || lower.endsWith('.3gp');
  }

  String _extractFileName(String url) {
    try {
      final path = Uri.parse(url).pathSegments;
      if (path.isNotEmpty) return path.last.split('?')[0];
    } catch (_) {}
    return '视频文件';
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: VideoParser.commonHeaders(cookie: cookie),
    ).timeout(_timeout);
    if (resp.statusCode == 200) return resp.body;
    throw Exception('页面请求失败: HTTP ${resp.statusCode}');
  }

  // ─── VDH 核心嗅探逻辑 ─────────────────────────────

  VideoInfo _vdhSniff(String html, String sourceUrl) {
    String? title;
    String? coverUrl;

    // 提取标题
    try {
      final t = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false).firstMatch(html);
      if (t != null) title = t.group(1)?.trim();
      final og = RegExp(r'<meta[^>]*property="og:title"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
      if (og != null) title ??= og.group(1);
    } catch (_) {}

    // 提取封面
    try {
      final oc = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
      if (oc != null) coverUrl = oc.group(1);
    } catch (_) {}

    // ★ 第一步：收集所有候选视频 URL（VDH 的全面扫描）
    final candidates = <_VideoCandidate>[];

    // 1. <video> / <source> / <audio> HTML 标签
    _addCandidates(html, RegExp(r'<video[^>]*src="([^"]+)"', caseSensitive: false), sourceUrl, candidates);
    _addCandidates(html, RegExp(r'<source[^>]*src="([^"]+)"', caseSensitive: false), sourceUrl, candidates);
    _addCandidates(html, RegExp(r'<audio[^>]*src="([^"]+)"', caseSensitive: false), sourceUrl, candidates);

    // 2. data-src / data-video / data-url 属性（JS 动态加载）
    _addCandidates(html, RegExp(r'data-(?:src|video|url|file)="([^"]+)"', caseSensitive: false), sourceUrl, candidates);

    // 3. meta 标签
    _addCandidates(html, RegExp(r'<meta[^>]*property="og:video"[^>]*content="([^"]*)"', caseSensitive: false), sourceUrl, candidates, ['video/', '.mp4', '.m3u8']);
    _addCandidates(html, RegExp(r'<meta[^>]*name="twitter:player"[^>]*content="([^"]*)"', caseSensitive: false), sourceUrl, candidates);

    // 4. 直接扫描 .mp4 / .m3u8 / .mpd URL（VDH 核心方式——不依赖标签）
    _addCandidates(html, RegExp(
      r'https?://[a-zA-Z0-9./_\-%~]+\.(?:mp4|m3u8|mpd|webm|flv|mov|mkv|ts|m4s)(?:\?[a-zA-Z0-9=&_\-%~]*)?',
      caseSensitive: false,
    ), sourceUrl, candidates);

    // 5. JSON 中的视频 URL 字段
    _addCandidates(html, RegExp(
      r'"(?:videoUrl|video_url|playUrl|play_url|mp4_url|src|file|url|stream_url|hls_url|dash_url|media_url)"\s*:\s*"(https?://[^"]+)"',
      caseSensitive: false,
    ), sourceUrl, candidates);

    // 6. 常见 CDN 视频路径模式
    _addCandidates(html, RegExp(
      r"""https?://[a-zA-Z0-9.-]*?(?:video|media|vod|cdn|stream|play|upload|storage|static)[a-zA-Z0-9.-]*/[^<>\s"']+""",
      caseSensitive: false,
    ), sourceUrl, candidates);

    // 7. 所有带 video 的 <a> 链接
    _addCandidates(html, RegExp(r'<a[^>]*href="([^"]+)"[^>]*>.*?(?:video|播放|下载|download).*?</a>', caseSensitive: false, dotAll: true), sourceUrl, candidates);

    developer.log('VDH 候选: 找到 ${candidates.length} 个候选 URL', name: _tag);

    if (candidates.isEmpty) {
      throw Exception('未在页面中找到视频链接\n'
          'VDH 嗅探已扫描了以下方式：\n'
          '- <video> / <source> 标签\n'
          '- og:video / twitter:player meta\n'
          '- .mp4 / .m3u8 / .mpd 直接链接\n'
          '- JSON 嵌入式视频地址\n'
          '- CDN 视频路径模式\n'
          '- data-* 动态属性');
    }

    // ★ 第二步：用 HEAD 请求验证 Content-Type（VDH 的核心做法）
    final verified = <_VideoCandidate>[];
    final unverified = <_VideoCandidate>[];

    // 并行验证前 15 个候选（VDH 风格：检查实际网络响应）
    final checkResults = await Future.wait(
      candidates.take(15).map((c) => _checkContentType(c)),
    );

    for (var i = 0; i < checkResults.length; i++) {
      if (checkResults[i]) {
        verified.add(candidates[i]);
      } else {
        unverified.add(candidates[i]);
      }
    }

    // 优先返回验证通过的，否则返回最佳猜测
    final best = verified.isNotEmpty
        ? _pickBest(verified)
        : _pickBest(unverified);

    developer.log('VDH 最终选择: ${best.url}', name: _tag);

    return VideoInfo(
      noteId: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ?? '网页视频',
      author: '',
      coverUrl: coverUrl ?? '',
      videoUrl: best.url,
      sourceUrl: sourceUrl,
      platform: VideoPlatform.unknown,
    );
  }

  void _addCandidates(String html, RegExp pattern, String baseUrl, List<_VideoCandidate> candidates, [List<String>? requiredSubstrings]) {
    for (final m in pattern.allMatches(html)) {
      var url = m.groupCount >= 1 ? (m.group(1) ?? m.group(0)!) : m.group(0)!;
      url = _resolveUrl(url, baseUrl);
      if (url.length < 25) continue;
      if (!url.startsWith('http')) continue;
      // 过滤明显不是视频的 URL
      final lower = url.toLowerCase();
      if (lower.contains('.css') || lower.contains('.js') ||
          lower.contains('.jpg') || lower.contains('.png') ||
          lower.contains('.gif') || lower.contains('.svg') ||
          lower.contains('.ico')) continue;
      // 如果要求特定子串
      if (requiredSubstrings != null) {
        bool match = false;
        for (final rs in requiredSubstrings) {
          if (lower.contains(rs) || url.contains(rs)) { match = true; break; }
        }
        if (!match) continue;
      }
      candidates.add(_VideoCandidate(url, _scoreUrl(url)));
    }
  }

  int _scoreUrl(String url) {
    int score = 0;
    final lower = url.toLowerCase();
    if (lower.endsWith('.mp4')) score += 100;
    if (lower.endsWith('.m3u8')) score += 80;
    if (lower.endsWith('.mpd')) score += 70;
    if (lower.endsWith('.webm')) score += 60;
    if (lower.endsWith('.flv')) score += 50;
    if (lower.contains('.mp4')) score += 30;
    if (lower.contains('video')) score += 20;
    if (lower.contains('play')) score += 10;
    if (lower.contains('watermark')) score -= 50;
    return score;
  }

  _VideoCandidate _pickBest(List<_VideoCandidate> candidates) {
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first;
  }

  /// 检查 URL 是否为视频文件（VDH 核心：验证 Content-Type）
  Future<bool> _checkContentType(_VideoCandidate candidate) async {
    try {
      final resp = await http.head(
        Uri.parse(candidate.url),
        headers: {
          'User-Agent': VideoParser.desktopUserAgent,
          'Range': 'bytes=0-0',
        },
      ).timeout(const Duration(seconds: 5));

      final ct = resp.headers['content-type']?.toLowerCase() ?? '';
      if (ct.isNotEmpty && _isMediaType(ct)) {
        developer.log('✅ 验证通过: ${candidate.url} → $ct', name: _tag);
        return true;
      }

      // 某些 CDN 不返回 content-type（302 重定向），但 status 200 说明资源可访问
      if (resp.statusCode == 200 || resp.statusCode == 206) {
        // 没有明确的 content-type 但可访问，作为弱验证通过
        final ext = candidate.url.toLowerCase();
        if (ext.endsWith('.mp4') || ext.endsWith('.m3u8') || ext.endsWith('.mpd')) {
          return true;
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  bool _isMediaType(String contentType) {
    final lower = contentType.toLowerCase();
    for (final mt in _mediaTypes) {
      if (lower.startsWith(mt)) return true;
    }
    return false;
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

class _VideoCandidate {
  final String url;
  final int score;
  _VideoCandidate(this.url, this.score);
}
