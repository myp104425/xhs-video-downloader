import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// 抖音 / TikTok 解析器
///
/// 核心思路：
/// 1. 从分享短链接重定向到真实视频页
/// 2. 从视频页 SSR 数据（window.__INITIAL_STATE__）提取视频信息
/// 3. 从页面正则提取视频直链 URL 作为兜底
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

    // 短链接重定向获取真实页面 URL
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
      developer.log('短链接解析后: $url', name: _tag);
    }

    // 获取页面 HTML
    final html = await _fetchPage(url, cookie: cookie);

    // 方法1: 从 SSR 数据提取
    final ssrResult = _parseFromSSR(html, url);
    if (ssrResult != null) {
      developer.log('SSR解析成功: ${ssrResult.title}', name: _tag);
      return ssrResult;
    }

    // 方法2: 从页面正则提取 MP4 URL
    final regexResult = _parseFromRegex(html, url);
    if (regexResult != null) return regexResult;

    throw Exception('无法解析抖音视频\n'
        '请确认：\n'
        '1. 在抖音 App 中点「分享」→「复制链接」\n'
        '2. 粘贴的是 https://v.douyin.com/ 开头的短链接');
  }

  /// 短链接重定向
  Future<String> _resolveRedirect(String url) async {
    try {
      final resp = await http.head(
        Uri.parse(url),
        headers: VideoParser.commonHeaders(),
      ).timeout(_timeout);
      final redirectUrl = resp.request?.url.toString() ?? url;
      // 抖音会 302 到真实页面
      if (redirectUrl != url && redirectUrl.contains('douyin.com')) {
        return redirectUrl;
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  /// 获取页面 HTML
  Future<String> _fetchPage(String url, {String? cookie}) async {
    final resp = await http.get(
      Uri.parse(url),
      headers: VideoParser.commonHeaders(cookie: cookie),
    ).timeout(_timeout);
    if (resp.statusCode == 200) return resp.body;
    throw Exception('页面请求失败: HTTP ${resp.statusCode}');
  }

  /// 从 SSR 数据提取视频信息
  VideoInfo? _parseFromSSR(String html, String sourceUrl) {
    try {
      // 抖音 SSR 数据有以下几种嵌入方式
      final patterns = [
        // 方式1: window.__INITIAL_STATE__
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*JSON\.parse\((&quot;|")(.*?)(&quot;|")\)',
            dotAll: true),
        RegExp(r'window\.__INITIAL_STATE__\s*=\s*({.*?});\s*<',
            dotAll: true),
        // 方式2: <script> 中的 JSON 数据
        RegExp(r'<script\s+id="__NEXT_DATA__"[^>]*type="application/json"[^>]*>(.*?)</script>',
            dotAll: true),
      ];

      Map<String, dynamic>? data;

      for (final pattern in patterns) {
        final m = pattern.firstMatch(html);
        if (m == null) continue;

        final raw = m.group(m.groupCount)!;
        String json = raw;

        // 处理 HTML 实体编码
        if (json.contains('&quot;')) {
          json = json.replaceAll('&quot;', '"').replaceAll('\\"', '"');
        }

        try {
          data = jsonDecode(json) as Map<String, dynamic>;
          break;
        } catch (_) {
          // 尝试清理后再次解析
          try {
            // 某些 SSR 数据包含非标准字符
            json = json
                .replaceAll('\\\n', '')
                .replaceAll('\\\r', '')
                .replaceAll('undefined', 'null');
            data = jsonDecode(json) as Map<String, dynamic>;
            break;
          } catch (_) {}
        }
      }

      if (data == null) return null;

      // 从 SSR 树中递归查找视频信息
      return _extractVideoInfo(data, sourceUrl);
    } catch (e) {
      developer.log('SSR解析异常: $e', name: _tag);
      return null;
    }
  }

  /// 从 JSON 树中递归提取视频信息
  VideoInfo? _extractVideoInfo(dynamic data, String sourceUrl) {
    String? title;
    String? author;
    String? cover;
    String? videoUrl;
    String? noteId;
    int duration = 0;

    void search(dynamic obj, {int depth = 0}) {
      if (depth > 12 || obj == null || videoUrl != null) return;

      if (obj is Map) {
        // 检测视频 URL — play_addr
        if (obj.containsKey('play_addr') && obj['play_addr'] is Map) {
          final addr = obj['play_addr'] as Map;
          final urlList = addr['url_list'];
          if (urlList is List && urlList.isNotEmpty) {
            for (final u in urlList) {
              final urlStr = u.toString();
              if (urlStr.contains('https://') && !urlStr.contains('watermark')) {
                videoUrl = urlStr;
                break;
              }
            }
            if (videoUrl == null) {
              videoUrl = urlList.first.toString();
            }
          }
          // 如果是 uri 格式，构造完整 URL
          if ((videoUrl == null || videoUrl!.isEmpty) && addr['uri'] != null) {
            final uri = addr['uri'].toString();
            if (uri.isNotEmpty) {
              videoUrl = 'https://aweme.snssdk.com/aweme/v1/play/?video_id=$uri&ratio=720p&line=0';
            }
          }
        }

        // 标题
        if (obj['desc'] is String && title == null) title = obj['desc'];
        if (obj['title'] is String && title == null) title = obj['title'];

        // 作者
        if (obj['author'] is Map) {
          author ??= (obj['author'] as Map)['nickname']?.toString();
        }

        // 封面
        if (obj['cover'] is Map) {
          final urlList = (obj['cover'] as Map)['url_list'];
          if (urlList is List && urlList.isNotEmpty) cover ??= urlList.first.toString();
        }

        // aweme_id / item_id
        if (obj['aweme_id'] is String) noteId ??= obj['aweme_id'];
        if (obj['item_id'] is String) noteId ??= obj['item_id'];

        // 时长
        if (obj['duration'] is int) duration = (obj['duration'] as int) ~/ 1000;

        // 剪枝：已经找到 videoUrl 就不再深入
        for (final val in obj.values) {
          if (videoUrl != null) break;
          search(val, depth: depth + 1);
        }
      } else if (obj is List) {
        for (final item in obj) {
          if (videoUrl != null) break;
          search(item, depth: depth + 1);
        }
      }
    }

    search(data);

    if (videoUrl == null || videoUrl!.isEmpty) return null;

    return VideoInfo(
      noteId: noteId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title ?? '抖音视频',
      author: author ?? '',
      coverUrl: cover ?? '',
      videoUrl: videoUrl!,
      sourceUrl: sourceUrl,
      duration: duration,
      resolution: '720p',
      platform: VideoPlatform.douyin,
    );
  }

  /// 从页面正则提取视频地址
  VideoInfo? _parseFromRegex(String html, String sourceUrl) {
    try {
      final mp4Urls = RegExp(
        r'https?://[a-zA-Z0-9./_\-%~]+\.mp4(?:\?[a-zA-Z0-9=&_\-%~]*)?',
      ).allMatches(html);

      if (mp4Urls.isNotEmpty) {
        for (final m in mp4Urls) {
          final url = m.group(0)!;
          if (url.length > 30 && !url.contains('watermark')) {
            return VideoInfo(
              noteId: DateTime.now().millisecondsSinceEpoch.toString(),
              title: '抖音视频',
              author: '',
              coverUrl: '',
              videoUrl: url,
              sourceUrl: sourceUrl,
              platform: VideoPlatform.douyin,
            );
          }
        }
        // 如果只有带水印的
        final url = mp4Urls.first.group(0)!;
        return VideoInfo(
          noteId: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '抖音视频',
          author: '',
          coverUrl: '',
          videoUrl: url,
          sourceUrl: sourceUrl,
          platform: VideoPlatform.douyin,
        );
      }

      return null;
    } catch (e) {
      developer.log('正则解析异常: $e', name: _tag);
      return null;
    }
  }
}
