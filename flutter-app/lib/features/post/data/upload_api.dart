import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/network/dio_client.dart';

class UploadApi {
  const UploadApi(this._client);

  final DioClient _client;

  Future<String> uploadImage(
    File file, {
    void Function(int, int)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
    });
    final result = await _client.upload<Map<String, dynamic>>(
      ApiPaths.uploadSingle,
      form: form,
      onProgress: onProgress,
      decode: (d) => d as Map<String, dynamic>,
    );
    final url =
        result['url'] ?? (result['data'] is Map ? result['data']['url'] : null);
    if (url == null) {
      throw StateError('上传响应缺少 url 字段');
    }
    return url.toString();
  }

  Future<List<String>> uploadImages(List<File> files) async {
    final form = FormData.fromMap({
      'files': await Future.wait(
        files.map((f) => MultipartFile.fromFile(f.path)),
      ),
    });
    final result = await _client.upload<Map<String, dynamic>>(
      ApiPaths.uploadMultiple,
      form: form,
      decode: (d) => d as Map<String, dynamic>,
    );
    final urls = result['urls'] ?? result['data']?['urls'];
    if (urls is List) {
      return urls.map((e) => e.toString()).toList();
    }
    throw StateError('上传响应缺少 urls 字段');
  }

  Future<VideoUploadResult> uploadVideo(
    File file, {
    void Function(int, int)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path),
    });
    final result = await _client.upload<Map<String, dynamic>>(
      ApiPaths.uploadVideo,
      form: form,
      onProgress: onProgress,
      decode: (d) => d as Map<String, dynamic>,
    );
    final data = result['data'] is Map
        ? result['data'] as Map<String, dynamic>
        : result;
    return VideoUploadResult(
      url: (data['url'] ?? '').toString(),
      coverUrl: (data['cover_url'] ?? data['coverUrl'] ?? '').toString(),
    );
  }
}

class VideoUploadResult {
  const VideoUploadResult({required this.url, required this.coverUrl});

  final String url;
  final String coverUrl;
}
