import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 抖音 / TikTok 解析器
///
/// 解析思路（借鉴 Video Download Helper）：
/// 1. 从短链接重定向获取真实 URL
/// 2. 使用抖音开放 API 获取视频信息
/// 3. 从页面 HTML 正则提取视频源作为兜底
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

    // 短链接重定向
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
      developer.log('短链接解析后: $url', name: _tag);
    }

    final awemeId = _extractAwemeId(url);

    // 方法1: API 解析
    if (awemeId != null) {
      try {
        return await _parseViaApi(awemeId, url, cookie: cookie);
      } catch (e) {
        developer.log('API 解析失败: $e', name: _tag);
      }
    }

    // 方法2: 页面 HTML 解析
    try {
      final html = await _fetchPage(url, cookie: cookie);
      final result = _parseFromHtml(html, url);
      if (result != null) return result;
    } catch (e) {
      developer.log('页面解析失败: $e', name: _tag);
    }

    // 方法3: 使用第三方无版权 API 作为终极兜底
    if (awemeId != null) {
      return await _parseViaThirdParty(awemeId, url);
    }

    throw Exception('无法从抖音解析视频信息\n'
        '请确认链接有效：\n'
        '1. 在抖音 App 中点「分享」→「复制链接」\n'
        '2. 粘贴以 https://v.douyin.com/ 开头的短链接');
  }

  Future<String> _resolveRedirect(String url) async {
    try {
      final resp = await http.head(Uri.parse(url), headers: VideoParser.commonHeaders()).timeout(_timeout);
      return resp.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }

  String? _extractAwemeId(String url) {
    final m = RegExp(r'/video/(\d+)').firstMatch(url);
    if (m != null) return m.group(1);
    final segs = Uri.tryParse(url)?.pathSegments ?? [];
    for (final s in segs.reversed) {
      if (RegExp(r'^\d+$').hasMatch(s)) return s;
    }
    return null;
  }

  /// 通过抖音公开 Web API 解析
  Future<VideoInfo> _parseViaApi(String awemeId, String sourceUrl, {String? cookie}) async {
    final apiUrl = 'https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id=$awemeId';
    final resp = await http
        .get(Uri.parse(apiUrl), headers: VideoParser.commonHeaders(cookie: cookie, referer: 'https://www.douyin.com'))
        .timeout(_timeout);

    if (resp.statusCode != 200) throw Exception('API 请求失败: HTTP ${resp.statusCode}');

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final detail = data['aweme_detail'] as Map?;
    if (detail == null) throw Exception('API 返回数据异常');

    return _extractDetail(detail, sourceUrl);
  }

  /// 使用第三方接口兜底（供无法直连 API 时使用）
  Future<VideoInfo> _parseViaThirdParty(String awemeId, String sourceUrl) async {
    // 使用第三方 hybrid API - 仅供学习用途备用
    try {
      final v6Resp = await http
          .get(Uri.parse('https://www.iesdouyin.com/aweme/v1/web/aweme/detail/?aweme_id=$awemeId'),
              headers: VideoParser.commonHeaders())
          .timeout(_timeout);
      if (v6Resp.statusCode == 200) {
        final data = jsonDecode(v6Resp.body) as Map<String, dynamic>;
        final detail = data['aweme_detail'] as Map?;
        if (detail != null) return _extractDetail(detail, sourceUrl);
      }
    } catch (_) {}

    throw Exception('无法获取抖音视频信息');
  }

  /// 从 aweme_detail 提取视频信息
  VideoInfo _extractDetail(Map detail, String sourceUrl) {
    final desc = detail['desc']?.toString() ?? '';
    final author = detail['author']?['nickname']?.toString() ?? '';
    final avatar = detail['author']?['avatar_thumb']?['url_list']?.first?.toString() ?? '';
    final cover = detail['video']?['cover']?['url_list']?.first?.toString() ?? '';
    final duration = (detail['video']?['duration'] as int? ?? 0) ~/ 1000;

    // 提取无水印视频地址
    String videoUrl = '';
    final video = detail['video'] as Map?;
    if (video != null) {
      // play_addr 最高画质
      final playAddr = video['play_addr'] as Map?;
      if (playAddr != null) {
        final uriList = playAddr['uri_list'] ?? playAddr['url_list'];
        if (uriList is List && uriList.isNotEmpty) {
          for (final uri in uriList) {
            final u = uri.toString();
            if (!u.contains('watermark') && u.isNotEmpty) {
              videoUrl = u.startsWith('//') ? 'https:$u' : u;
              break;
            }
          }
          if (videoUrl.isEmpty) {
            final u = uriList.first.toString();
            videoUrl = u.startsWith('//') ? 'https:$u' : u;
          }
        }
      }
    }

    if (videoUrl.isEmpty) throw Exception('未找到视频地址');

    return VideoInfo(
      noteId: detail['aweme_id']?.toString() ?? '',
      title: desc,
      author: author,
      authorAvatar: avatar,
      coverUrl: cover,
      videoUrl: videoUrl,
      sourceUrl: sourceUrl,
      duration: duration,
      resolution: '1080p',
      platform: VideoPlatform.douyin,
    );
  }

  Future<String> _fetchPage(String url, {String? cookie}) async {
    final resp = await http
        .get(Uri.parse(url), headers: VideoParser.commonHeaders(cookie: cookie))
        .timeout(_timeout);
    if (resp.statusCode == 200) return resp.body;
    throw Exception('页面请求失败: HTTP ${resp.statusCode}');
  }

  /// 从页面 HTML 正则提取视频
  VideoInfo? _parseFromHtml(String html, String sourceUrl) {
    // 方法1: SSR 数据
    final patterns = [
      RegExp(r'<script[^>]*id="RENDER_DATA"[^>]*>(.*?)</script>', dotAll: true),
      RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});', dotAll: true),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(html);
      if (m == null) continue;
      String raw = m.group(1)!;
      if (raw.contains('%')) {
        try { raw = Uri.decodeComponent(raw); } catch (_) {}
      }
      try {
        final data = jsonDecode(raw);
        final result = _extractFromData(data);
        if (result != null) return result;
      } catch (_) {}
    }

    // 方法2: 直接提取 .mp4 URL
    final mp4s = RegExp(r'https?://[a-zA-Z0-9./_-]+\.mp4[^"'"'"'\s]*').allMatches(html);
    if (mp4s.isNotEmpty) {
      return VideoInfo(
        noteId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '抖音视频',
        author: '',
        videoUrl: mp4s.first.group(0)!,
        sourceUrl: sourceUrl,
        platform: VideoPlatform.douyin,
      );
    }
    return null;
  }

  VideoInfo? _extractFromData(dynamic data) {
    try {
      String? videoUrl, title, author, coverUrl, noteId;
      int duration = 0;

      void search(dynamic obj, {int d = 0}) {
        if (d > 10 || obj == null) return;
        if (obj is Map) {
          if (obj['play_addr'] is Map) {
            final list = (obj['play_addr'] as Map)['url_list'] ?? (obj['play_addr'] as Map)['uri_list'];
            if (list is List && list.isNotEmpty) {
              var u = list.first.toString();
              if (u.startsWith('//')) u = 'https:$u';
              videoUrl ??= u;
            }
          }
          if (obj['src'] is String) {
            final s = obj['src'] as String;
            if (s.contains('.mp4')) videoUrl ??= s;
          }
          noteId ??= obj['aweme_id']?.toString() ?? obj['video_id']?.toString();
          title ??= obj['desc']?.toString();
          author ??= obj['author']?['nickname']?.toString() ?? obj['nickname']?.toString();
          if (obj['cover'] is Map) {
            final list = (obj['cover'] as Map)['url_list'];
            if (list is List && list.isNotEmpty) coverUrl ??= list.first.toString();
          }
          if (obj['duration'] is int) duration = (obj['duration'] as int) ~/ 1000;
          for (final v in obj.values) { search(v, d: d + 1); }
        } else if (obj is List) {
          for (final item in obj) { search(item, d: d + 1); }
        }
      }

      search(data);
      if (videoUrl == null) return null;
      return VideoInfo(
        noteId: noteId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title ?? '抖音视频',
        author: author ?? '',
        coverUrl: coverUrl ?? '',
        videoUrl: videoUrl!,
        sourceUrl: '',
        duration: duration,
        platform: VideoPlatform.douyin,
      );
    } catch (_) {
      return null;
    }
  }
}
