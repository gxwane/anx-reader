import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef BookSearchFetcher = Future<BookSearchBridgeResponse> Function({
  required String keyword,
  required int maxResults,
  required int maxSnippets,
  required int? maxCharacters,
  required Duration timeout,
});

class BookSearchBridgeHandlers {
  const BookSearchBridgeHandlers({
    required this.bookId,
    required this.searchBook,
  });

  final int bookId;
  final BookSearchFetcher searchBook;
}

class BookSearchBridgeResponse {
  const BookSearchBridgeResponse({
    required this.results,
    required this.completed,
    required this.duration,
  });

  final List<Map<String, dynamic>> results;
  final bool completed;
  final Duration duration;
}

final bookSearchBridgeProvider =
    StateProvider<BookSearchBridgeHandlers?>((ref) => null);
