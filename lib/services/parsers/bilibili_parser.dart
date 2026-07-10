import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// B站解析器
class BilibiliParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.bilibili;

  static const String _tag = 'BilibiliParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _urlPattern = RegExp(
    r'https?://(?:www\.)?bilibili\.com/(?:video|BV)[a-zA-Z0-9]+',
  );
  static final RegExp _bvPattern = RegExp(
    r'BV[a-zA-Z0-9]+',
  );
  static final RegExp _shortUrlPattern = RegExp(
    r'https?://b23\.tv/[a-zA-Z0-9]+',
  );

  @override
  bool canParse(String url) {
    return _urlPattern.hasMatch(url) ||
        _shortUrlPattern.hasMatch(url) ||
        url.contains('bilibili.com') ||
        url.contains('b23.tv');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析B站: $url', name: _tag);

    // 短链接
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
    }

    // 提取 BV 号
    final bvMatch = _bvPattern.firstMatch(url);
    final bvId = bvMatch?.group(0);

    if (bvId == null) {
      throw Exception('无法从链接中提取B站视频ID（BV号）');
    }

    // B站有官方 API（无需 cookie 即可获取视频信息）
    final apiUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvId';
    final response = await http
        .get(Uri.parse(apiUrl), headers: commonHeaders(referer: 'https://www.bilibili.com'))
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('B站API请求失败: HTTP ${response.statusCode}');
    }

    final apiData = jsonDecode(response.body) as Map<String, dynamic>;
    if (apiData['code'] != 0) {
      throw Exception('B站API错误: ${apiData['message']}');
    }

    final videoData = apiData['data'] as Map<String, dynamic>;

    // B站视频无法直接获取直链（需登录 + referer），但可以获取基本信息和封面
    final title = videoData['title']?.toString() ?? '';
    final author = videoData['owner']?['name']?.toString() ?? '';
    final authorAvatar = videoData['owner']?['face']?.toString() ?? '';
    final coverUrl = videoData['pic']?.toString() ?? '';
    final duration = videoData['duration'] as int? ?? 0; // 秒
    final description = videoData['desc']?.toString() ?? '';
    final stat = videoData['stat'] as Map? ?? {};
    final likes = stat['like'] as int? ?? 0;
    final aid = (videoData['aid'] as int?)?.toString() ?? '';

    // 尝试获取视频播放地址（需要 cookie 和 referer）
    String? videoUrl = '';
    try {
      final playUrl =
          'https://api.bilibili.com/x/player/playurl?bvid=$bvId&cid=${videoData['cid']}&qn=112&fnval=0&fnver=0&fourk=1';
      final playResponse = await http
          .get(Uri.parse(playUrl),
              headers: commonHeaders(cookie: cookie, referer: 'https://www.bilibili.com'))
          .timeout(_timeout);

      if (playResponse.statusCode == 200) {
        final playData = jsonDecode(playResponse.body);
        if (playData['code'] == 0) {
          final durl = playData['data']?['durl'] as List?;
          if (durl != null && durl.isNotEmpty) {
            videoUrl = durl[0]['url']?.toString() ?? '';
          }
        }
      }
    } catch (e) {
      developer.log('B站视频流获取失败(可接受): $e', name: _tag);
    }

    return VideoInfo(
      noteId: bvId,
      title: title,
      author: author,
      authorAvatar: authorAvatar,
      coverUrl: coverUrl,
      videoUrl: videoUrl,
      sourceUrl: url,
      duration: duration,
      resolution: '1080p',
      likes: likes,
      description: description,
      platform: VideoPlatform.bilibili,
    );
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
}
