import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/spending_store.dart';
import '../data/statement_parser.dart';

/// Lets the user pick a PDF/CSV statement, reads it and loads it into [store].
/// Asks for the PDF password if the bank protected it.
Future<void> importStatement(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'csv'],
  );
  if (file == null) return; // user cancelled
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't read that file. Try again.")));
    return;
  }
  if (!context.mounted) return;

  String? password;
  ParsedStatement parsed;
  while (true) {
    try {
      parsed = parseStatement(bytes, file.name, password: password);
      break;
    } on StatementPasswordRequired catch (e) {
      if (!context.mounted) return;
      password = await _askPassword(context, wrong: e.wrongPassword);
      if (password == null) return;
    } on StatementParseException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
  }
  if (!context.mounted) return;

  // Saving can take a few seconds on mobile data.
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Saving your transactions…')),
        ]),
      ),
    ),
  );
  try {
    final result = await store.importStatement(parsed, file.name);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 7),
      content: Text('${_describe(parsed)}\n'
          '${result.added} new transaction${result.added == 1 ? '' : 's'} saved'
          '${result.alreadySaved > 0 ? ' · ${result.alreadySaved} were already saved' : ''}.\n'
          '${_booksLine(parsed)}'),
    ));
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(const SnackBar(
      content: Text("Couldn't save the statement. Check your internet connection and try again."),
    ));
  }
}

String _booksLine(ParsedStatement s) {
  final d = s.difference;
  if (d == null) return 'No opening/closing balance found to check against.';
  if (d.abs() < 0.01 && s.flaggedCount == 0) return '✓ The books balance with your statement.';
  return "⚠ ${pula(d.abs())} doesn't add up. Check Profile → Statements.";
}

/// "142 transactions read · 1 Aug 2026 – 31 Oct 2026 (3 months)"
String _describe(ParsedStatement s) {
  final dates = s.txns.map((t) => t.date).toList()..sort();
  if (dates.isEmpty) return 'No transactions found';
  final months = {for (final d in dates) '${d.year}-${d.month}'}.length;
  return '${s.txns.length} transactions read · ${shortDate(dates.first)} ${dates.first.year} – '
      '${shortDate(dates.last)} ${dates.last.year} ($months month${months == 1 ? '' : 's'})';
}

Future<String?> _askPassword(BuildContext context, {required bool wrong}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Statement password'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(wrong
            ? 'That password did not work. Try again.'
            : 'Your bank protected this PDF. Enter the password from the statement email '
                '(often your ID/Omang number or date of birth).'),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Open')),
      ],
    ),
  );
  controller.dispose();
  return result;
}
