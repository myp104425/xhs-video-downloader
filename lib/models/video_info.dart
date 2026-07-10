import 'package:flutter/material.dart';

/// 视频平台枚举
enum VideoPlatform {
  xiaohongshu('小红书', 'xhs', 0xFFFF2442),
  douyin('抖音', 'douyin', 0xFF161823),
  kuaishou('快手', 'kuaishou', 0xFFFF4906),
  bilibili('B站', 'bilibili', 0xFF00A1D6),
  weibo('微博', 'weibo', 0xFFE6162D),
  unknown('其他', 'unknown', 0xFF888888);

  final String displayName;
  final String key;
  final int brandColorInt;

  const VideoPlatform(this.displayName, this.key, this.brandColorInt);

  Color get brandColor => Color(brandColorInt);

  /// 平台图标
  IconData get icon {
    switch (this) {
      case VideoPlatform.xiaohongshu:
        return Icons.auto_stories;
      case VideoPlatform.douyin:
        return Icons.music_note;
      case VideoPlatform.kuaishou:
        return Icons.video_camera_front;
      case VideoPlatform.bilibili:
        return Icons.tv;
      case VideoPlatform.weibo:
        return Icons.forum;
      case VideoPlatform.unknown:
        return Icons.video_library;
    }
  }
}

/// 小红书视频信息数据模型
class VideoInfo {
  /// 笔记/视频ID
  final String noteId;

  /// 视频标题
  final String title;

  /// 作者昵称
  final String author;

  /// 作者头像URL
  final String authorAvatar;

  /// 视频封面图URL
  final String coverUrl;

  /// 视频直链URL（无水印）
  final String videoUrl;

  /// 视频原始链接
  final String sourceUrl;

  /// 视频时长（秒）
  final int duration;

  /// 视频分辨率描述
  final String resolution;

  /// 视频大小（字节）
  final int fileSize;

  /// 点赞数
  final int likes;

  /// 笔记描述
  final String description;

  /// 来源平台
  final VideoPlatform platform;

  /// 下载状态
  DownloadStatus downloadStatus;

  /// 本地文件路径（下载后）
  String? localPath;

  /// 下载时间
  DateTime? downloadTime;

  VideoInfo({
    required this.noteId,
    required this.title,
    required this.author,
    this.authorAvatar = '',
    required this.coverUrl,
    required this.videoUrl,
    required this.sourceUrl,
    this.duration = 0,
    this.resolution = '',
    this.fileSize = 0,
    this.likes = 0,
    this.description = '',
    this.platform = VideoPlatform.unknown,
    this.downloadStatus = DownloadStatus.none,
    this.localPath,
    this.downloadTime,
  });

  /// 从 JSON 创建
  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      noteId: json['note_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      authorAvatar: json['author_avatar'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      resolution: json['resolution'] as String? ?? '',
      fileSize: json['file_size'] as int? ?? 0,
      likes: json['likes'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      platform: VideoPlatform.values.firstWhere(
        (p) => p.key == json['platform'],
        orElse: () => VideoPlatform.unknown,
      ),
      downloadStatus:
          DownloadStatus.values[json['download_status'] as int? ?? 0],
      localPath: json['local_path'] as String?,
      downloadTime: json['download_time'] != null
          ? DateTime.parse(json['download_time'] as String)
          : null,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'note_id': noteId,
      'title': title,
      'author': author,
      'author_avatar': authorAvatar,
      'cover_url': coverUrl,
      'video_url': videoUrl,
      'source_url': sourceUrl,
      'duration': duration,
      'resolution': resolution,
      'file_size': fileSize,
      'likes': likes,
      'description': description,
      'platform': platform.key,
      'download_status': downloadStatus.index,
      'local_path': localPath,
      'download_time': downloadTime?.toIso8601String(),
    };
  }

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize <= 0) return '未知';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 格式化时长
  String get formattedDuration {
    if (duration <= 0) return '';
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 下载状态枚举
enum DownloadStatus {
  /// 未下载
  none,

  /// 下载中
  downloading,

  /// 已暂停
  paused,

  /// 下载完成
  completed,

  /// 下载失败
  failed,
}

/// 下载阶段
enum DownloadStage {
  downloading,
  converting,
  done,
}

/// 下载进度的回调
class DownloadProgress {
  final int received;
  final int total;
  final double speed; // bytes per second
  final DownloadStage stage;

  DownloadProgress({
    required this.received,
    required this.total,
    this.speed = 0,
    this.stage = DownloadStage.downloading,
  });

  double get percentage => total > 0 ? received / total : 0.0;

  String get formattedPercentage => '${(percentage * 100).toStringAsFixed(1)}%';

  String get formattedReceived {
    if (received < 1024) return '$received B';
    if (received < 1024 * 1024) {
      return '${(received / 1024).toStringAsFixed(1)} KB';
    }
    return '${(received / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedTotal {
    if (total < 1024) return '$total B';
    if (total < 1024 * 1024) {
      return '${(total / 1024).toStringAsFixed(1)} KB';
    }
    return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedSpeed {
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
