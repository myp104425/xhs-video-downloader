import 'package:flutter/material.dart';
import '../models/video_info.dart';

/// 平台标识徽章
class PlatformBadge extends StatelessWidget {
  final VideoPlatform platform;
  final double size;

  const PlatformBadge({
    super.key,
    required this.platform,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: platform.brandColor,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: platform.brandColor.withOpacity(0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        platform.icon,
        color: Colors.white,
        size: size * 0.6,
      ),
    );
  }
}
