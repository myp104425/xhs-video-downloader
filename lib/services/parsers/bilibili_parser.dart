import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../models/video_info.dart';
import 'parser_base.dart';

/// B站解析器
///
/// 核心思路：
/// 1. 从 URL 提取 BV 号
/// 2. 调用 B 站 API 获取视频元数据
/// 3. 获取视频播放地址（flv 格式最可靠，返回绝对 URL）
class BilibiliParser extends VideoParser {
  @override
  VideoPlatform get platform => VideoPlatform.bilibili;

  static const String _tag = 'BilibiliParser';
  static const Duration _timeout = Duration(seconds: 30);

  static final RegExp _bvPattern = RegExp(r'BV[a-zA-Z0-9]+');
  static final RegExp _shortUrlPattern = RegExp(r'https?://b23\.tv/[a-zA-Z0-9]+');

  @override
  bool canParse(String url) {
    return _bvPattern.hasMatch(url) || _shortUrlPattern.hasMatch(url) ||
        url.contains('bilibili.com') || url.contains('b23.tv');
  }

  @override
  Future<VideoInfo> parse(String url, {String? cookie}) async {
    developer.log('开始解析B站: $url', name: _tag);

    // 短链接重定向
    if (_shortUrlPattern.hasMatch(url)) {
      url = await _resolveRedirect(url);
    }

    // 提取 BV 号
    final bvMatch = _bvPattern.firstMatch(url);
    final bvId = bvMatch?.group(0);
    if (bvId == null) throw Exception('无法提取B站视频ID（BV号）');

    // 获取视频元数据
    final viewResp = await http.get(
      Uri.parse('https://api.bilibili.com/x/web-interface/view?bvid=$bvId'),
      headers: VideoParser.commonHeaders(referer: 'https://www.bilibili.com'),
    ).timeout(_timeout);

    if (viewResp.statusCode != 200) throw Exception('B站API请求失败');
    final viewData = jsonDecode(viewResp.body) as Map<String, dynamic>;
    if (viewData['code'] != 0) throw Exception('B站API错误: ${viewData['message']}');

    final d = viewData['data'] as Map;
    final title = d['title']?.toString() ?? '';
    final author = d['owner']?['name']?.toString() ?? '';
    final authorAvatar = d['owner']?['face']?.toString() ?? '';
    final coverUrl = d['pic']?.toString() ?? '';
    final duration = d['duration'] as int? ?? 0;
    final desc = d['desc']?.toString() ?? '';
    final likes = (d['stat'] as Map?)?['like'] as int? ?? 0;

    // 获取 cid
    dynamic cid = d['cid'];
    if (cid == null) {
      final pages = d['pages'];
      if (pages is List && pages.isNotEmpty) {
        cid = (pages.first as Map)['cid'];
      }
    }
    final cidStr = cid?.toString() ?? '';
    if (cidStr.isEmpty) throw Exception('无法获取视频 cid');

    // 获取视频播放地址 — Python 脚本方案：fnval=4048 DASH + durl 兜底
    String videoUrl = '';
    try {
      // 先用 DASH (fnval=4048) — Python 脚本方案
      final playResp = await http.get(
        Uri.parse('https://api.bilibili.com/x/player/playurl?bvid=$bvId&cid=$cidStr&qn=0&fnval=4048&fnver=0&fourk=1'),
        headers: VideoParser.commonHeaders(cookie: cookie, referer: 'https://www.bilibili.com'),
      ).timeout(_timeout);

      if (playResp.statusCode == 200) {
        final playData = jsonDecode(playResp.body) as Map<String, dynamic>;
        if (playData['code'] == 0) {
          final data = playData['data'] as Map?;
          if (data != null) {
            // 方式1: DASH 视频流 (Python 脚本方案，取最高码率)
            if (data['dash'] is Map) {
              final dash = data['dash'] as Map;
              final videos = dash['video'] as List?;
              if (videos != null && videos.isNotEmpty) {
                // 按带宽排序取最高画质
                videos.sort((a, b) => ((b as Map)['bandwidth'] ?? 0).compareTo((a as Map)['bandwidth'] ?? 0));
                final best = videos.first as Map;
                var url = best['baseUrl']?.toString() ?? '';
                // baseUrl 可能是相对路径，需要补全
                if (url.startsWith('/')) {
                  url = 'https://upos-sz-mirrorali.bilivideo.com$url';
                }
                if (url.isNotEmpty && url.startsWith('http')) videoUrl = url;
              }
            }
            // 方式2: flv 格式 (兜底)
            if (videoUrl.isEmpty && data['durl'] is List) {
              final durl = data['durl'] as List;
              if (durl.isNotEmpty) {
                var url = (durl.first as Map)['url']?.toString() ?? '';
                if (url.isNotEmpty) videoUrl = url;
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
      final resp = await http.head(Uri.parse(url), headers: VideoParser.commonHeaders()).timeout(_timeout);
      return resp.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }
}
