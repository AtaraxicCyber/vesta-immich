import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:immich_mobile/vesta/drive/drive.service.dart';
import 'package:intl/intl.dart';

/// Vesta: the Drive tab. Browses the family's shared files; read-only for now.
@RoutePage()
class DrivePage extends HookConsumerWidget {
  const DrivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Folder names from the Drive root down to the folder on screen
    final folders = useState<List<String>>(const []);
    final reload = useState(0);
    final path = folders.value.join('/');

    final listing = useMemoized(() => ref.read(driveServiceProvider).list(path), [path, reload.value]);
    final snapshot = useFuture(listing);

    void open(DriveEntry entry) => folders.value = [...folders.value, entry.name];
    void up() => folders.value = folders.value.sublist(0, folders.value.length - 1);
    Future<void> refresh() async {
      reload.value++;
      await listing.catchError((_) => const <DriveEntry>[]);
    }

    final Widget body;
    if (snapshot.connectionState != ConnectionState.done) {
      body = const Center(child: CircularProgressIndicator());
    } else if (snapshot.hasError) {
      body = _Message(
        icon: Icons.cloud_off_rounded,
        text: context.t.drive_load_failed,
        action: TextButton(onPressed: () => reload.value++, child: Text(context.t.retry)),
      );
    } else if (snapshot.requireData.isEmpty) {
      body = _Message(icon: Icons.folder_open_rounded, text: context.t.empty_folder);
    } else {
      final entries = snapshot.requireData;
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        itemBuilder: (context, index) => _EntryTile(entry: entries[index], onOpen: open),
      );
    }

    return PopScope(
      canPop: folders.value.isEmpty,
      onPopInvokedWithResult: (didPop, _) => didPop ? null : up(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(folders.value.isEmpty ? context.t.drive : folders.value.last),
          leading: folders.value.isEmpty ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: up),
          automaticallyImplyLeading: false,
        ),
        body: RefreshIndicator(onRefresh: refresh, child: body),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final DriveEntry entry;
  final void Function(DriveEntry) onOpen;

  const _EntryTile({required this.entry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final details = [
      if (entry.size != null) formatHumanReadableBytes(entry.size!, 1),
      if (entry.modified != null) DateFormat.yMMMd().format(entry.modified!.toLocal()),
    ].join(' · ');

    return ListTile(
      leading: Icon(
        entry.isFolder ? Icons.folder_rounded : _fileIcon(entry.name),
        color: entry.isFolder ? context.primaryColor : null,
      ),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: entry.isFolder ? const Icon(Icons.chevron_right_rounded) : null,
      // Opening files comes with downloads (Sprint 2)
      onTap: entry.isFolder ? () => onOpen(entry) : null,
    );
  }

  static IconData _fileIcon(String name) {
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (extension) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'heic' || 'webp' => Icons.image_outlined,
      'mp4' || 'mov' || 'mkv' || 'webm' => Icons.movie_outlined,
      'mp3' || 'm4a' || 'wav' || 'flac' => Icons.audio_file_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

/// A centred icon and message, scrollable so pull-to-refresh still works.
class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 12,
            children: [
              Icon(icon, size: 48, color: context.colorScheme.onSurfaceVariant),
              Text(text, textAlign: TextAlign.center),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}
