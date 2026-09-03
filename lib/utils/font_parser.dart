import 'dart:io';
import 'dart:typed_data';

class FontMetadata {
  final String familyName;
  final String? postscriptName;
  final String styleOrSubfamily;
  final int fileSize;
  final String? fullName;

  const FontMetadata({
    required this.familyName,
    this.postscriptName,
    this.styleOrSubfamily = 'Regular',
    required this.fileSize,
    this.fullName,
  });

  @override
  String toString() =>
      'FontMetadata(family: $familyName, ps: $postscriptName, style: $styleOrSubfamily, size: $fileSize)';
}

/// Parses font metadata using random-access I/O (reads < 64KB without loading entire file).
/// Supports TTF, OTF, and TTC font collections.
Future<FontMetadata?> parseFontMetadata(File file) async {
  if (!await file.exists()) return null;

  RandomAccessFile? raf;
  try {
    final fileSize = await file.length();
    if (fileSize < 12) return null;

    raf = await file.open(mode: FileMode.read);
    final headerBytes = await raf.read(12);
    if (headerBytes.length < 12) return null;

    final header = ByteData.sublistView(headerBytes);
    final magic = header.getUint32(0);

    int sfntOffset = 0;
    // TTC header ('ttcf' = 0x74746366)
    if (magic == 0x74746366) {
      if (fileSize < 16) return null;
      final numFontsBytes = await raf.read(4);
      final numFonts = ByteData.sublistView(numFontsBytes).getUint32(0);
      if (numFonts == 0) return null;

      // Read offset of first font in collection
      final firstOffsetBytes = await raf.read(4);
      sfntOffset = ByteData.sublistView(firstOffsetBytes).getUint32(0);

      await raf.setPosition(sfntOffset);
      final subHeaderBytes = await raf.read(12);
      if (subHeaderBytes.length < 12) return null;
      final subHeader = ByteData.sublistView(subHeaderBytes);
      final subMagic = subHeader.getUint32(0);
      if (!_isValidSfntMagic(subMagic)) return null;

      final numTables = subHeader.getUint16(4);
      return await _readNameTable(raf, sfntOffset + 12, numTables, fileSize);
    } else if (_isValidSfntMagic(magic)) {
      final numTables = header.getUint16(4);
      return await _readNameTable(raf, 12, numTables, fileSize);
    } else {
      return null;
    }
  } catch (_) {
    return null;
  } finally {
    await raf?.close();
  }
}

bool _isValidSfntMagic(int magic) {
  // 0x00010000 (TrueType 1.0), 'OTTO' (0x4F54544F), 'true' (0x74727565), 'typ1' (0x74797031)
  return magic == 0x00010000 ||
      magic == 0x4F54544F ||
      magic == 0x74727565 ||
      magic == 0x74797031;
}

Future<FontMetadata?> _readNameTable(
  RandomAccessFile raf,
  int tableDirOffset,
  int numTables,
  int fileSize,
) async {
  await raf.setPosition(tableDirOffset);
  final tableDirBytes = await raf.read(numTables * 16);
  if (tableDirBytes.length < numTables * 16) return null;

  final tableDir = ByteData.sublistView(tableDirBytes);
  int? nameTableOffset;
  int? nameTableLength;

  for (int i = 0; i < numTables; i++) {
    final entryOffset = i * 16;
    final tag = String.fromCharCodes(
      tableDirBytes.sublist(entryOffset, entryOffset + 4),
    );
    if (tag == 'name') {
      nameTableOffset = tableDir.getUint32(entryOffset + 8);
      nameTableLength = tableDir.getUint32(entryOffset + 12);
      break;
    }
  }

  if (nameTableOffset == null ||
      nameTableLength == null ||
      nameTableLength == 0 ||
      nameTableLength > 256 * 1024 ||
      nameTableOffset + nameTableLength > fileSize) {
    return null;
  }

  await raf.setPosition(nameTableOffset);
  final nameBytes = await raf.read(nameTableLength);
  if (nameBytes.length < nameTableLength) return null;

  return _parseNameBytes(nameBytes, fileSize);
}

FontMetadata? _parseNameBytes(Uint8List nameBytes, int fileSize) {
  if (nameBytes.length < 6) return null;
  final data = ByteData.sublistView(nameBytes);

  final count = data.getUint16(2);
  final stringOffset = data.getUint16(4);

  String? familyZh;
  String? familyEn;
  String? familyFallback;
  String? styleZh;
  String? styleEn;
  String? styleFallback;
  String? fullName;
  String? postscriptName;

  for (int i = 0; i < count; i++) {
    final recordOffset = 6 + i * 12;
    if (recordOffset + 12 > nameBytes.length) break;

    final platformID = data.getUint16(recordOffset);
    final languageID = data.getUint16(recordOffset + 4);
    final nameID = data.getUint16(recordOffset + 6);
    final length = data.getUint16(recordOffset + 8);
    final offset = data.getUint16(recordOffset + 10);

    final strPos = stringOffset + offset;
    if (strPos + length > nameBytes.length) continue;

    String value = '';
    if (platformID == 3 || platformID == 0) {
      // UTF-16BE encoding
      final chars = <int>[];
      for (int j = 0; j < length; j += 2) {
        if (strPos + j + 1 < nameBytes.length) {
          chars.add((nameBytes[strPos + j] << 8) | nameBytes[strPos + j + 1]);
        }
      }
      value = String.fromCharCodes(chars).trim();
    } else {
      // ASCII / MacRoman encoding
      value = String.fromCharCodes(nameBytes.sublist(strPos, strPos + length)).trim();
    }

    if (value.isEmpty) continue;

    // nameID 1: Family Name, 16: Preferred Family
    if (nameID == 1 || nameID == 16) {
      if (languageID == 2052 || languageID == 1028) {
        familyZh ??= value;
      } else if (languageID == 1033) {
        familyEn ??= value;
      } else {
        familyFallback ??= value;
      }
    } else if (nameID == 2 || nameID == 17) {
      // Subfamily / Style
      if (languageID == 2052 || languageID == 1028) {
        styleZh ??= value;
      } else if (languageID == 1033) {
        styleEn ??= value;
      } else {
        styleFallback ??= value;
      }
    } else if (nameID == 4) {
      // Full Name
      fullName ??= value;
    } else if (nameID == 6) {
      // PostScript Name
      postscriptName ??= value;
    }
  }

  final finalFamily = familyZh ?? familyEn ?? familyFallback ?? fullName;
  if (finalFamily == null || finalFamily.isEmpty) return null;

  return FontMetadata(
    familyName: finalFamily,
    postscriptName: postscriptName,
    styleOrSubfamily: styleZh ?? styleEn ?? styleFallback ?? 'Regular',
    fileSize: fileSize,
    fullName: fullName,
  );
}

/// Measure total bytes read during metadata parsing to prove random-access efficiency.
Future<int> measureParserReadBytes(File file) async {
  if (!await file.exists()) return 0;
  RandomAccessFile? raf;
  int bytesRead = 0;
  try {
    raf = await file.open(mode: FileMode.read);
    final headerBytes = await raf.read(12);
    bytesRead += headerBytes.length;
    if (headerBytes.length < 12) return bytesRead;

    final header = ByteData.sublistView(headerBytes);
    final magic = header.getUint32(0);
    int numTables = 0;
    int tableDirOffset = 12;

    if (magic == 0x74746366) {
      final numBytes = await raf.read(4);
      bytesRead += numBytes.length;
      final firstOffsetBytes = await raf.read(4);
      bytesRead += firstOffsetBytes.length;
      final sfntOffset = ByteData.sublistView(firstOffsetBytes).getUint32(0);
      await raf.setPosition(sfntOffset);
      final subHeaderBytes = await raf.read(12);
      bytesRead += subHeaderBytes.length;
      numTables = ByteData.sublistView(subHeaderBytes).getUint16(4);
      tableDirOffset = sfntOffset + 12;
    } else if (_isValidSfntMagic(magic)) {
      numTables = header.getUint16(4);
    } else {
      return bytesRead;
    }

    await raf.setPosition(tableDirOffset);
    final tableDirBytes = await raf.read(numTables * 16);
    bytesRead += tableDirBytes.length;
    final tableDir = ByteData.sublistView(tableDirBytes);

    for (int i = 0; i < numTables; i++) {
      final entryOffset = i * 16;
      final tag = String.fromCharCodes(
        tableDirBytes.sublist(entryOffset, entryOffset + 4),
      );
      if (tag == 'name') {
        final nameOffset = tableDir.getUint32(entryOffset + 8);
        final nameLength = tableDir.getUint32(entryOffset + 12);
        await raf.setPosition(nameOffset);
        final nameBytes = await raf.read(nameLength);
        bytesRead += nameBytes.length;
        break;
      }
    }
    return bytesRead;
  } finally {
    await raf?.close();
  }
}

/// Synchronous backward-compatible helper with random-access seek (< 64KB read).
String getFontNameFromFile(File file) {
  try {
    final raf = file.openSync(mode: FileMode.read);
    try {
      final fileSize = file.lengthSync();
      final headerBytes = raf.readSync(12);
      if (headerBytes.length < 12) return _fallbackName(file);

      final header = ByteData.sublistView(headerBytes);
      final magic = header.getUint32(0);
      if (!_isValidSfntMagic(magic) && magic != 0x74746366) {
        return _fallbackName(file);
      }

      int numTables = 0;
      int tableDirOffset = 12;
      if (magic == 0x74746366) {
        raf.readSync(4);
        final firstOffsetBytes = raf.readSync(4);
        final sfntOffset = ByteData.sublistView(firstOffsetBytes).getUint32(0);
        raf.setPositionSync(sfntOffset);
        final subHeaderBytes = raf.readSync(12);
        numTables = ByteData.sublistView(subHeaderBytes).getUint16(4);
        tableDirOffset = sfntOffset + 12;
      } else {
        numTables = header.getUint16(4);
      }

      raf.setPositionSync(tableDirOffset);
      final tableDirBytes = raf.readSync(numTables * 16);
      final tableDir = ByteData.sublistView(tableDirBytes);

      int? nameOffset;
      int? nameLength;
      for (int i = 0; i < numTables; i++) {
        final entryOffset = i * 16;
        final tag = String.fromCharCodes(
          tableDirBytes.sublist(entryOffset, entryOffset + 4),
        );
        if (tag == 'name') {
          nameOffset = tableDir.getUint32(entryOffset + 8);
          nameLength = tableDir.getUint32(entryOffset + 12);
          break;
        }
      }

      if (nameOffset == null ||
          nameLength == null ||
          nameLength == 0 ||
          nameLength > 256 * 1024 ||
          nameOffset + nameLength > fileSize) {
        return _fallbackName(file);
      }
      raf.setPositionSync(nameOffset);
      final nameBytes = raf.readSync(nameLength);
      final meta = _parseNameBytes(nameBytes, fileSize);
      return meta?.familyName ?? _fallbackName(file);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return _fallbackName(file);
  }
}

String _fallbackName(File file) {
  return file.path.split(Platform.pathSeparator).last.split('.').first;
}
