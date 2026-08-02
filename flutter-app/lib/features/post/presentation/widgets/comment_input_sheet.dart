import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../shared/extensions/l10n_ext.dart';
import '../../../../shared/providers/toast_controller.dart';
import '../../application/comment_list_controller.dart';

/// 评论输入面板（底部 Modal）。
class CommentInputSheet extends ConsumerStatefulWidget {
  const CommentInputSheet({super.key, required this.postId, this.parentId, this.replyTo});

  final int postId;
  final int? parentId;
  final String? replyTo;

  @override
  ConsumerState<CommentInputSheet> createState() => _CommentInputSheetState();
}

class _CommentInputSheetState extends ConsumerState<CommentInputSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _ctrl.text.trim();
    final l = context.l10n;
    if (content.isEmpty) {
      ref.read(toastControllerProvider).error(l.postCommentRequired);
      return;
    }
    setState(() => _sending = true);
    final ok = await ref.read(commentListProvider(widget.postId).notifier).publish(
          widget.postId,
          content: content,
          parentId: widget.parentId,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      ref.read(toastControllerProvider).success(l.postCommentPublished);
      Navigator.of(context).pop();
    } else {
      ref.read(toastControllerProvider).error(l.commonOperationFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.replyTo != null ? l.postCommentReplyTo(widget.replyTo!) : l.postComment,
                      style: const TextStyle(fontSize: AppTextSize.body, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: l.postCommentPlaceholder,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l.postCommentSend),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
