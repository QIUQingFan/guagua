import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

class PublishMediaGrid extends StatelessWidget {
  const PublishMediaGrid({
    super.key,
    required this.isVideo,
    required this.images,
    this.video,
    required this.onAddImages,
    required this.onPickVideo,
    required this.onRemoveImage,
    required this.onReorderImages,
  });

  final bool isVideo;
  final List<String> images;
  final String? video;
  final VoidCallback onAddImages;
  final VoidCallback onPickVideo;
  final void Function(int index) onRemoveImage;
  final void Function(int oldIndex, int newIndex) onReorderImages;

  @override
  Widget build(BuildContext context) {
    if (isVideo) return _videoPicker(context);
    return _imageGrid(context);
  }

  Widget _imageGrid(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canAdd = images.length < 9;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < images.length; i++)
          _MediaTile(
            key: ValueKey('img_$i'),
            path: images[i],
            index: i,
            onRemove: () => onRemoveImage(i),
          ),
        if (canAdd)
          _AddTile(
            icon: Icons.add_photo_alternate_outlined,
            onTap: onAddImages,
            color: colors.surfaceContainerHighest,
          ),
      ],
    );
  }

  Widget _videoPicker(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (video == null) {
      return _AddTile(
        icon: Icons.video_call_outlined,
        onTap: onPickVideo,
        color: colors.surfaceContainerHighest,
        wide: true,
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.image),
          child: SizedBox(
            width: double.infinity,
            height: 180,
            child: Image.file(File(video!), fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: _RemoveButton(onTap: () => onPickVideo()),
        ),
        Positioned(
          bottom: AppSpacing.sm,
          left: AppSpacing.sm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill, color: Colors.white, size: 16),
                SizedBox(width: 4),
                Text('视频', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    super.key,
    required this.path,
    required this.index,
    required this.onRemove,
  });

  final String path;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Image.file(File(path), fit: BoxFit.cover),
          ),
          Positioned(top: 4, right: 4, child: _RemoveButton(onTap: onRemove)),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.onTap,
    required this.color,
    this.wide = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = wide ? const Size(double.infinity, 180) : const Size(100, 100);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.image),
          border: Border.all(
            color: colors.outline.withValues(alpha: 0.2),
            width: 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: colors.outline),
            const SizedBox(height: 4),
            Text(
              wide ? '添加视频' : '',
              style: TextStyle(fontSize: 12, color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}
