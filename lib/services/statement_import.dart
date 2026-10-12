import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/mock_data.dart';
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
  while (true) {
    try {
      final parsed = parseStatement(bytes, file.name, password: password);
      store.load(parsed, file.name);
      messenger.showSnackBar(SnackBar(
        content: Text('Read ${store.loadSummary}'),
        duration: const Duration(seconds: 6),
      ));
      return;
    } on StatementPasswordRequired catch (e) {
      if (!context.mounted) return;
      password = await _askPassword(context, wrong: e.wrongPassword);
      if (password == null) return;
    } on StatementParseException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
  }
}

void loadSample() => store.load(sampleStatement(), 'Sample statement', sample: true);

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
