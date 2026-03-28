/// PDF loading and content extraction service.
///
/// Supports three analysis paths matching OpenClaw's pdf-tool.ts:
///   1. Native Anthropic — send base64 PDF as a document content block.
///   2. Native Google/Gemini — send base64 PDF as inline_data.
///   3. Extraction fallback — extract text + render pages to JPEG images,
///      then send to any vision-capable model.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

final _log = Logger('flutterclaw.pdf_service');

const int _kMaxPdfs = 10;
const int _kMaxBytes = 10 * 1024 * 1024; // 10 MB
const int _kMaxPages = 20;
const double _kPageScale = 1.5; // render scale for extracted images

class PdfLoadResult {
  final Uint8List bytes;
  final String filename;
  final String base64;

  PdfLoadResult({required this.bytes, required this.filename})
      : base64 = base64Encode(bytes);
}

class PdfExtraction {
  /// Plain text extracted from all pages (may be empty for scanned PDFs).
  final String text;

  /// Page images rendered as JPEG base64 strings (for vision fallback).
  final List<String> pageImages;

  const PdfExtraction({required this.text, required this.pageImages});
}

class PdfService {
  final Dio _dio = Dio();

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Load a PDF from a local path or HTTP(S) URL.
  /// Returns null and logs a warning on failure.
  Future<PdfLoadResult?> loadPdf(String source) async {
    try {
      if (source.startsWith('http://') || source.startsWith('https://')) {
        return await _loadFromUrl(source);
      }
      return await _loadFromFile(source);
    } catch (e) {
      _log.warning('Failed to load PDF "$source": $e');
      return null;
    }
  }

  Future<PdfLoadResult> _loadFromUrl(String url) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    if (response.data == null) throw Exception('Empty response from $url');
    final bytes = Uint8List.fromList(response.data!);
    if (bytes.length > _kMaxBytes) {
      throw Exception(
        'PDF too large: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB '
        '(max ${_kMaxBytes ~/ 1024 ~/ 1024} MB)',
      );
    }
    final filename = Uri.parse(url).pathSegments.lastOrNull ?? 'document.pdf';
    return PdfLoadResult(bytes: bytes, filename: filename);
  }

  Future<PdfLoadResult> _loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) throw Exception('File not found: $path');
    final bytes = await file.readAsBytes();
    if (bytes.length > _kMaxBytes) {
      throw Exception(
        'PDF too large: ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
      );
    }
    return PdfLoadResult(bytes: bytes, filename: p.basename(path));
  }

  // ---------------------------------------------------------------------------
  // Content extraction (fallback path)
  // ---------------------------------------------------------------------------

  /// Extract text and render pages to JPEG images from a loaded PDF.
  /// [pageRange] is an optional 1-based list of page numbers to process.
  Future<PdfExtraction> extractContent(
    PdfLoadResult pdf, {
    List<int>? pageRange,
  }) async {
    // Write bytes to a temp file so pdfx can open it
    final tmp = await getTemporaryDirectory();
    final tmpPath = p.join(
      tmp.path,
      'fc_pdf_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    final tmpFile = File(tmpPath);
    await tmpFile.writeAsBytes(pdf.bytes);

    try {
      final doc = await PdfDocument.openFile(tmpPath);
      final pageCount = doc.pagesCount;
      final effectiveRange = _resolvePageRange(pageRange, pageCount);

      final textBuf = StringBuffer();
      final images = <String>[];

      for (final pageNum in effectiveRange) {
        if (pageNum < 1 || pageNum > pageCount) continue;
        final page = await doc.getPage(pageNum);
        try {
          final rendered = await page.render(
            width: page.width * _kPageScale,
            height: page.height * _kPageScale,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#ffffff',
          );
          if (rendered?.bytes != null) {
            images.add(base64Encode(rendered!.bytes));
          }
        } finally {
          await page.close();
        }
      }

      await doc.close();
      return PdfExtraction(text: textBuf.toString().trim(), pageImages: images);
    } finally {
      await tmpFile.delete().catchError((_) => tmpFile);
    }
  }

  List<int> _resolvePageRange(List<int>? range, int pageCount) {
    if (range != null && range.isNotEmpty) {
      return range.where((n) => n >= 1 && n <= pageCount).toList();
    }
    final last = pageCount.clamp(1, _kMaxPages);
    return List.generate(last, (i) => i + 1);
  }

  // ---------------------------------------------------------------------------
  // Provider detection helpers
  // ---------------------------------------------------------------------------

  static bool supportsNativePdf(String provider) =>
      provider == 'anthropic' || provider == 'google';

  // ---------------------------------------------------------------------------
  // Build content blocks for providers
  // ---------------------------------------------------------------------------

  /// Build an Anthropic-compatible document content block from a PDF.
  /// Returns a list with one `{type:"document", source:{...}}` block.
  static List<Map<String, dynamic>> buildAnthropicPdfBlocks(
    List<PdfLoadResult> pdfs,
    String prompt,
  ) {
    return [
      for (final pdf in pdfs)
        {
          'type': 'document',
          'source': {
            'type': 'base64',
            'media_type': 'application/pdf',
            'data': pdf.base64,
          },
          'title': pdf.filename,
        },
      {'type': 'text', 'text': prompt},
    ];
  }

  /// Build a Google/Gemini-compatible inline_data block.
  static List<Map<String, dynamic>> buildGeminiPdfBlocks(
    List<PdfLoadResult> pdfs,
    String prompt,
  ) {
    return [
      for (final pdf in pdfs)
        {
          'inline_data': {
            'mime_type': 'application/pdf',
            'data': pdf.base64,
          },
        },
      {'text': prompt},
    ];
  }

  /// Build vision-compatible content blocks from extracted text + page images.
  static List<Map<String, dynamic>> buildExtractionBlocks(
    List<PdfExtraction> extractions,
    String prompt,
  ) {
    final blocks = <Map<String, dynamic>>[];
    for (var i = 0; i < extractions.length; i++) {
      final e = extractions[i];
      final label = extractions.length > 1 ? '[PDF ${i + 1} text]\n' : '[PDF text]\n';
      if (e.text.isNotEmpty) {
        blocks.add({'type': 'text', 'text': '$label${e.text}'});
      }
      for (final img in e.pageImages) {
        blocks.add({
          'type': 'image',
          'data': img,
          'mimeType': 'image/jpeg',
        });
      }
    }
    blocks.add({'type': 'text', 'text': prompt});
    return blocks;
  }

  // ---------------------------------------------------------------------------
  // Limits
  // ---------------------------------------------------------------------------

  static int get maxPdfs => _kMaxPdfs;
  static int get maxBytes => _kMaxBytes;
  static int get maxPages => _kMaxPages;
}

/// Parse a page range string like "1-5", "1,3,5-7" into a sorted list of
/// 1-based page numbers, capped at [maxPages].
List<int> parsePdfPageRange(String range, {int maxPages = _kMaxPages}) {
  final pages = <int>{};
  for (final part in range.split(',')) {
    final trimmed = part.trim();
    if (trimmed.contains('-')) {
      final bounds = trimmed.split('-');
      if (bounds.length == 2) {
        final from = int.tryParse(bounds[0].trim());
        final to = int.tryParse(bounds[1].trim());
        if (from != null && to != null) {
          for (var n = from; n <= to && n <= maxPages; n++) {
            pages.add(n);
          }
        }
      }
    } else {
      final n = int.tryParse(trimmed);
      if (n != null && n <= maxPages) pages.add(n);
    }
  }
  final sorted = pages.toList()..sort();
  return sorted;
}
