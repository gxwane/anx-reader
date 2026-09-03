import 'package:anx_reader/enums/reading_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/notes/markdown_notes_formatter.dart';
import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownNotesFormatter - sanitizeFileName Tests', () {
    test('standard title and author', () {
      final name = MarkdownNotesFormatter.sanitizeFileName('人件 (第二版)', author: '汤姆·狄马可');
      expect(name, equals('人件 (第二版) - 汤姆·狄马可.md'));
    });

    test('author empty or null', () {
      final name1 = MarkdownNotesFormatter.sanitizeFileName('设计模式', author: '');
      final name2 = MarkdownNotesFormatter.sanitizeFileName('设计模式', author: null);
      expect(name1, equals('设计模式.md'));
      expect(name2, equals('设计模式.md'));
    });

    test('replaces invalid characters with underscores', () {
      final name = MarkdownNotesFormatter.sanitizeFileName(
        'C++: The "Complete" Guide <Edition 3>? / Yes | No * Maybe \\ Wow',
        author: 'Bjarne: Stroustrup',
      );
      expect(name.contains(':'), isFalse);
      expect(name.contains('"'), isFalse);
      expect(name.contains('<'), isFalse);
      expect(name.contains('>'), isFalse);
      expect(name.contains('?'), isFalse);
      expect(name.contains('/'), isFalse);
      expect(name.contains('|'), isFalse);
      expect(name.contains('*'), isFalse);
      expect(name.contains('\\'), isFalse);
      expect(name.endsWith('.md'), isTrue);
    });

    test('strips trailing dots and spaces', () {
      final name = MarkdownNotesFormatter.sanitizeFileName('Book Title...   ', author: 'Author .  ');
      expect(name, equals('Book Title - Author.md'));
    });

    test('handles Windows reserved device names safely', () {
      final nameCon = MarkdownNotesFormatter.sanitizeFileName('CON');
      final nameNul = MarkdownNotesFormatter.sanitizeFileName('NUL');
      final nameAux = MarkdownNotesFormatter.sanitizeFileName('aux');

      expect(nameCon, equals('CON_book.md'));
      expect(nameNul, equals('NUL_book.md'));
      expect(nameAux, equals('aux_book.md'));
    });

    test('handles empty title and author gracefully', () {
      final name = MarkdownNotesFormatter.sanitizeFileName('', author: '');
      expect(name, equals('untitled.md'));
    });
  });

  group('MarkdownNotesFormatter - formatBookNotesToMarkdown Tests', () {
    final testBook = Book(
      id: 101,
      title: '人件: 思考"人性化"团队 (第二版)',
      coverPath: 'covers/101.jpg',
      filePath: 'books/peopleware.epub',
      lastReadPosition: 'epubcfi(/6/2!/4/1:0)',
      readingPercentage: 0.654,
      author: '汤姆·狄马可 & 蒂莫西·利斯特',
      isDeleted: false,
      rating: 5.0,
      createTime: DateTime.utc(2026, 1, 1),
      updateTime: DateTime.utc(2026, 9, 3, 1, 0, 0),
      status: ReadingStatus.reading,
      md5: 'dfa17eccbc4aff215996d014488b0fc4',
    );

    test('generates valid YAML frontmatter with json-encoded special characters', () {
      final notes = [
        BookNote(
          id: 1,
          bookId: 101,
          content: '大多数软件开发问题本质上不是技术问题，而是社会学问题。',
          cfi: 'epubcfi(/6/2!/4/2:0)',
          chapter: '第一章 此时此刻',
          type: 'highlight',
          color: 'F1D43B',
          readerNote: '核心论点，管理者需要重视团队凝聚力。',
          createTime: DateTime.utc(2026, 9, 3, 1, 10, 0),
          updateTime: DateTime.utc(2026, 9, 3, 1, 15, 0),
          isDeleted: false,
        ),
        BookNote(
          id: 2,
          bookId: 101,
          content: '催促人们加班并不能产生更高质量的软件。',
          cfi: 'epubcfi(/6/2!/4/10:0)',
          chapter: '第一章 此时此刻',
          type: 'underline',
          color: 'FF0000',
          readerNote: null,
          createTime: DateTime.utc(2026, 9, 3, 1, 20, 0),
          updateTime: DateTime.utc(2026, 9, 3, 1, 22, 0),
          isDeleted: false,
        ),
        BookNote(
          id: 3,
          bookId: 101,
          content: '西班牙式大餐的隐喻：催熟不会带来美味。',
          cfi: 'epubcfi(/6/4!/4/2:0)',
          chapter: '第二章 奶酪与品质',
          type: 'highlight',
          color: '00FF00',
          readerNote: '非常形象的隐喻。',
          createTime: DateTime.utc(2026, 9, 3, 1, 30, 0),
          updateTime: DateTime.utc(2026, 9, 3, 1, 35, 0),
          isDeleted: false,
        ),
      ];

      final markdown = MarkdownNotesFormatter.formatBookNotesToMarkdown(
        testBook,
        notes,
        exportedAt: DateTime.utc(2026, 9, 3, 2, 0, 0),
      );

      // Verify Frontmatter
      expect(markdown.startsWith('---\n'), isTrue);
      expect(markdown.contains('type: "book-note"'), isTrue);
      expect(markdown.contains('title: "人件: 思考\\"人性化\\"团队 (第二版)"'), isTrue);
      expect(markdown.contains('author: "汤姆·狄马可 & 蒂莫西·利斯特"'), isTrue);
      expect(markdown.contains('book_id: 101'), isTrue);
      expect(markdown.contains('file_md5: "dfa17eccbc4aff215996d014488b0fc4"'), isTrue);
      expect(markdown.contains('reading_status: "reading"'), isTrue);
      expect(markdown.contains('reading_percentage: 65.4\n'), isTrue);
      expect(markdown.contains('total_notes: 3'), isTrue);
      expect(markdown.contains('tags:\n  - anx-reader\n  - book-notes'), isTrue);

      // Verify Body Structure
      expect(markdown.contains('# 人件: 思考"人性化"团队 (第二版)'), isTrue);
      expect(markdown.contains('## 第一章 此时此刻'), isTrue);
      expect(markdown.contains('> 大多数软件开发问题本质上不是技术问题，而是社会学问题。'), isTrue);
      expect(markdown.contains('- **批注**：核心论点，管理者需要重视团队凝聚力。'), isTrue);
      expect(markdown.contains('类型：划线高亮 ｜ 颜色：#F1D43B'), isTrue);
      expect(markdown.contains('## 第二章 奶酪与品质'), isTrue);
    });

    test('aggregates non-contiguous notes of identical chapters together without duplicate headings', () {
      final nonContiguousNotes = [
        BookNote(
          id: 1,
          bookId: 101,
          content: 'Ch1 Note A',
          cfi: 'epubcfi(/6/2!/4/1:0)',
          chapter: '第一章 此时此刻',
          type: 'highlight',
          color: 'F1D43B',
          createTime: DateTime.utc(2026, 9, 3, 1, 0, 0),
          updateTime: DateTime.utc(2026, 9, 3, 1, 0, 0),
          isDeleted: false,
        ),
        BookNote(
          id: 2,
          bookId: 101,
          content: 'Ch2 Note',
          cfi: 'epubcfi(/6/4!/4/1:0)',
          chapter: '第二章 奶酪与品质',
          type: 'highlight',
          color: 'F1D43B',
          createTime: DateTime.utc(2026, 9, 3, 2, 0, 0),
          updateTime: DateTime.utc(2026, 9, 3, 2, 0, 0),
          isDeleted: false,
        ),
        BookNote(
          id: 3,
          bookId: 101,
          content: 'Ch1 Note B (Created later)',
          cfi: 'epubcfi(/6/2!/4/5:0)',
          chapter: '第一章 此时此刻',
          type: 'highlight',
          color: 'F1D43B',
          createTime: DateTime.utc(2026, 9, 3, 3, 0, 0),
          updateTime: DateTime.utc(2026, 9, 3, 3, 0, 0),
          isDeleted: false,
        ),
      ];

      final markdown = MarkdownNotesFormatter.formatBookNotesToMarkdown(testBook, nonContiguousNotes);

      // Verify '## 第一章 此时此刻' appears exactly once
      final matches = RegExp(r'## 第一章 此时此刻').allMatches(markdown);
      expect(matches.length, equals(1));

      // Both Ch1 notes must appear in markdown
      expect(markdown.contains('> Ch1 Note A'), isTrue);
      expect(markdown.contains('> Ch1 Note B (Created later)'), isTrue);
    });

    test('indents multiline reader notes properly', () {
      final notes = [
        BookNote(
          id: 1,
          bookId: 101,
          content: 'Quote line',
          cfi: 'epubcfi(/6/2!/4/1:0)',
          chapter: '第一章',
          type: 'highlight',
          color: 'F1D43B',
          readerNote: '第一行思考\n第二行延伸\n第三行总结',
          createTime: DateTime.utc(2026, 9, 3, 1, 0, 0),
          updateTime: DateTime.utc(2026, 9, 3, 1, 0, 0),
          isDeleted: false,
        ),
      ];

      final markdown = MarkdownNotesFormatter.formatBookNotesToMarkdown(testBook, notes);
      expect(markdown.contains('- **批注**：第一行思考\n  第二行延伸\n  第三行总结'), isTrue);
    });

    test('handles emoji and surrogate pair truncation safely in sanitizeFileName', () {
      final longTitleWithEmoji = '📚' * 130;
      final fileName = MarkdownNotesFormatter.sanitizeFileName(longTitleWithEmoji);
      expect(fileName.endsWith('.md'), isTrue);
      // Safe characters length should be 120
      final baseName = fileName.replaceAll('.md', '');
      expect(baseName.characters.length, equals(120));
    });

    test('handles empty notes gracefully', () {
      final markdown = MarkdownNotesFormatter.formatBookNotesToMarkdown(testBook, []);
      expect(markdown.contains('total_notes: 0'), isTrue);
      expect(markdown.contains('*暂无划线或批注笔记*'), isTrue);
    });
  });
}
