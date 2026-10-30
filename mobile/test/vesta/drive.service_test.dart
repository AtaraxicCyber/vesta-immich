import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:immich_mobile/vesta/drive/drive.service.dart';

// A real Dufs v0.47.0 response for PROPFIND /drive/Documents/ (Depth: 1), from the Vesta-App sandbox
const _dufsDocuments = '''<?xml version="1.0" encoding="utf-8" ?>
<D:multistatus xmlns:D="DAV:">
<D:response>
<D:href>/drive/Documents/</D:href>
<D:propstat>
<D:prop>
<D:displayname>Documents</D:displayname>
<D:getlastmodified>Fri, 30 Oct 2026 15:16:47 GMT</D:getlastmodified>
<D:resourcetype><D:collection/></D:resourcetype>
</D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat>
</D:response><D:response>
<D:href>/drive/Documents/welcome.txt</D:href>
<D:propstat>
<D:prop>
<D:displayname>welcome.txt</D:displayname>
<D:getcontentlength>38</D:getcontentlength>
<D:getlastmodified>Fri, 30 Oct 2026 15:17:00 GMT</D:getlastmodified>
<D:resourcetype></D:resourcetype>
</D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat>
</D:response><D:response>
<D:href>/drive/Documents/Taxes/</D:href>
<D:propstat>
<D:prop>
<D:displayname>Taxes</D:displayname>
<D:getlastmodified>Fri, 30 Oct 2026 15:16:47 GMT</D:getlastmodified>
<D:resourcetype><D:collection/></D:resourcetype>
</D:prop>
<D:status>HTTP/1.1 200 OK</D:status>
</D:propstat>
</D:response>
</D:multistatus>''';

void main() {
  group('parseMultistatus', () {
    test('parses a Dufs listing, skipping the folder itself, folders first', () {
      final entries = DriveService.parseMultistatus(_dufsDocuments, folderPath: '/drive/Documents/');

      expect(entries.map((e) => e.path), ['Documents/Taxes', 'Documents/welcome.txt']);
      final taxes = entries[0];
      expect([taxes.name, taxes.isFolder, taxes.size], ['Taxes', true, null]);
      final welcome = entries[1];
      expect([welcome.name, welcome.isFolder, welcome.size], ['welcome.txt', false, 38]);
      expect(welcome.modified, DateTime.utc(2026, 10, 30, 15, 17));
    });

    test('decodes names, accepts absolute hrefs and any namespace prefix, sorts by name', () {
      const body = '''<?xml version="1.0"?>
<multistatus xmlns="DAV:">
  <response><href>https://family-a.example/drive/</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response>
  <response><href>https://family-a.example/drive/b%20notes.txt</href><propstat><prop><resourcetype/><getlastmodified>not a date</getlastmodified></prop></propstat></response>
  <response><href>/drive/A%C3%A9%20photos/</href><propstat><prop><resourcetype><collection/></resourcetype></prop></propstat></response>
  <response><href>/drive/a.txt</href><propstat><prop><resourcetype/></prop></propstat></response>
  <response><propstat><prop/></propstat></response>
</multistatus>''';

      final entries = DriveService.parseMultistatus(body, folderPath: '/drive/');

      expect(entries.map((e) => e.name), ['Aé photos', 'a.txt', 'b notes.txt']);
      expect(entries.first.isFolder, isTrue);
      expect(entries.last.modified, isNull);
    });

    test('ignores entries outside the requested folder', () {
      const body = '''<multistatus xmlns="DAV:">
  <response><href>/drive/Documents/</href></response>
  <response><href>/drive/Other/x.txt</href></response>
  <response><href>/drive/Documents/Taxes/2025.pdf</href><propstat><prop><resourcetype/></prop></propstat></response>
</multistatus>''';

      final entries = DriveService.parseMultistatus(body, folderPath: '/drive/Documents/');

      expect(entries.map((e) => e.path), ['Documents/Taxes/2025.pdf']);
    });
  });

  group('list', () {
    late http.Request request;

    DriveService serviceReturning(int status, String body, {String? token = 'token-1'}) => DriveService(
      () => MockClient((r) async {
        request = r;
        return http.Response(body, status);
      }),
      () => 'https://family-a.example',
      () => token,
    );

    test('sends an authenticated depth-1 PROPFIND to the encoded folder URL', () async {
      final entries = await serviceReturning(207, _dufsDocuments).list('Documents');

      expect(request.method, 'PROPFIND');
      expect(request.url.toString(), 'https://family-a.example/drive/Documents/');
      expect(request.headers['Authorization'], 'Bearer token-1');
      expect(request.headers['Depth'], '1');
      expect(entries, hasLength(2));
    });

    test('encodes each path segment', () async {
      await serviceReturning(207, '<multistatus xmlns="DAV:"/>').list('Family photos/2025 #1');

      expect(request.url.toString(), 'https://family-a.example/drive/Family%20photos/2025%20%231/');
    });

    Matcher throwsDrive(DriveError error) => throwsA(isA<DriveException>().having((e) => e.error, 'error', error));

    test('maps 401 to unauthorized', () {
      expect(serviceReturning(401, '').list(''), throwsDrive(.unauthorized));
    });

    test('is unauthorized without a login token', () {
      expect(serviceReturning(207, _dufsDocuments, token: null).list(''), throwsDrive(.unauthorized));
    });

    test('maps other statuses and bad XML to failed', () async {
      await expectLater(serviceReturning(500, '').list(''), throwsDrive(.failed));
      await expectLater(serviceReturning(207, '<not xml').list(''), throwsDrive(.failed));
    });
  });
}
