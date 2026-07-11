import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// B站解析器
///
/// 解析思路：
/// 1. 从 URL 提取 BV 号 / AV 号
/// 2. 调用 B 站公开 API 获取视频元数据（标题、封面、作者等）
/// 3. 获取视频播放流地址（直链，需 referer）
class BilibiliParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.bilibili;

  static const String _tag = 'BilibiliParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _bvPattern = RegExp(r'BV[a-zA-Z0-9]+');
  static final RegExp _avPattern = RegExp(r'av(\d+)', caseSensitive: false);
  static final RegExp _shortUrlPattern = RegExp(r'https?://b23\.tv/[a-zA-Z0-9]+');

  @override
  bool canParse(String url) {
    return _bvPattern.hasMatch(url) ||
        _avPattern.hasMatch(url) ||
        _shortUrlPattern.hasMatch(url) ||
        url.contains('bilibili.com') ||
        url.contains('b23.tv');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析B站: $url', name: _tag);

    // 短链接重定向
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
      developer.log('短链接解析后: $url', name: _tag);
    }

    // 提取 BV 号
    final bvMatch = _bvPattern.firstMatch(url);
    final bvId = bvMatch?.group(0);
    if (bvId == null) {
      throw Exception('无法从链接中提取B站视频ID（BV号）');
    }

    // 调用 B 站 API 获取视频信息
    final viewResp = await http
        .get(
          Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$bvId'),
          headers: VideoParser.commonHeaders(referer: 'https://www.bilibili.com'),
        )
        .timeout(_timeout);

    if (viewResp.statusCode != 200) {
      throw Exception('B站API请求失败: HTTP ${viewResp.statusCode}');
    }

    final viewData = jsonDecode(viewResp.body) as Map<String, dynamic>;
    if (viewData['code'] != 0) {
      throw Exception('B站API错误: ${viewData['message'] ?? '未知错误'}');
    }

    final videoData = viewData['data'] as Map<String, dynamic>;
    final title = videoData['title']?.toString() ?? '';
    final author = videoData['owner']?['name']?.toString() ?? '';
    final authorAvatar = videoData['owner']?['face']?.toString() ?? '';
    final coverUrl = videoData['pic']?.toString() ?? '';
    final duration = videoData['duration'] as int? ?? 0;
    final desc = videoData['desc']?.toString() ?? '';
    final stat = videoData['stat'] as Map? ?? {};
    final likes = stat['like'] as int? ?? 0;

    // 获取 cid（视频分P，默认取第一P）
    dynamic cid = videoData['cid'];
    if (cid == null) {
      final pages = videoData['pages'];
      if (pages is List && pages.isNotEmpty) {
        cid = (pages.first as Map)['cid'];
      }
    }
    final cidStr = cid?.toString() ?? '';
    if (cidStr.isEmpty) {
      throw Exception('无法获取视频 cid');
    }

    // 尝试获取视频播放地址
    String videoUrl = '';
    try {
      // qn=112 (1080p+), fnval=16 (DASH), fnver=0, fourk=1
      final playUrl =
          'https://api.bilibili.com/x/player/playurl?bvid=$bvId&cid=$cidStr&qn=112&fnval=16&fnver=0&fourk=1';
      final playResp = await http
          .get(
            Uri.parse(playUrl),
            headers: VideoParser.commonHeaders(cookie: cookie, referer: 'https://www.bilibili.com'),
          )
          .timeout(_timeout);

      if (playResp.statusCode == 200) {
        final playData = jsonDecode(playResp.body) as Map<String, dynamic>;
        if (playData['code'] == 0) {
          final data = playData['data'] as Map?;
          if (data != null) {
            // DASH 格式 - video 列表取最高画质 baseUrl
            if (data['dash'] is Map) {
              final dash = data['dash'] as Map;
              final videoList = dash['video'] as List?;
              if (videoList != null && videoList.isNotEmpty) {
                // 取最高画质的 baseUrl
                final best = videoList.last as Map;
                var url = best['base_url']?.toString() ?? best['baseUrl']?.toString() ?? '';
                // DASH 的 base_url 是相对路径，需要拼接 CDN 域名
                if (url.isNotEmpty) {
                  if (!url.startsWith('http')) {
                    // 从 backup_url 提取 CDN 域名
                    final backup = best['backup_url'] as List?;
                    if (backup != null && backup.isNotEmpty) {
                      final fullUrl = backup.first.toString();
                      final uri = Uri.tryParse(fullUrl);
                      if (uri != null) {
                        url = '${uri.scheme}://${uri.host}$url';
                      }
                    }
                  }
                  videoUrl = url;
                }
              }
            }
            // MP4 格式（flv）
            if (videoUrl.isEmpty && data['durl'] is List) {
              final durl = data['durl'] as List;
              if (durl.isNotEmpty) {
                var url = (durl.first as Map)['url']?.toString() ?? '';
                if (url.isNotEmpty) {
                  // B站 flv 地址可能带重定向
                  if (!url.contains('.bilivideo.com') && url.contains('://')) {
                    // 已经是完整 URL
                  }
                  videoUrl = url;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      developer.log('B站视频流获取失败: $e', name: _tag);
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
      resolution: videoUrl.isNotEmpty ? '1080p' : '',
      likes: likes,
      description: desc,
      platform: VideoPlatform.bilibili,
    );
  }

  Future<String> _resolveRedirect(String url) async {
    try {
      final response = await http
          .head(Uri.parse(url), headers: VideoParser.commonHeaders())
          .timeout(_timeout);
      return response.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }
}
