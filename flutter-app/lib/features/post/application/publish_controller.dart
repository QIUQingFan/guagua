import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exceptions.dart';
import '../data/publish_dto.dart';
import '../data/publish_repository.dart';

class PublishFormState {
  const PublishFormState({
    this.title = '',
    this.content = '',
    this.type = 1, 
    this.categoryId,
    this.tags = const [],
    this.localImages = const [],
    this.localVideo,
    this.remoteImages = const [],
    this.remoteVideoUrl,
    this.remoteCoverUrl,
    this.location,
  });

  final String title;
  final String content;
  final int type;
  final int? categoryId;
  final List<String> tags;
  final List<String> localImages;
  final String? localVideo;
  final List<String> remoteImages;
  final String? remoteVideoUrl;
  final String? remoteCoverUrl;
  final String? location;

  bool get isVideo => type == 2;

  int get pendingMediaCount =>
      (isVideo ? (localVideo == null ? 0 : 1) : localImages.length);

  PublishFormState copyWith({
    String? title,
    String? content,
    int? type,
    int? categoryId,
    List<String>? tags,
    List<String>? localImages,
    String? localVideo,
    List<String>? remoteImages,
    String? remoteVideoUrl,
    String? remoteCoverUrl,
    String? location,
  }) {
    return PublishFormState(
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      tags: tags ?? this.tags,
      localImages: localImages ?? this.localImages,
      localVideo: localVideo ?? this.localVideo,
      remoteImages: remoteImages ?? this.remoteImages,
      remoteVideoUrl: remoteVideoUrl ?? this.remoteVideoUrl,
      remoteCoverUrl: remoteCoverUrl ?? this.remoteCoverUrl,
      location: location ?? this.location,
    );
  }

  DraftEntity toDraft() => DraftEntity(
    title: title,
    content: content,
    type: type,
    categoryId: categoryId,
    tags: tags,
    localImages: localImages,
    localVideo: localVideo,
    remoteImages: remoteImages,
    remoteVideoUrl: remoteVideoUrl,
    remoteCoverUrl: remoteCoverUrl,
    location: location,
    updatedAt: DateTime.now(),
  );

  factory PublishFormState.fromDraft(DraftEntity draft) => PublishFormState(
    title: draft.title,
    content: draft.content,
    type: draft.type,
    categoryId: draft.categoryId,
    tags: List<String>.from(draft.tags),
    localImages: List<String>.from(draft.localImages),
    localVideo: draft.localVideo,
    remoteImages: List<String>.from(draft.remoteImages),
    remoteVideoUrl: draft.remoteVideoUrl,
    remoteCoverUrl: draft.remoteCoverUrl,
    location: draft.location,
  );
}

enum PublishStatus { idle, uploading, publishing, success, error }

class PublishState {
  const PublishState({
    this.form = const PublishFormState(),
    this.status = PublishStatus.idle,
    this.uploadProgress = 0,
    this.uploadTotal = 0,
    this.errorCode,
    this.createdPostId,
  });

  final PublishFormState form;
  final PublishStatus status;
  final int uploadProgress;
  final int uploadTotal;
  final String? errorCode;
  final int? createdPostId;

  bool get isBusy =>
      status == PublishStatus.uploading || status == PublishStatus.publishing;

  PublishState copyWith({
    PublishFormState? form,
    PublishStatus? status,
    int? uploadProgress,
    int? uploadTotal,
    String? errorCode,
    int? createdPostId,
    bool clearError = false,
    bool clearCreated = false,
  }) {
    return PublishState(
      form: form ?? this.form,
      status: status ?? this.status,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      createdPostId: clearCreated
          ? null
          : (createdPostId ?? this.createdPostId),
    );
  }
}

class PublishController extends Notifier<PublishState> {
  @override
  PublishState build() {
    Future.microtask(_restoreDraft);
    return const PublishState();
  }

  PublishRepository get _repo => ref.read(publishRepositoryProvider);

  void setTitle(String v) => state = state.copyWith(
    form: state.form.copyWith(title: v),
    clearError: true,
  );
  void setContent(String v) => state = state.copyWith(
    form: state.form.copyWith(content: v),
    clearError: true,
  );
  void setCategoryId(int? id) =>
      state = state.copyWith(form: state.form.copyWith(categoryId: id));
  void setLocation(String? v) =>
      state = state.copyWith(form: state.form.copyWith(location: v));

  void switchType(int type) {
    if (type == state.form.type) return;
    state = state.copyWith(
      form: state.form.copyWith(
        type: type,
        localImages: type == 2 ? const [] : state.form.localImages,
        localVideo: type == 1 ? null : state.form.localVideo,
        remoteImages: type == 2 ? const [] : state.form.remoteImages,
        remoteVideoUrl: type == 1 ? null : state.form.remoteVideoUrl,
        remoteCoverUrl: type == 1 ? null : state.form.remoteCoverUrl,
      ),
      clearError: true,
    );
  }

  void addImages(List<String> paths) {
    if (state.form.isVideo) return;
    final list = [...state.form.localImages, ...paths];
    if (list.length > 9) list.removeRange(9, list.length);
    state = state.copyWith(form: state.form.copyWith(localImages: list));
  }

  void removeImageAt(int index) {
    final list = [...state.form.localImages]..removeAt(index);
    state = state.copyWith(form: state.form.copyWith(localImages: list));
  }

  /// 重排图片
  void reorderImages(int oldIndex, int newIndex) {
    final list = [...state.form.localImages];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(form: state.form.copyWith(localImages: list));
  }

  void setVideo(String? path) {
    state = state.copyWith(
      form: state.form.copyWith(localVideo: path),
      clearError: true,
    );
  }

  void addTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty) return;
    if (state.form.tags.contains(t)) return;
    if (state.form.tags.length >= 10) return;
    state = state.copyWith(
      form: state.form.copyWith(tags: [...state.form.tags, t]),
    );
  }

  void removeTag(String tag) {
    state = state.copyWith(
      form: state.form.copyWith(
        tags: state.form.tags.where((t) => t != tag).toList(),
      ),
    );
  }

  Future<void> _restoreDraft() async {
    final draft = await _repo.loadDraft();
    if (draft != null) {
      state = state.copyWith(form: PublishFormState.fromDraft(draft));
    }
  }

  Future<void> saveDraft() async {
    await _repo.saveDraft(state.form.toDraft());
  }

  Future<void> discardDraft() async {
    await _repo.clearDraft();
    state = const PublishState();
  }

  Future<void> publish() async {
    if (state.isBusy) return;

    final form = state.form;
    final error = _repo.validate(
      title: form.title,
      imageCount: form.isVideo ? 0 : form.localImages.length,
      videoCount: form.isVideo ? (form.localVideo == null ? 0 : 1) : 0,
    );
    if (error != null) {
      state = state.copyWith(status: PublishStatus.error, errorCode: error);
      return;
    }

    try {
      var remoteImages = List<String>.from(form.remoteImages);
      var remoteVideoUrl = form.remoteVideoUrl;
      var remoteCoverUrl = form.remoteCoverUrl;

      final pendingCount = form.pendingMediaCount;
      if (pendingCount > 0) {
        state = state.copyWith(
          status: PublishStatus.uploading,
          uploadProgress: 0,
          uploadTotal: pendingCount,
          clearError: true,
          clearCreated: true,
        );
        if (form.isVideo) {
          final video = File(form.localVideo!);
          final result = await _repo.uploadVideo(video);
          remoteVideoUrl = result.url;
          remoteCoverUrl = result.coverUrl;
        } else {
          final files = form.localImages.map(File.new).toList();
          remoteImages = await _repo.uploadImages(
            files,
            onProgress: (done, total) {
              state = state.copyWith(uploadProgress: done, uploadTotal: total);
            },
          );
        }
      }

      state = state.copyWith(status: PublishStatus.publishing);
      final request = CreatePostRequest(
        title: form.title.trim(),
        content: form.content.trim(),
        type: form.type,
        categoryId: form.categoryId,
        tags: form.tags,
        images: form.isVideo ? const [] : remoteImages,
        videoUrl: form.isVideo ? remoteVideoUrl : null,
        coverUrl: form.isVideo ? remoteCoverUrl : null,
        isDraft: false,
        location: form.location,
      );
      final result = await _repo.create(request);

      await _repo.clearDraft();
      state = state.copyWith(
        status: PublishStatus.success,
        createdPostId: result.id,
      );
    } catch (e) {
      state = state.copyWith(
        status: PublishStatus.error,
        errorCode: e is ApiException ? 'api_error' : 'network_error',
      );
    }
  }

  void reset() {
    state = const PublishState();
    Future.microtask(_restoreDraft);
  }
}

final publishControllerProvider =
    NotifierProvider<PublishController, PublishState>(PublishController.new);

final draftRestoreProbeProvider = FutureProvider<DraftEntity?>((ref) async {
  return ref.watch(publishRepositoryProvider).loadDraft();
});
