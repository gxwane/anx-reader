import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookOpenedFolder extends ConsumerStatefulWidget {
  const BookOpenedFolder({
    super.key,
    required this.books,
    required this.groupName,
  });

  final List<Book> books;
  final String groupName;

  @override
  ConsumerState<BookOpenedFolder> createState() => _BookOpenedFolderState();
}

class _BookOpenedFolderState extends ConsumerState<BookOpenedFolder> {
  bool isEditing = false;
  bool isEditingName = false;
  bool _isDissolving = false;
  bool _dissolveFailed = false;
  List<Book> books = [];
  late TextEditingController _nameController;
  String currentGroupName = "";

  @override
  void initState() {
    super.initState();
    books = widget.books;
    currentGroupName = widget.groupName;
    _nameController = TextEditingController(text: currentGroupName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateGroupName() async {
    if (books.isEmpty) return;

    final groupId = books.first.groupId;
    if (groupId <= 0) return;

    try {
      final group = await ref.read(groupDaoProvider.notifier).getGroup(groupId);
      if (group == null) return;
      final updatedGroup = group.copyWith(name: _nameController.text);
      await ref.read(groupDaoProvider.notifier).updateGroup(updatedGroup);

      setState(() {
        currentGroupName = _nameController.text;
        isEditingName = false;
      });
    } catch (e) {
      // Handle error
      setState(() {
        isEditingName = false;
      });
    }
  }

  Future<void> _dissolveGroup() async {
    if (_isDissolving) return;
    final route = ModalRoute.of(context);
    setState(() {
      _isDissolving = true;
      _dissolveFailed = false;
    });
    try {
      await ref.read(bookListProvider.notifier).dissolveGroup(books);
      _closeDissolvedFolder(route);
    } catch (error) {
      AnxLog.warning('Folder dissolution failed: $error');
      if (mounted) setState(() => _dissolveFailed = true);
    } finally {
      if (mounted) setState(() => _isDissolving = false);
    }
  }

  void _closeDissolvedFolder(ModalRoute<dynamic>? route) {
    if (!mounted || route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  List<Widget> _buildActions(BuildContext context) => [
        if (_dissolveFailed)
          Text(L10n.of(context).commonFailed,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(
          onPressed: _isDissolving ? null : _dissolveGroup,
          child: Text(L10n.of(context).commonDissolve),
        ),
        TextButton(
          onPressed: _isDissolving
              ? null
              : () => setState(() => isEditing = !isEditing),
          child: Text(isEditing
              ? L10n.of(context).commonCancel
              : L10n.of(context).commonEdit),
        ),
      ];

  void _cancelNameEditing() {
    setState(() {
      _nameController.text = currentGroupName;
      isEditingName = false;
    });
  }

  Widget _buildTitleEditor() => Row(
        children: [
          Expanded(
            child: TextField(
              enabled: !_isDissolving,
              controller: _nameController,
              decoration: InputDecoration(border: OutlineInputBorder()),
              autofocus: true,
            ),
          ),
          IconButton(
            icon: Icon(Icons.check),
            onPressed: _isDissolving ? null : _updateGroupName,
          ),
          IconButton(
            icon: Icon(Icons.close),
            onPressed: _isDissolving ? null : _cancelNameEditing,
          ),
        ],
      );

  Widget _buildTitle() {
    if (isEditingName) return _buildTitleEditor();
    return TextButton(
      onPressed:
          _isDissolving ? null : () => setState(() => isEditingName = true),
      child: Text(
        currentGroupName,
        style: TextStyle(fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _removeFromGroup(int index) {
    ref.read(bookListProvider.notifier).removeFromGroup(books[index]);
    books.removeAt(index);
    if (books.isEmpty) Navigator.pop(context);
    setState(() {});
  }

  Widget _buildBookTile(int index) => AbsorbPointer(
        absorbing: _isDissolving,
        child: Stack(
          children: [
            BookItem(book: books[index]),
            isEditing
                ? Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      onPressed:
                          _isDissolving ? null : () => _removeFromGroup(index),
                      icon: const Icon(
                        Icons.remove_circle,
                        size: 30,
                        color: Colors.red,
                      ),
                    ),
                  )
                : Container(),
          ],
        ),
      );

  Widget _buildContent(BuildContext context) => SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: Prefs().bookCoverWidth,
            childAspectRatio: 1 / 2.2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) => _buildBookTile(index),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: _buildTitle(),
        content: _buildContent(context),
        actions: _buildActions(context),
      );
}
