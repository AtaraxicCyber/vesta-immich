import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:xml/xml.dart';

/// Vesta: a file or folder in the family Drive.
class DriveEntry {
  final String name;

  /// Path inside the Drive, without leading or trailing slashes (`Documents/Taxes`).
  final String path;
  final bool isFolder;
  final int? size;
  final DateTime? modified;

  const DriveEntry({required this.name, required this.path, required this.isFolder, this.size, this.modified});
}

enum DriveError { unauthorized, failed }

class DriveException implements Exception {
  final DriveError error;

  const DriveException(this.error);

  @override
  String toString() => 'DriveException($error)';
}

const _propfindBody = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>''';

/// Vesta: reads the family Drive, a WebDAV share at `<server>/drive/`.
///
/// The Drive accepts the same login token as the photos server.
class DriveService {
  final http.Client Function() _client;
  final String? Function() _serverUrl;
  final String? Function() _accessToken;

  const DriveService(this._client, this._serverUrl, this._accessToken);

  Uri _folderUri(String serverUrl, String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return Uri.parse('$serverUrl/drive/${segments.map(Uri.encodeComponent).map((s) => '$s/').join()}');
  }

  /// Lists a folder: folders first, then files, each sorted by name.
  Future<List<DriveEntry>> list(String path) async {
    final serverUrl = _serverUrl();
    final token = _accessToken();
    if (serverUrl == null || token == null) {
      throw const DriveException(DriveError.unauthorized);
    }

    final uri = _folderUri(serverUrl, path);
    final request = http.Request('PROPFIND', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..body = _propfindBody;

    final http.Response response;
    try {
      response = await _client().send(request).then(http.Response.fromStream).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const DriveException(DriveError.failed);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const DriveException(DriveError.unauthorized);
    }
    if (response.statusCode != 207) {
      throw const DriveException(DriveError.failed);
    }

    try {
      return parseMultistatus(response.body, folderPath: uri.path);
    } on XmlException {
      throw const DriveException(DriveError.failed);
    }
  }

  /// Turns a WebDAV multistatus response into entries, leaving out the folder itself.
  static List<DriveEntry> parseMultistatus(String body, {required String folderPath}) {
    String trimSlashes(String s) => s.replaceAll(RegExp(r'^/+|/+$'), '');

    final folder = trimSlashes(Uri.decodeFull(folderPath));
    final entries = <DriveEntry>[];

    for (final response in XmlDocument.parse(body).findAllElements('response', namespaceUri: 'DAV:')) {
      final href = response.findElements('href', namespaceUri: 'DAV:').firstOrNull?.innerText;
      if (href == null) {
        continue;
      }
      // Hrefs may be absolute URLs or paths, and are percent-encoded
      final hrefPath = trimSlashes(Uri.decodeFull(Uri.parse(href).path));
      if (hrefPath == folder || !hrefPath.startsWith('$folder/')) {
        continue;
      }

      final prop = response.findAllElements('prop', namespaceUri: 'DAV:').firstOrNull;
      final isFolder = prop?.findAllElements('collection', namespaceUri: 'DAV:').isNotEmpty ?? false;
      final size = int.tryParse(
        prop?.findElements('getcontentlength', namespaceUri: 'DAV:').firstOrNull?.innerText ?? '',
      );
      final modifiedText = prop?.findElements('getlastmodified', namespaceUri: 'DAV:').firstOrNull?.innerText;
      DateTime? modified;
      try {
        modified = modifiedText == null ? null : HttpDate.parse(modifiedText);
      } on HttpException {
        modified = null;
      }

      // Path inside the Drive: drop the `drive/` prefix
      final drivePath = hrefPath.split('/').skip(1).join('/');
      entries.add(
        DriveEntry(
          name: drivePath.split('/').last,
          path: drivePath,
          isFolder: isFolder,
          size: isFolder ? null : size,
          modified: modified,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }
}

final driveServiceProvider = Provider(
  (_) => DriveService(() => NetworkRepository.client, getServerUrl, () => Store.tryGet(StoreKey.accessToken)),
);
