import 'package:flutter_test/flutter_test.dart';
import 'package:xhs_video_downloader/models/video_info.dart';
import 'package:xhs_video_downloader/services/parsers/parser_manager.dart';

void main() {
  group('VideoInfo Model', () {
    test('should create VideoInfo with correct values', () {
      final video = VideoInfo(
        noteId: '12345',
        title: '测试视频',
        author: '测试作者',
        coverUrl: 'https://example.com/cover.jpg',
        videoUrl: 'https://example.com/video.mp4',
        sourceUrl: 'https://www.xiaohongshu.com/explore/12345',
        duration: 120,
        resolution: '1080p',
        fileSize: 10 * 1024 * 1024,
        likes: 1000,
        platform: VideoPlatform.xiaohongshu,
      );

      expect(video.noteId, '12345');
      expect(video.title, '测试视频');
      expect(video.formattedDuration, '02:00');
      expect(video.formattedSize, '10.0 MB');
      expect(video.resolution, '1080p');
      expect(video.platform, VideoPlatform.xiaohongshu);
    });

    test('should serialize to JSON and back', () {
      final original = VideoInfo(
        noteId: '12345',
        title: '测试视频',
        author: '测试作者',
        coverUrl: 'https://example.com/cover.jpg',
        videoUrl: 'https://example.com/video.mp4',
        sourceUrl: 'https://www.xiaohongshu.com/explore/12345',
        duration: 120,
        fileSize: 1024,
        likes: 500,
        platform: VideoPlatform.douyin,
      );

      final json = original.toJson();
      final restored = VideoInfo.fromJson(json);

      expect(restored.noteId, original.noteId);
      expect(restored.title, original.title);
      expect(restored.author, original.author);
      expect(restored.platform, VideoPlatform.douyin);
      expect(restored.downloadStatus, DownloadStatus.none);
    });

    test('should format file size correctly', () {
      final video1 = VideoInfo(
        noteId: '1', title: '', author: '', coverUrl: '', videoUrl: '',
        sourceUrl: '', fileSize: 500,
      );
      expect(video1.formattedSize, '500 B');

      final video2 = VideoInfo(
        noteId: '2', title: '', author: '', coverUrl: '', videoUrl: '',
        sourceUrl: '', fileSize: 2048,
      );
      expect(video2.formattedSize, '2.0 KB');

      final video3 = VideoInfo(
        noteId: '3', title: '', author: '', coverUrl: '', videoUrl: '',
        sourceUrl: '', fileSize: 5 * 1024 * 1024,
      );
      expect(video3.formattedSize, '5.0 MB');
    });

    test('should format duration correctly', () {
      final video1 = VideoInfo(
        noteId: '1', title: '', author: '', coverUrl: '', videoUrl: '',
        sourceUrl: '', duration: 65,
      );
      expect(video1.formattedDuration, '01:05');

      final video2 = VideoInfo(
        noteId: '2', title: '', author: '', coverUrl: '', videoUrl: '',
        sourceUrl: '', duration: 0,
      );
      expect(video2.formattedDuration, '');
    });
  });

  group('ParserManager', () {
    test('should validate correct URLs', () {
      final pm = ParserManager();

      expect(pm.isValidUrl('https://www.xiaohongshu.com/explore/123'),
          isTrue);
      expect(pm.isValidUrl('https://xhslink.com/abc'), isTrue);
      expect(pm.isValidUrl('https://www.douyin.com/video/123'), isTrue);
      expect(pm.isValidUrl('https://v.douyin.com/abc'), isTrue);
      expect(pm.isValidUrl('https://www.kuaishou.com/short-video/abc'),
          isTrue);
      expect(pm.isValidUrl('https://www.bilibili.com/video/BV123'), isTrue);
      expect(pm.isValidUrl('https://b23.tv/abc'), isTrue);
      expect(pm.isValidUrl('https://www.weibo.com/123/abc'), isTrue);
    });

    test('should reject invalid URLs', () {
      final pm = ParserManager();
      expect(pm.isValidUrl('https://www.youtube.com/watch?v=abc'), isTrue);
      expect(pm.isValidUrl('not-a-url'), isFalse);
      expect(pm.isValidUrl('ftp://example.com'), isFalse);
      expect(pm.isValidUrl(''), isFalse);
    });

    test('should detect correct platforms', () {
      final pm = ParserManager();

      expect(
        pm.detectPlatform('https://www.xiaohongshu.com/explore/123'),
        VideoPlatform.xiaohongshu,
      );
      expect(
        pm.detectPlatform('https://www.douyin.com/video/123'),
        VideoPlatform.douyin,
      );
      expect(
        pm.detectPlatform('https://www.kuaishou.com/short-video/abc'),
        VideoPlatform.kuaishou,
      );
      expect(
        pm.detectPlatform('https://www.bilibili.com/video/BV123'),
        VideoPlatform.bilibili,
      );
      expect(
        pm.detectPlatform('https://www.weibo.com/123/abc'),
        VideoPlatform.weibo,
      );
    });
  });
}
