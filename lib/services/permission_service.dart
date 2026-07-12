import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限管理服务
class PermissionService {
  /// 请求存储权限（Android 10+ 需要 MANAGE_EXTERNAL_STORAGE）
  static Future<bool> requestStoragePermission({BuildContext? context}) async {
    // Android 11+
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Android 10 (API 29)
    if (await Permission.storage.isGranted) {
      return true;
    }

    // 请求权限
    if (await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }

    if (await Permission.storage.request().isGranted) {
      return true;
    }

    return false;
  }

  /// 检查是否应该显示权限说明（用户之前拒绝过）
  static Future<bool> shouldShowRationale() async {
    return await Permission.manageExternalStorage.shouldShowRequestRationale ||
        await Permission.storage.shouldShowRequestRationale;
  }

  /// 打开应用设置
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
