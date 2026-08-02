import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../shared/providers/core_providers.dart';
import 'post_api.dart';
import 'post_repository.dart' show postApiProvider;
import 'publish_dto.dart';
import 'upload_api.dart';

class PublishRepository {
  PublishRepository({
    required UploadApi uploadApi,
    required PostApi postApi,
    required Future<String?> Function() readDraft,
    required Future<void> Function(String) writeDraft,
    required Future<void> Function() clearDraft,
  }) : _upload = uploadApi,
       _post = postApi,
       _readDraft = readDraft,
       _writeDraft = writeDraft,
       _clearDraft = clearDraft;

  final UploadApi _upload;
  final PostApi _post;
  final Future<String?> Function() _readDraft;
  final Future<void> Function(String) _writeDraft;
  final Future<void> Function() _clearDraft;

  Future<DraftEntity?> loadDraft() async {
    try {
      final raw = await _readDraft();
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final draft = DraftEntity.fromJson(json);
      return draft.isEmpty ? null : draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(DraftEntity draft) async {
    if (draft.isEmpty) {
      await clearDraft();
      return;
    }
    final updated = draft.copyWith(updatedAt: DateTime.now());
    await _writeDraft(jsonEncode(updated.toJson()));
  }

  Future<void> clearDraft() => _clearDraft();

  Future<String> uploadImage(
    File file, {
    void Function(int sent, int total)? onProgress,
  }) => _upload.uploadImage(file, onProgress: onProgress);

  Future<List<String>> uploadImages(
    List<File> files, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <String>[];
    for (var i = 0; i < files.length; i++) {
      final url = await _upload.uploadImage(files[i]);
      results.add(url);
      onProgress?.call(i + 1, files.length);
    }
    return results;
  }

  Future<VideoUploadResult> uploadVideo(
    File file, {
    void Function(int sent, int total)? onProgress,
  }) => _upload.uploadVideo(file, onProgress: onProgress);

  Future<PublishResultEntity> create(CreatePostRequest request) async {
    final dto = await _post.create(request.toJson());
    return PublishResultEntity.fromDto(dto);
  }

  Future<PublishResultEntity> update(int id, CreatePostRequest request) async {
    final dto = await _post.update(id, request.toJson());
    return PublishResultEntity.fromDto(dto);
  }

  String? validate({
    required String title,
    required int imageCount,
    required int videoCount,
  }) {
    if (title.trim().isEmpty) return 'need_title';
    if (imageCount == 0 && videoCount == 0) return 'need_media';
    return null;
  }
}

final uploadApiProvider = Provider<UploadApi>(
  (ref) => UploadApi(ref.watch(dioClientProvider)),
);

final publishRepositoryProvider = Provider<PublishRepository>((ref) {
  final storage = ref.watch(sharedPrefsStorageProvider);
  return PublishRepository(
    uploadApi: ref.watch(uploadApiProvider),
    postApi: ref.watch(postApiProvider),
    readDraft: () async => storage?.getString(StorageKeys.publishDraft),
    writeDraft: (value) async =>
        storage?.setString(StorageKeys.publishDraft, value),
    clearDraft: () async => storage?.remove(StorageKeys.publishDraft),
  );
});

String publishErrorCode(Object error) {
  if (error is ApiException) {
    if (error.isUnauthorized) return 'unauthorized';
    if (error.code >= 500) return 'server_error';
    return 'api_error';
  }
  return 'network_error';
}
