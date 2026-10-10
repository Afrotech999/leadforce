import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';

import 'phone.dart';
import 'repository.dart';

/// One row on the way in, from a CSV cell or a phone-book entry.
typedef ImportRow = ({String? name, String? phone, String? source});

class ImportResult {
  const ImportResult({
    required this.rows,
    required this.imported,
    required this.duplicates,
    required this.needsReview,
    required this.batchesCreated,
    this.error,
  });

  final int rows;
  final int imported;
  final int duplicates;
  final int needsReview;
  final int batchesCreated;
  final String? error;

  bool get failed => error != null;

  static ImportResult failure(String message) => ImportResult(
    rows: 0,
    imported: 0,
    duplicates: 0,
    needsReview: 0,
    batchesCreated: 0,
    error: message,
  );
}

/// CSV import (spec 6).
///
/// Header matching is deliberately loose — the source sheets came from four different
/// scrapes and none of them agree on column names. Anything that cannot be normalized
/// goes to Needs review rather than being dropped.
Future<ImportResult> importCsv(Repo repo, File file) async {
  String raw;
  try {
    raw = await file.readAsString(encoding: utf8);
  } on FileSystemException catch (e) {
    return ImportResult.failure('Could not read the file: ${e.message}');
  } on FormatException {
    // Some exports are Windows-1252; latin1 never throws and keeps the digits intact.
    try {
      raw = await file.readAsString(encoding: latin1);
    } catch (e) {
      return ImportResult.failure('Could not decode the file as text.');
    }
  }

  final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // fieldDelimiter left null so the decoder auto-detects ',' vs ';' — the four
  // source exports do not agree on it.
  final table = const CsvDecoder(skipEmptyLines: true).convert(normalized);

  if (table.isEmpty) return ImportResult.failure('The file is empty.');

  final header = table.first
      .map((c) => c.toString().trim().toLowerCase())
      .toList();
  final mapping = _resolveColumns(header);

  // If no header was recognised, the first row is data, and we guess columns by content.
  final startRow = mapping.hasHeader ? 1 : 0;
  final resolved = mapping.hasHeader ? mapping : _guessFromData(table);

  if (resolved.phone < 0) {
    return ImportResult.failure(
      'No phone column found. Expected a column named phone, mobile, number or tel.',
    );
  }

  final rows = <ImportRow>[];
  for (var i = startRow; i < table.length; i++) {
    final row = table[i];
    String? cell(int index) {
      if (index < 0 || index >= row.length) return null;
      final v = row[index]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    rows.add((
      name: cell(resolved.name),
      phone: cell(resolved.phone),
      source: cell(resolved.source),
    ));
  }

  return importRows(repo, rows);
}

/// The one place rows become contacts, whatever they came from.
///
/// Normalizes, deduplicates against what is already stored, sends anything
/// un-normalizable to Needs review rather than dropping it, then rebuilds the
/// batches. Both the CSV importer and the phone-book importer end up here, so the
/// two can never drift apart.
Future<ImportResult> importRows(Repo repo, List<ImportRow> rows) async {
  var created = 0;
  var duplicates = 0;
  var review = 0;
  var seen = 0;

  // One transaction for the whole import: thousands of individual ones would be
  // thousands of fsyncs.
  await repo.db.transaction((txn) async {
    for (final row in rows) {
      if (row.phone == null && row.name == null) continue;
      seen++;

      final e164 = normalizePhone(row.phone);
      if (e164 == null) {
        review++;
        await repo.addNeedsReview(
          name: row.name,
          phone: row.phone,
          source: row.source,
          reason: rejectionReason(row.phone),
          txn: txn,
        );
        continue;
      }

      final isNew = await repo.upsertContact(
        e164: e164,
        name: row.name,
        source: row.source,
        txn: txn,
      );
      if (isNew) {
        created++;
      } else {
        duplicates++;
      }
    }
  });

  return ImportResult(
    rows: seen,
    imported: created,
    duplicates: duplicates,
    needsReview: review,
    batchesCreated: await repo.generateBatches(),
  );
}

class _Columns {
  const _Columns(this.phone, this.name, this.source, this.hasHeader);
  final int phone;
  final int name;
  final int source;
  final bool hasHeader;
}

const _phoneHeaders = [
  'phone',
  'mobile',
  'number',
  'tel',
  'phone_e164',
  'msisdn',
  'contact',
];
const _nameHeaders = [
  'name',
  'full name',
  'fullname',
  'customer',
  'owner',
  'seller',
];
const _sourceHeaders = [
  'source',
  'account',
  'site',
  'platform',
  'origin',
  'from',
];

_Columns _resolveColumns(List<String> header) {
  int find(List<String> candidates) {
    // Exact match first so "phone" wins over "phone_type".
    for (final c in candidates) {
      final i = header.indexWhere((h) => h == c);
      if (i >= 0) return i;
    }
    for (final c in candidates) {
      final i = header.indexWhere((h) => h.contains(c));
      if (i >= 0) return i;
    }
    return -1;
  }

  final phone = find(_phoneHeaders);
  final name = find(_nameHeaders);
  final source = find(_sourceHeaders);
  return _Columns(phone, name, source, phone >= 0 || name >= 0);
}

/// Headerless file: the phone column is whichever one normalizes most often.
_Columns _guessFromData(List<List<dynamic>> table) {
  final sample = table.take(25).toList();
  if (sample.isEmpty) return const _Columns(-1, -1, -1, false);

  final width = sample.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  var bestColumn = -1;
  var bestHits = 0;
  for (var col = 0; col < width; col++) {
    var hits = 0;
    for (final row in sample) {
      if (col < row.length && normalizePhone(row[col]?.toString()) != null) {
        hits++;
      }
    }
    if (hits > bestHits) {
      bestHits = hits;
      bestColumn = col;
    }
  }
  if (bestColumn < 0) return const _Columns(-1, -1, -1, false);

  // Name: the first other column that holds mostly non-numeric text.
  var nameColumn = -1;
  for (var col = 0; col < width; col++) {
    if (col == bestColumn) continue;
    var texty = 0;
    for (final row in sample) {
      final v = col < row.length ? row[col]?.toString().trim() ?? '' : '';
      if (v.isNotEmpty && RegExp(r'[A-Za-zሀ-፿]').hasMatch(v)) texty++;
    }
    if (texty > sample.length / 2) {
      nameColumn = col;
      break;
    }
  }
  return _Columns(bestColumn, nameColumn, -1, false);
}
