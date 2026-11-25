// @esofiso
// v2.1 - Gelişmiş Mobil Sürüm

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';

import 'sozler_verisi.dart';

// ============================================================================
// 1. VERİ MODELLERİ VE HİCRİ / ÖZEL GÜN YARDIMCILARI
// ============================================================================

class GunlukVakit {
  final DateTime tarih;
  final String hicriTarih;
  final List<String> vakitler; // [İmsak, Güneş, Öğle, İkindi, Akşam, Yatsı]

  const GunlukVakit({
    required this.tarih,
    required this.hicriTarih,
    required this.vakitler,
  });

  String get tarihAnahtari => TarihYardimci.anahtar(tarih);

  DateTime? vakitZamani(int index) {
    if (index < 0 || index >= vakitler.length) return null;
    final p = vakitler[index].split(':');
    if (p.length < 2) return null;
    final saat = int.tryParse(p[0].trim());
    final dk = int.tryParse(p[1].trim());
    if (saat == null || dk == null) return null;
    return DateTime(tarih.year, tarih.month, tarih.day, saat, dk);
  }

  String toCsvSatiri() {
    final miladi = DateFormat('dd MMMM yyyy EEEE', 'tr_TR').format(tarih);
    return '$miladi,$hicriTarih,${vakitler.join(',')}';
  }
}

class TarihYardimci {
  static const List<String> hicriAylar = [
    '',
    'Muharrem',
    'Safer',
    'Rebiülevvel',
    'Rebiülahir',
    'Cemaziyelevvel',
    'Cemaziyelahir',
    'Recep',
    'Şaban',
    'Ramazan',
    'Şevval',
    'Zilkade',
    'Zilhicce',
  ];

  static const Map<String, int> turkceAylar = {
    'ocak': 1,
    'subat': 2,
    'şubat': 2,
    'mart': 3,
    'nisan': 4,
    'mayis': 5,
    'mayıs': 5,
    'haziran': 6,
    'temmuz': 7,
    'agustos': 8,
    'ağustos': 8,
    'eylul': 9,
    'eylül': 9,
    'ekim': 10,
    'kasim': 11,
    'kasım': 11,
    'aralik': 12,
    'aralık': 12,
  };

  static const Map<String, int> hicriAyHaritasi = {
    'muharrem': 1,
    'safer': 2,
    'rebiulevvel': 3,
    'rebiülevvel': 3,
    'rebiulahir': 4,
    'rebiülahir': 4,
    'cemaziyelevvel': 5,
    'cemaziyelahir': 6,
    'recep': 7,
    'saban': 8,
    'şaban': 8,
    'ramazan': 9,
    'sevval': 10,
    'şevval': 10,
    'zilkade': 11,
    'zilhicce': 12,
  };

  static String trKucult(String s) {
    return s
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('\u0307', '')
        .trim();
  }

  static String anahtar(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool ayniGun(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime? turkceTarihCoz(String ham) {
    final s = ham.trim();
    if (s.isEmpty) return null;

    // 01.01.2026 veya 01/01/2026
    final noktaMatch = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})').firstMatch(s);
    if (noktaMatch != null) {
      final g = int.tryParse(noktaMatch.group(1)!);
      final a = int.tryParse(noktaMatch.group(2)!);
      final y = int.tryParse(noktaMatch.group(3)!);
      if (g != null && a != null && y != null && a >= 1 && a <= 12 && g >= 1 && g <= 31) {
        return DateTime(y, a, g);
      }
    }

    // 2026-01-01
    final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (isoMatch != null) {
      final y = int.tryParse(isoMatch.group(1)!);
      final a = int.tryParse(isoMatch.group(2)!);
      final g = int.tryParse(isoMatch.group(3)!);
      if (g != null && a != null && y != null) {
        return DateTime(y, a, g);
      }
    }

    // "01 Ocak 2026 Perşembe" veya "1 Ocak 2026"
    final parcalar = s.split(RegExp(r'\s+'));
    if (parcalar.length >= 3) {
      final g = int.tryParse(parcalar[0]);
      final ayAdi = trKucult(parcalar[1]);
      final a = turkceAylar[ayAdi];
      final y = int.tryParse(parcalar[2]);
      if (g != null && a != null && y != null && g >= 1 && g <= 31) {
        return DateTime(y, a, g);
      }
    }
    return null;
  }

  static (int yil, int ay, int gun) miladiToHicri(DateTime tarih) {
    final a = (14 - tarih.month) ~/ 12;
    final y = tarih.year + 4800 - a;
    final m = tarih.month + 12 * a - 3;
    final jd = tarih.day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;

    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final hAy = (24 * l) ~/ 709;
    final hGun = l - (709 * hAy) ~/ 24;
    final hYil = 30 * n + j - 30;
    return (hYil, hAy, hGun);
  }

  static String hicriMetinHesapla(DateTime tarih) {
    final (hYil, hAy, hGun) = miladiToHicri(tarih);
    final ayAdi = (hAy >= 1 && hAy <= 12) ? hicriAylar[hAy] : '';
    return '$hGun $ayAdi $hYil';
  }

  static (int ay, int gun)? hicriMetinCoz(String? metin) {
    if (metin == null || metin.trim().isEmpty) return null;
    final parcalar = metin.trim().split(RegExp(r'\s+'));
    if (parcalar.length < 2) return null;
    final gun = int.tryParse(parcalar[0]);
    final ay = hicriAyHaritasi[trKucult(parcalar[1])];
    if (gun != null && ay != null) return (ay, gun);
    return null;
  }

  static String? ozelGunBul(
    DateTime an, {
    required bool aksamSonrasi,
    String? bugunHicri,
    String? yarinHicri,
  }) {
    final kontrolTarihi = aksamSonrasi ? an.add(const Duration(days: 1)) : an;
    final kaynakHicri = aksamSonrasi ? yarinHicri : bugunHicri;

    int hAy;
    int hGun;
    final cozulen = hicriMetinCoz(kaynakHicri);
    if (cozulen != null) {
      hAy = cozulen.$1;
      hGun = cozulen.$2;
    } else {
      final hesap = miladiToHicri(kontrolTarihi);
      hAy = hesap.$2;
      hGun = hesap.$3;
    }

    // Bayramlar
    if (hAy == 10 && (hGun >= 1 && hGun <= 3)) return 'Ramazan Bayramı';
    if (hAy == 12 && (hGun >= 10 && hGun <= 13)) return 'Kurban Bayramı';

    // Kandil geceleri
    if (hAy == 9 && hGun == 27) return 'Kadir Gecesi';
    if (hAy == 3 && hGun == 12) return 'Mevlid Kandili';
    if (hAy == 7 && hGun == 27) return 'Miraç Kandili';
    if (hAy == 8 && hGun == 15) return 'Berat Kandili';
    if (hAy == 7 && hGun <= 7 && kontrolTarihi.weekday == DateTime.friday) {
      return 'Regaip Kandili';
    }

    // Ramazan Ayı
    if (hAy == 9) return 'Ramazan Ayı';

    // Cuma (Perşembe akşamından Cuma akşamına kadar)
    if ((an.weekday == DateTime.friday && !aksamSonrasi) ||
        (an.weekday == DateTime.thursday && aksamSonrasi)) {
      return 'Hayırlı Cumalar';
    }
    return null;
  }

  static String sehirSlug(String sehir) {
    const map = {
      'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g',
      'ı': 'i', 'I': 'i', 'İ': 'i', 'ö': 'o', 'Ö': 'o',
      'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
    };
    final sb = StringBuffer();
    for (final ch in sehir.trim().split('')) {
      sb.write(map[ch] ?? ch.toLowerCase());
    }
    return sb.toString().replaceAll(RegExp(r'[^a-z0-9-]'), '');
  }
}

// ============================================================================
// 2. VERİ YÖNETİM SERVİSİ (XLSX/CSV İMPORT + DİYANET ONLINE KATMANI)
// ============================================================================

class ImportSonucu {
  final String onerilenSehir;
  final List<GunlukVakit> kayitlar;
  const ImportSonucu({required this.onerilenSehir, required this.kayitlar});
}

class VeriYonetimServisi {
  static final RegExp _saatRegex = RegExp(r'^\d{1,2}:\d{2}$');

  static Future<Directory> _sehirKlasoru() async {
    final doc = await getApplicationDocumentsDirectory();
    final dir = Directory('${doc.path}/sehir_vakitleri');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _dosyaAdiUret(String sehirAdi) {
    final slug = TarihYardimci.sehirSlug(sehirAdi);
    return 'vakitler_${slug.isEmpty ? DateTime.now().millisecondsSinceEpoch : slug}.csv';
  }

  /// CSV metnini tipli GunlukVakit haritasına dönüştürür.
  static Map<String, GunlukVakit> csvCoz(String rawData) {
    final sonuc = <String, GunlukVakit>{};
    final satirlar = const LineSplitter().convert(rawData);
    for (final satir in satirlar) {
      final temiz = satir.trim();
      if (temiz.isEmpty) continue;
      final ayrac = temiz.contains(';') && !temiz.contains(',') ? ';' : ',';
      final parcalar = temiz.split(ayrac).map((e) => e.trim().replaceAll('"', '')).toList();
      final kayit = _satirdanGunlukVakit(parcalar);
      if (kayit != null) {
        sonuc[kayit.tarihAnahtari] = kayit;
      }
    }
    return sonuc;
  }

  static GunlukVakit? _satirdanGunlukVakit(List<String> parcalar) {
    if (parcalar.length < 7) return null;
    final tarih = TarihYardimci.turkceTarihCoz(parcalar[0]);
    if (tarih == null) return null;

    // 8+ sütunlu Diyanet formatı: [Miladi, Hicri, İmsak, Güneş, Öğle, İkindi, Akşam, Yatsı]
    if (parcalar.length >= 8 && _saatRegex.hasMatch(parcalar[2])) {
      final vakitler = parcalar.sublist(2, 8).map(_saatiNormalizeEt).toList();
      if (vakitler.every((v) => _saatRegex.hasMatch(v))) {
        final hicri = parcalar[1].isNotEmpty
            ? parcalar[1]
            : TarihYardimci.hicriMetinHesapla(tarih);
        return GunlukVakit(tarih: tarih, hicriTarih: hicri, vakitler: vakitler);
      }
    }

    // 7 sütunlu Hicri'siz format: [Miladi, İmsak, Güneş, Öğle, İkindi, Akşam, Yatsı]
    if (_saatRegex.hasMatch(parcalar[1])) {
      final vakitler = parcalar.sublist(1, 7).map(_saatiNormalizeEt).toList();
      if (vakitler.every((v) => _saatRegex.hasMatch(v))) {
        return GunlukVakit(
          tarih: tarih,
          hicriTarih: TarihYardimci.hicriMetinHesapla(tarih),
          vakitler: vakitler,
        );
      }
    }
    return null;
  }

  static String _saatiNormalizeEt(String s) {
    final temiz = s.trim().split(' ').first;
    final p = temiz.split(':');
    if (p.length < 2) return temiz;
    return '${p[0].padLeft(2, '0')}:${p[1].padLeft(2, '0')}';
  }

  /// Diyanet .xlsx dosyasını (inlineStr + sharedStrings destekli) çözer.
  static ImportSonucu xlsxCoz(Uint8List bytes, String dosyaAdi) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Varsa sharedStrings.xml'i oku
    final sharedStrings = <String>[];
    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase() == 'xl/sharedstrings.xml') {
        final xmlStr = utf8.decode(file.content as List<int>, allowMalformed: true);
        final doc = XmlDocument.parse(xmlStr);
        for (final si in doc.findAllElements('si', namespace: '*')) {
          final text = si.findAllElements('t', namespace: '*').map((e) => e.innerText).join();
          sharedStrings.add(text);
        }
        break;
      }
    }

    // 2. İlk çalışma sayfasını bul (sheet1.xml)
    ArchiveFile? sheetFile;
    for (final file in archive) {
      final lower = file.name.toLowerCase();
      if (file.isFile && lower.startsWith('xl/worksheets/sheet') && lower.endsWith('.xml')) {
        sheetFile = file;
        if (lower.endsWith('sheet1.xml')) break;
      }
    }
    if (sheetFile == null) {
      throw Exception('Excel dosyasında çalışma sayfası bulunamadı.');
    }

    final sheetXml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
    final doc = XmlDocument.parse(sheetXml);

    String onerilenSehir = _dosyaAdindanSehirTahmin(dosyaAdi);
    final kayitlar = <GunlukVakit>[];

    for (final row in doc.findAllElements('row', namespace: '*')) {
      final hucreler = <int, String>{};
      var maxCol = -1;
      for (final c in row.findElements('c', namespace: '*')) {
        final ref = c.getAttribute('r') ?? '';
        final colIdx = _sutunIndeksi(ref);
        final tAttr = c.getAttribute('t');
        String deger = '';
        if (tAttr == 'inlineStr') {
          deger = c.findAllElements('t', namespace: '*').map((e) => e.innerText).join();
        } else if (tAttr == 's') {
          final vEls = c.findElements('v', namespace: '*');
          final vText = vEls.isNotEmpty ? vEls.first.innerText : '';
          final idx = int.tryParse(vText);
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            deger = sharedStrings[idx];
          }
        } else {
          final vEls = c.findElements('v', namespace: '*');
          deger = vEls.isNotEmpty ? vEls.first.innerText : '';
        }
        if (colIdx >= 0) {
          hucreler[colIdx] = deger.trim();
          if (colIdx > maxCol) maxCol = colIdx;
        }
      }

      if (maxCol < 0) continue;
      final satirList = List<String>.generate(maxCol + 1, (i) => hucreler[i] ?? '');

      // Başlıktan şehir adı yakala: "Ankara Namaz Vakitleri | Diyanet..."
      if (satirList.isNotEmpty) {
        final ilk = satirList[0];
        if (ilk.contains('Namaz Vakitleri')) {
          final aday = ilk.split('Namaz Vakitleri').first.trim();
          if (aday.isNotEmpty) onerilenSehir = aday;
        } else if (ilk.contains('İçin') && ilk.contains('Namaz Vakti')) {
          final aday = ilk.split('İçin').first.trim();
          if (aday.isNotEmpty) onerilenSehir = aday;
        }
      }

      final kayit = _satirdanGunlukVakit(satirList);
      if (kayit != null) {
        kayitlar.add(kayit);
      }
    }

    return ImportSonucu(onerilenSehir: onerilenSehir, kayitlar: kayitlar);
  }

  static ImportSonucu csvDosyaCoz(Uint8List bytes, String dosyaAdi) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final map = csvCoz(text);
    final liste = map.values.toList()..sort((a, b) => a.tarih.compareTo(b.tarih));
    return ImportSonucu(
      onerilenSehir: _dosyaAdindanSehirTahmin(dosyaAdi),
      kayitlar: liste,
    );
  }

  static int _sutunIndeksi(String ref) {
    final harfler = RegExp(r'^[A-Za-z]+').firstMatch(ref)?.group(0);
    if (harfler == null) return -1;
    var index = 0;
    for (final code in harfler.toUpperCase().codeUnits) {
      index = index * 26 + (code - 64);
    }
    return index - 1;
  }

  static String _dosyaAdindanSehirTahmin(String dosyaAdi) {
    var temiz = dosyaAdi.replaceAll(RegExp(r'\.(xlsx|csv|txt)$', caseSensitive: false), '');
    if (temiz.contains('Namaz Vakitleri')) {
      temiz = temiz.split('Namaz Vakitleri').first.trim();
    }
    temiz = temiz.replaceAll(RegExp(r'^vakitler[_-]', caseSensitive: false), '').trim();
    if (temiz.isEmpty) return 'Yeni Şehir';
    return temiz[0].toUpperCase() + temiz.substring(1);
  }

  /// Kalıcı olarak uygulama klasörüne kaydeder (mevcut dosya varsa tarihleri birleştirir).
  static Future<String> sehirVerisiKaydet(
    String sehirAdi,
    List<GunlukVakit> yeniKayitlar, {
    String? mevcutDosyaYolu,
  }) async {
    final dir = await _sehirKlasoru();
    final dosyaYolu = mevcutDosyaYolu ?? '${dir.path}/${_dosyaAdiUret(sehirAdi)}';
    final dosya = File(dosyaYolu);

    final birlesik = <String, GunlukVakit>{};
    if (await dosya.exists()) {
      final eskiMetin = await dosya.readAsString();
      birlesik.addAll(csvCoz(eskiMetin));
    }
    for (final k in yeniKayitlar) {
      birlesik[k.tarihAnahtari] = k;
    }

    final sirali = birlesik.values.toList()..sort((a, b) => a.tarih.compareTo(b.tarih));
    final sb = StringBuffer('Miladi Tarih,Hicri Tarih,İmsak,Güneş,Öğle,İkindi,Akşam,Yatsı\n');
    for (final k in sirali) {
      sb.writeln(k.toCsvSatiri());
    }
    await dosya.writeAsString(sb.toString(), flush: true);
    return dosyaYolu;
  }

  /// Online Katman 1: 1 Aylık Resmi Diyanet Tablosu (Habertürk / Diyanet kaynağı)
  static Future<List<GunlukVakit>> internettenAylikDiyanetCek(String sehirAdi) async {
    final slug = TarihYardimci.sehirSlug(sehirAdi);
    final url = Uri.parse('https://www.haberturk.com/namaz-vakitleri/$slug');
    final resp = await http.get(url, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
    }).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Sunucu hatası (${resp.statusCode}). Şehir adını kontrol edin.');
    }

    final html = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final tableMatch = RegExp(r'<tbody[^>]*>(.*?)</tbody>', dotAll: true, caseSensitive: false)
        .firstMatch(html);
    if (tableMatch == null) {
      throw Exception('İmsakiye tablosu bulunamadı. 1 Yıllık API yöntemini deneyin.');
    }

    final trMatches = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false)
        .allMatches(tableMatch.group(1)!);

    final now = DateTime.now();
    final kayitlar = <GunlukVakit>[];
    var gunIndex = 1;

    for (final tr in trMatches) {
      final tdler = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false)
          .allMatches(tr.group(1)!)
          .map((m) => m.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim())
          .toList();

      if (tdler.length >= 7) {
        final vakitler = tdler.sublist(1, 7).map(_saatiNormalizeEt).toList();
        if (vakitler.every((v) => _saatRegex.hasMatch(v))) {
          DateTime? tarih = TarihYardimci.turkceTarihCoz(tdler[0]);
          tarih ??= DateTime(now.year, now.month, gunIndex);
          kayitlar.add(GunlukVakit(
            tarih: tarih,
            hicriTarih: TarihYardimci.hicriMetinHesapla(tarih),
            vakitler: vakitler,
          ));
          gunIndex++;
        }
      }
    }

    if (kayitlar.isEmpty) {
      throw Exception('Tablodan vakit verisi okunamadı.');
    }
    return kayitlar;
  }

  /// Online Katman 2: 1 Yıllık Diyanet Metodu (Aladhan API method=13, Tüm Dünya)
  static Future<List<GunlukVakit>> internettenYillikApiCek(
    String sehirAdi, {
    String ulke = 'Turkey',
    int? yil,
  }) async {
    final hedefYil = yil ?? DateTime.now().year;
    final uri = Uri.https('api.aladhan.com', '/v1/calendarByCity/$hedefYil', {
      'city': sehirAdi.trim(),
      'country': ulke.trim(),
      'method': '13', // Diyanet İşleri Başkanlığı, Turkey
    });

    final resp = await http.get(uri).timeout(const Duration(seconds: 25));
    if (resp.statusCode != 200) {
      throw Exception('API yanıt vermedi (${resp.statusCode}).');
    }

    final jsonMap = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final data = jsonMap['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Geçersiz API yanıtı.');
    }

    final kayitlar = <GunlukVakit>[];
    for (var ay = 1; ay <= 12; ay++) {
      final ayListesi = data['$ay'];
      if (ayListesi is! List) continue;
      for (final gunObj in ayListesi) {
        if (gunObj is! Map<String, dynamic>) continue;
        final timings = gunObj['timings'] as Map<String, dynamic>?;
        final dateObj = gunObj['date'] as Map<String, dynamic>?;
        if (timings == null || dateObj == null) continue;

        final greg = dateObj['gregorian'] as Map<String, dynamic>?;
        final gregStr = greg?['date']?.toString() ?? ''; // dd-MM-yyyy
        final tarih = TarihYardimci.turkceTarihCoz(gregStr);
        if (tarih == null) continue;

        String hicriStr = TarihYardimci.hicriMetinHesapla(tarih);
        final hijri = dateObj['hijri'] as Map<String, dynamic>?;
        if (hijri != null) {
          final hGun = int.tryParse(hijri['day']?.toString() ?? '');
          final hAyNo = int.tryParse((hijri['month'] as Map?)?['number']?.toString() ?? '');
          final hYil = hijri['year']?.toString() ?? '';
          if (hGun != null && hAyNo != null && hAyNo >= 1 && hAyNo <= 12 && hYil.isNotEmpty) {
            hicriStr = '$hGun ${TarihYardimci.hicriAylar[hAyNo]} $hYil';
          }
        }

        final vakitler = [
          _saatiNormalizeEt(timings['Fajr']?.toString() ?? ''),
          _saatiNormalizeEt(timings['Sunrise']?.toString() ?? ''),
          _saatiNormalizeEt(timings['Dhuhr']?.toString() ?? ''),
          _saatiNormalizeEt(timings['Asr']?.toString() ?? ''),
          _saatiNormalizeEt(timings['Maghrib']?.toString() ?? ''),
          _saatiNormalizeEt(timings['Isha']?.toString() ?? ''),
        ];
        if (vakitler.every((v) => _saatRegex.hasMatch(v))) {
          kayitlar.add(GunlukVakit(
            tarih: tarih,
            hicriTarih: hicriStr,
            vakitler: vakitler,
          ));
        }
      }
    }

    if (kayitlar.isEmpty) {
      throw Exception('Bu şehir için veri bulunamadı.');
    }
    return kayitlar;
  }
}

// ============================================================================
// 3. BİLDİRİM SERVİSİ (MEVCUT KANALLAR VE ALARM MODU KORUNDU)
// ============================================================================

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    } catch (_) {}

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin
        .initialize(const InitializationSettings(android: androidSettings));

    if (Platform.isAndroid) {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();
    }
  }

  AndroidNotificationDetails get _standardDetails =>
      const AndroidNotificationDetails(
        'nvapp_standard_v1',
        'Standart Hatırlatıcı',
        importance: Importance.max,
        priority: Priority.high,
        color: Colors.blue,
        playSound: true,
        category: AndroidNotificationCategory.reminder,
      );

  AndroidNotificationDetails get _alarmDetails => AndroidNotificationDetails(
        'nvapp_alarm_mode_v1',
        'Alarm Modu',
        importance: Importance.max,
        priority: Priority.max,
        color: Colors.deepPurple,
        playSound: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        additionalFlags: Int32List.fromList(<int>[4]),
      );

  Future<void> bildirimKur(int id, String vakitAdi, DateTime vakit,
      int dakikaKala, bool isAlarm) async {
    final hedef = vakit.subtract(Duration(minutes: dakikaKala));
    if (hedef.isBefore(DateTime.now())) return;

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        dakikaKala == 0
            ? '$vakitAdi Vakti Girdi!'
            : '$vakitAdi Vaktine $dakikaKala dk Kaldı',
        isAlarm ? 'Alarmı kapatmak için dokunun' : 'Vakit hatırlatıcısı',
        tz.TZDateTime.from(hedef, tz.local),
        NotificationDetails(
          android: isAlarm ? _alarmDetails : _standardDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  Future<void> iptalEt() async => await _notificationsPlugin.cancelAll();
}

final notificationService = NotificationService();

// ============================================================================
// 4. UYGULAMA GİRİŞ NOKTASI
// ============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NamazApp());
}

class NamazApp extends StatefulWidget {
  const NamazApp({super.key});
  @override
  State<NamazApp> createState() => _NamazAppState();
}

class _NamazAppState extends State<NamazApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _baslat();
  }

  Future<void> _baslat() async {
    await initializeDateFormatting('tr_TR', null);
    await notificationService.init();
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _themeMode = (prefs.getBool('isDarkMode') ?? false)
          ? ThemeMode.dark
          : ThemeMode.light);
    }
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
    await prefs.setBool('isDarkMode', _themeMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NvApp Mobile',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: _themeMode,
      home: AnaSayfa(onThemeToggle: toggleTheme),
    );
  }
}

// ============================================================================
// 5. ANA SAYFA
// ============================================================================

class AnaSayfa extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const AnaSayfa({super.key, required this.onThemeToggle});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> with WidgetsBindingObserver {
  final Map<String, String> varsayilanAssetSehirler = const {
    'Çorum': 'assets/vakitler_corum.csv',
    'Niğde': 'assets/vakitler_nigde.csv',
    'Ankara': 'assets/vakitler_ankara.csv',
  };

  Map<String, String> ozelSehirDosyalari = {};
  String secilenSehir = 'Çorum';

  Map<String, GunlukVakit> vakitHaritasi = {};
  GunlukVakit? gosterilenVakit;

  String kalanSure = '--:--:--';
  double ilerlemeYuzdesi = 0.0;
  int aktifIndex = -1;
  DateTime gosterilenTarih = DateTime.now();
  DateTime _sonKontrolGunu = DateTime.now();
  bool veriYuklendi = false;

  // Yeni ayarlar
  String seciliTema = 'vakit_dinamik';
  bool ozelGunTemasiAktif = true;
  bool hicriGoster = false;
  bool sozGoster = true;
  late int aktifSozIndex;

  final List<String> vakitIsimleri = const [
    'İmsak',
    'Güneş',
    'Öğle',
    'İkindi',
    'Akşam',
    'Yatsı',
  ];

  Map<int, int> alarmAyarlari = {};
  Map<int, bool> alarmTipleri = {};
  Timer? _sayacTimer;

  List<String> get tumSehirIsimleri {
    final set = <String>{...varsayilanAssetSehirler.keys, ...ozelSehirDosyalari.keys};
    return set.toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final gunNo = int.tryParse(DateFormat('D').format(DateTime.now())) ?? 1;
    aktifSozIndex = (gunNo - 1) % diniSozler.length;

    _veriVeAyarlariYukle();
    _sayacTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && veriYuklendi) {
        _sayaciGuncelle();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sayacTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && veriYuklendi) {
      final simdi = DateTime.now();
      if (!TarihYardimci.ayniGun(simdi, _sonKontrolGunu)) {
        _sonKontrolGunu = simdi;
        _gunuBelirle(simdi);
      }
      _sayaciGuncelle();
      _widgetTakviminiGuncelle();
    }
  }

  Future<void> _veriVeAyarlariYukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final ozelJson = prefs.getString('ozelSehirDosyalari');
    final yuklenenOzel = <String, String>{};
    if (ozelJson != null && ozelJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(ozelJson) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is String) yuklenenOzel[k] = v;
        });
      } catch (_) {}
    }

    setState(() {
      ozelSehirDosyalari = yuklenenOzel;
      secilenSehir = prefs.getString('secilenSehir') ?? 'Çorum';
      if (!tumSehirIsimleri.contains(secilenSehir)) {
        secilenSehir = 'Çorum';
      }
      seciliTema = prefs.getString('seciliTema') ?? 'vakit_dinamik';
      ozelGunTemasiAktif = prefs.getBool('ozelGunTemasiAktif') ?? true;
      sozGoster = prefs.getBool('sozGoster') ?? true;
      for (int i = 0; i < 6; i++) {
        alarmAyarlari[i] = prefs.getInt('alarm_$i') ?? -1;
        alarmTipleri[i] = prefs.getBool('alarm_type_$i') ?? false;
      }
    });

    await _hizliVeriYukle();
  }

  Future<void> _widgetTakviminiGuncelle() async {
    if (vakitHaritasi.isEmpty) return;

    final simdi = DateTime.now();
    final liste = <Map<String, dynamic>>[];

    for (int gunOffset = 0; gunOffset < 7; gunOffset++) {
      final gun = simdi.add(Duration(days: gunOffset));
      final kayit = vakitHaritasi[TarihYardimci.anahtar(gun)];
      if (kayit == null) continue;

      for (int i = 0; i < 6; i++) {
        final zaman = kayit.vakitZamani(i);
        if (zaman != null && zaman.isAfter(simdi)) {
          liste.add({
            'ad': vakitIsimleri[i],
            'ms': zaman.millisecondsSinceEpoch,
          });
        }
      }
    }

    if (liste.isEmpty) return;
    await HomeWidget.saveWidgetData('vakit_takvimi', jsonEncode(liste));
    await HomeWidget.updateWidget(name: 'HomeScreenWidgetProvider');
  }

  Future<void> _hizliVeriYukle() async {
    try {
      String rawData = '';
      if (ozelSehirDosyalari.containsKey(secilenSehir)) {
        final f = File(ozelSehirDosyalari[secilenSehir]!);
        if (await f.exists()) {
          rawData = await f.readAsString();
        }
      }
      if (rawData.isEmpty && varsayilanAssetSehirler.containsKey(secilenSehir)) {
        rawData = await rootBundle.loadString(varsayilanAssetSehirler[secilenSehir]!);
      }

      vakitHaritasi = VeriYonetimServisi.csvCoz(rawData);
      final simdi = DateTime.now();
      _sonKontrolGunu = simdi;
      _gunuBelirle(simdi);

      if (mounted) {
        setState(() => veriYuklendi = true);
      }
      _sayaciGuncelle();
      _alarmlariYonet();
      _widgetTakviminiGuncelle();
    } catch (e) {
      if (mounted) {
        setState(() => veriYuklendi = true);
        _mesajGoster('Veri yüklenirken hata oluştu: $e');
      }
    }
  }

  void _gunuBelirle(DateTime referansTarih) {
    final bugunKayit = vakitHaritasi[TarihYardimci.anahtar(referansTarih)];
    if (bugunKayit != null) {
      final yatsiVakti = bugunKayit.vakitZamani(5);
      final yarin = referansTarih.add(const Duration(days: 1));
      final yarinKayit = vakitHaritasi[TarihYardimci.anahtar(yarin)];

      if (TarihYardimci.ayniGun(referansTarih, DateTime.now()) &&
          yatsiVakti != null &&
          DateTime.now().isAfter(yatsiVakti) &&
          yarinKayit != null) {
        gosterilenTarih = yarin;
        gosterilenVakit = yarinKayit;
      } else {
        gosterilenTarih = referansTarih;
        gosterilenVakit = bugunKayit;
      }
    } else {
      gosterilenTarih = referansTarih;
      gosterilenVakit = null;
    }
  }

  void _satirGuncelle(DateTime tarih) {
    gosterilenTarih = tarih;
    gosterilenVakit = vakitHaritasi[TarihYardimci.anahtar(tarih)];
  }

  Future<void> alarmDegistir(int index, int dakika, {bool isAlarm = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alarm_$index', dakika);
    await prefs.setBool('alarm_type_$index', isAlarm);

    setState(() {
      alarmAyarlari[index] = dakika;
      alarmTipleri[index] = isAlarm;
    });
    _alarmlariYonet();
  }

  Future<void> _alarmlariYonet() async {
    if (vakitHaritasi.isEmpty) return;
    await notificationService.iptalEt();

    for (int gunOffset = 0; gunOffset < 5; gunOffset++) {
      final hedefGun = DateTime.now().add(Duration(days: gunOffset));
      final kayit = vakitHaritasi[TarihYardimci.anahtar(hedefGun)];
      if (kayit == null) continue;

      for (int i = 0; i < 6; i++) {
        final dk = alarmAyarlari[i] ?? -1;
        if (dk != -1) {
          final v = kayit.vakitZamani(i);
          if (v != null) {
            final isAlarm = alarmTipleri[i] ?? false;
            notificationService.bildirimKur(
              (gunOffset * 10) + i,
              vakitIsimleri[i],
              v,
              dk,
              isAlarm,
            );
          }
        }
      }
    }
  }

  void _sayaciGuncelle() {
    final simdi = DateTime.now();

    // Gece yarısı geçişi kontrolü
    if (!TarihYardimci.ayniGun(simdi, _sonKontrolGunu)) {
      _sonKontrolGunu = simdi;
      _gunuBelirle(simdi);
      _widgetTakviminiGuncelle();
    }

    final bugunKayit = vakitHaritasi[TarihYardimci.anahtar(simdi)];
    if (bugunKayit == null) {
      if (mounted) {
        setState(() {
          kalanSure = '--:--:--';
          ilerlemeYuzdesi = 0.0;
          aktifIndex = -1;
        });
      }
      return;
    }

    int bulunanIndex = -1;
    DateTime? hedefZaman;
    DateTime? baslangicZamani;

    for (int i = 0; i < 6; i++) {
      final tamVakit = bugunKayit.vakitZamani(i);
      if (tamVakit == null) continue;

      if (simdi.isBefore(tamVakit)) {
        bulunanIndex = i - 1;
        hedefZaman = tamVakit;
        if (i > 0) {
          baslangicZamani = bugunKayit.vakitZamani(i - 1);
        } else {
          // Gece yarısı - İmsak arası: dünün yatsı vakti başlangıç
          final dun = simdi.subtract(const Duration(days: 1));
          baslangicZamani = vakitHaritasi[TarihYardimci.anahtar(dun)]?.vakitZamani(5) ??
              DateTime(simdi.year, simdi.month, simdi.day, 0, 0);
        }
        break;
      }
    }

    // Yatsı vakti geçmişse hedef ertesi günün İmsak vaktidir
    if (hedefZaman == null) {
      bulunanIndex = 5;
      baslangicZamani = bugunKayit.vakitZamani(5);
      final yarin = simdi.add(const Duration(days: 1));
      final yarinKayit = vakitHaritasi[TarihYardimci.anahtar(yarin)];
      hedefZaman = yarinKayit?.vakitZamani(0);
    }

    String yeniKalan = '--:--:--';
    double yeniIlerleme = 0.0;

    if (hedefZaman != null) {
      final fark = hedefZaman.difference(simdi);
      if (!fark.isNegative) {
        yeniKalan =
            '${fark.inHours.toString().padLeft(2, '0')}:${(fark.inMinutes % 60).toString().padLeft(2, '0')}:${(fark.inSeconds % 60).toString().padLeft(2, '0')}';
        if (baslangicZamani != null) {
          final toplamSn = hedefZaman.difference(baslangicZamani).inSeconds;
          if (toplamSn > 0) {
            yeniIlerleme =
                (simdi.difference(baslangicZamani).inSeconds / toplamSn).clamp(0.0, 1.0);
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        aktifIndex = bulunanIndex;
        kalanSure = yeniKalan;
        ilerlemeYuzdesi = yeniIlerleme;
      });
    }
  }

  // --- ÖZEL GÜN & TEMA HESAPLARI ---
  String? _aktifOzelGun() {
    final simdi = DateTime.now();
    final bugunKayit = vakitHaritasi[TarihYardimci.anahtar(simdi)];
    final yarinKayit = vakitHaritasi[TarihYardimci.anahtar(simdi.add(const Duration(days: 1)))];
    final aksam = bugunKayit?.vakitZamani(4);
    final aksamSonrasi = aksam != null && !simdi.isBefore(aksam);

    return TarihYardimci.ozelGunBul(
      simdi,
      aksamSonrasi: aksamSonrasi,
      bugunHicri: bugunKayit?.hicriTarih,
      yarinHicri: yarinKayit?.hicriTarih,
    );
  }

  LinearGradient _getArkaplanGradient(bool isDark, int index, String? ozelGun) {
    // 1. Özel gün teması (Altın sarısı geçişli)
    if (ozelGunTemasiAktif && ozelGun != null) {
      if (isDark) {
        return const LinearGradient(
          colors: [Color(0xFF1F1606), Color(0xFF4A340B), Color(0xFF141007)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      }
      return const LinearGradient(
        colors: [Color(0xFF8C6214), Color(0xFFD4A024), Color(0xFF5A3D0A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    // 2. Seçilebilir sabit temalar
    switch (seciliTema) {
      case 'minimal_koyu':
        return const LinearGradient(
          colors: [Color(0xFF000000), Color(0xFF0B0D11)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        );
      case 'klasik':
        final geceMi = index == -1 || index == 4 || index == 5;
        if (isDark) {
          return geceMi
              ? const LinearGradient(
                  colors: [Color(0xFF0A0F2C), Color(0xFF050712)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : const LinearGradient(
                  colors: [Color(0xFF06281A), Color(0xFF050C0A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                );
        }
        return geceMi
            ? const LinearGradient(
                colors: [Color(0xFF121955), Color(0xFF1D26A8), Color(0xFF030C12)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFF05522D), Color(0xFF097F46), Color(0xFF030C12)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              );
      case 'zumrut':
        return isDark
            ? const LinearGradient(
                colors: [Color(0xFF04221A), Color(0xFF0A3D2E), Color(0xFF03100C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFF065F46), Color(0xFF0E946C), Color(0xFF041C18)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              );
      case 'gece_mavisi':
        return isDark
            ? const LinearGradient(
                colors: [Color(0xFF071126), Color(0xFF0F254E), Color(0xFF040914)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFF0F2A60), Color(0xFF1D4EA8), Color(0xFF060E20)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              );
      case 'gun_batimi':
        return isDark
            ? const LinearGradient(
                colors: [Color(0xFF331118), Color(0xFF280D2B), Color(0xFF0C0712)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFFBE4B37), Color(0xFF7E225C), Color(0xFF180E22)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              );
      case 'vakit_dinamik':
      default:
        return _getVakitGradient(isDark, index);
    }
  }

  LinearGradient _getVakitGradient(bool isDark, int index) {
    if (isDark) {
      switch (index) {
        case 0:
          return const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0F2027)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 1:
          return const LinearGradient(
            colors: [Color(0xFF232526), Color(0xFF414345)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 2:
          return const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 3:
          return const LinearGradient(
            colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 4:
          return const LinearGradient(
            colors: [Color(0xFF0F0C29), Color(0xFF302B63)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 5:
        default:
          return const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF1A1A2E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
      }
    } else {
      switch (index) {
        case 0:
          return const LinearGradient(
            colors: [Color(0xFF2B5876), Color(0xFF4E4376)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 1:
          return const LinearGradient(
            colors: [Color(0xFFDAA872), Color(0xFFE4C777)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 2:
          return const LinearGradient(
            colors: [Color(0xFF6DD5FA), Color(0xFF143F5B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 3:
          return const LinearGradient(
            colors: [Color(0xFFE67E22), Color(0xFF2C3E50)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 4:
          return const LinearGradient(
            colors: [Color(0xFFC31432), Color(0xFF240B36)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
        case 5:
        default:
          return const LinearGradient(
            colors: [Color(0xFF141E30), Color(0xFF243B55)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
      }
    }
  }

  Color _getTextColor(bool isDark, String? ozelGun) {
    if (isDark) return Colors.white;
    if (ozelGunTemasiAktif && ozelGun != null) return Colors.white;
    if (seciliTema == 'vakit_dinamik' && aktifIndex == 1) return Colors.black87;
    return Colors.white;
  }

  void _mesajGoster(String mesaj) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mesaj), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _linkAc(String urlStr) async {
    final uri = Uri.parse(urlStr);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // --- DOSYADAN VERİ İMPORT ETME (.xlsx / .csv) ---
  Future<void> _dosyadanIceAktar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) {
        _mesajGoster('Dosya okunamadı.');
        return;
      }

      final ext = (picked.extension ?? '').toLowerCase();
      final ImportSonucu sonuc = (ext == 'xlsx')
          ? VeriYonetimServisi.xlsxCoz(bytes, picked.name)
          : VeriYonetimServisi.csvDosyaCoz(bytes, picked.name);

      if (sonuc.kayitlar.isEmpty) {
        _mesajGoster('Dosyada geçerli namaz vakti satırı bulunamadı.');
        return;
      }

      if (!mounted) return;
      final sehirAdi = await _sehirAdiOnayDialogu(
        baslangicAdi: sonuc.onerilenSehir,
        bilgi:
            '${sonuc.kayitlar.length} günlük veri okundu\n(${DateFormat('dd.MM.yyyy').format(sonuc.kayitlar.first.tarih)} - ${DateFormat('dd.MM.yyyy').format(sonuc.kayitlar.last.tarih)})',
      );
      if (sehirAdi == null || sehirAdi.trim().isEmpty) return;

      await _yeniSehirVerisiniKaydetVeSec(sehirAdi.trim(), sonuc.kayitlar);
    } catch (e) {
      _mesajGoster('İçe aktarma hatası: $e');
    }
  }

  Future<String?> _sehirAdiOnayDialogu({
    required String baslangicAdi,
    required String bilgi,
  }) async {
    final controller = TextEditingController(text: baslangicAdi);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şehri Kaydet'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(bilgi, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Şehir Adı',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _yeniSehirVerisiniKaydetVeSec(
    String sehirAdi,
    List<GunlukVakit> kayitlar,
  ) async {
    final mevcutYol = ozelSehirDosyalari[sehirAdi];
    final dosyaYolu = await VeriYonetimServisi.sehirVerisiKaydet(
      sehirAdi,
      kayitlar,
      mevcutDosyaYolu: mevcutYol,
    );

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ozelSehirDosyalari[sehirAdi] = dosyaYolu;
      secilenSehir = sehirAdi;
    });
    await prefs.setString('ozelSehirDosyalari', jsonEncode(ozelSehirDosyalari));
    await prefs.setString('secilenSehir', sehirAdi);
    await _hizliVeriYukle();
    _mesajGoster('$sehirAdi için ${kayitlar.length} günlük veri kaydedildi.');
  }

  // --- DOĞRUDAN İNTERNETTEN VERİ ÇEKME KATMANI (OVERFLOW DÜZELTİLDİ) ---
  void _internettenVeriCekDialogu() {
    final sehirCtrl = TextEditingController(text: secilenSehir);
    final ulkeCtrl = TextEditingController(text: 'Turkey');
    String kaynakModu = 'yillik_api';
    bool yukleniyor = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('İnternetten Veri Çek'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: sehirCtrl,
                  enabled: !yukleniyor,
                  decoration: const InputDecoration(
                    labelText: 'Şehir (Örn: İstanbul, İzmir, Leuven)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                if (kaynakModu == 'yillik_api')
                  TextField(
                    controller: ulkeCtrl,
                    enabled: !yukleniyor,
                    decoration: const InputDecoration(
                      labelText: 'Ülke (Örn: Turkey, Belgium)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: kaynakModu,
                  onChanged: (v) {
                    if (yukleniyor || v == null) return;
                    setDialogState(() => kaynakModu = v);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        enabled: !yukleniyor,
                        title: const Text('1 Yıllık (Diyanet Metodu API)'),
                        subtitle: const Text('365 gün + Hicri tarih, tüm dünya'),
                        value: 'yillik_api',
                      ),
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        enabled: !yukleniyor,
                        title: const Text('1 Aylık Resmi Diyanet Tablosu'),
                        subtitle: const Text('Türkiye şehirleri (tam Diyanet saati)'),
                        value: 'aylik_diyanet',
                      ),
                    ],
                  ),
                ),
                if (yukleniyor) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  const Text('Vakitler indiriliyor...', style: TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: yukleniyor ? null : () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: yukleniyor
                  ? null
                  : () async {
                      final sehir = sehirCtrl.text.trim();
                      if (sehir.isEmpty) return;
                      setDialogState(() => yukleniyor = true);
                      try {
                        final kayitlar = kaynakModu == 'aylik_diyanet'
                            ? await VeriYonetimServisi.internettenAylikDiyanetCek(sehir)
                            : await VeriYonetimServisi.internettenYillikApiCek(
                                sehir,
                                ulke: ulkeCtrl.text.trim().isEmpty
                                    ? 'Turkey'
                                    : ulkeCtrl.text.trim(),
                              );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _yeniSehirVerisiniKaydetVeSec(sehir, kayitlar);
                      } catch (e) {
                        setDialogState(() => yukleniyor = false);
                        _mesajGoster('İndirme hatası: $e');
                      }
                    },
              child: const Text('Çek ve Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  // --- ŞEHİR SEÇİMİ VE YÖNETİMİ MENÜSÜ (OVERFLOW DÜZELTİLDİ) ---
  void _sehirSecimiYap(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Şehirler ve Veri Kaynağı',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ),
                ...tumSehirIsimleri.map((s) {
                  final ozelMi = ozelSehirDosyalari.containsKey(s);
                  final seciliMi = s == secilenSehir;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      seciliMi ? Icons.check_circle : Icons.location_city,
                      color: seciliMi ? Colors.blue : null,
                    ),
                    title: Text(
                      s,
                      style: TextStyle(
                        fontWeight: seciliMi ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: ozelMi
                        ? const Text('İçe aktarılan / indirilen veri',
                            style: TextStyle(fontSize: 11))
                        : null,
                    trailing: ozelMi && !varsayilanAssetSehirler.containsKey(s)
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () async {
                              final dosyaYolu = ozelSehirDosyalari.remove(s);
                              if (dosyaYolu != null) {
                                final f = File(dosyaYolu);
                                if (await f.exists()) await f.delete();
                              }
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString(
                                  'ozelSehirDosyalari', jsonEncode(ozelSehirDosyalari));
                              if (secilenSehir == s) {
                                secilenSehir = 'Çorum';
                                await prefs.setString('secilenSehir', secilenSehir);
                                await _hizliVeriYukle();
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          )
                        : null,
                    onTap: () {
                      setState(() => secilenSehir = s);
                      _hizliVeriYukle();
                      Navigator.pop(ctx);
                      SharedPreferences.getInstance()
                          .then((p) => p.setString('secilenSehir', s));
                    },
                  );
                }),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.upload_file, color: Colors.teal),
                  title: const Text('Dosyadan İçe Aktar (Diyanet Excel / CSV)'),
                  subtitle: const Text('1 yıllık veya 1 aylık .xlsx / .csv dosyası'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _dosyadanIceAktar();
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud_download_outlined, color: Colors.blue),
                  title: const Text('İnternetten Otomatik Çek (Diyanet)'),
                  subtitle: const Text('Şehir seçip doğrudan indir'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _internettenVeriCekDialogu();
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.open_in_browser, color: Colors.amber),
                  title: const Text('Diyanet Sitesini Aç'),
                  subtitle: const Text('Resmi 1 yıllık Excel indirmek için'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _linkAc('https://namazvakitleri.diyanet.gov.tr');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- TEMA VE GÖRÜNÜM MENÜSÜ (OVERFLOW DÜZELTİLDİ) ---
  void _temaMenusuAc(BuildContext context) {
    final temalar = const [
      ('vakit_dinamik', 'Güneşe / Vakte Bağlı', Icons.wb_twilight),
      ('klasik', 'Klasik (Gündüz / Gece)', Icons.brightness_4),
      ('zumrut', 'Zümrüt Yeşili', Icons.eco_outlined),
      ('gece_mavisi', 'Gece Mavisi', Icons.nights_stay_outlined),
      ('gun_batimi', 'Gün Batımı', Icons.gradient),
      ('minimal_koyu', 'Saf Siyah (AMOLED)', Icons.contrast),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Temalar ve Görünüm',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                  RadioGroup<String>(
                    groupValue: seciliTema,
                    onChanged: (val) async {
                      if (val == null) return;
                      setState(() => seciliTema = val);
                      setSheetState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('seciliTema', val);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: temalar
                          .map((t) => RadioListTile<String>(
                                dense: true,
                                secondary: Icon(t.$3),
                                title: Text(t.$2),
                                value: t.$1,
                              ))
                          .toList(),
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Özel Gün Teması (Altın Geçiş)'),
                    subtitle: const Text('Cuma, Ramazan, Kandiller ve Bayramlar'),
                    value: ozelGunTemasiAktif,
                    onChanged: (val) async {
                      setState(() => ozelGunTemasiAktif = val);
                      setSheetState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('ozelGunTemasiAktif', val);
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    title: const Text('Günün Hadisi / Özlü Söz'),
                    value: sozGoster,
                    onChanged: (val) async {
                      setState(() => sozGoster = val);
                      setSheetState(() {});
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('sozGoster', val);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bugunMu = TarihYardimci.ayniGun(gosterilenTarih, DateTime.now());
    final ozelGun = _aktifOzelGun();
    final contentColor = _getTextColor(isDark, ozelGun);
    final siyahSeritGerekli = !isDark;

    final hicriMetin = (gosterilenVakit != null && gosterilenVakit!.hicriTarih.isNotEmpty)
        ? gosterilenVakit!.hicriTarih
        : TarihYardimci.hicriMetinHesapla(gosterilenTarih);
    final miladiMetin = DateFormat('dd MMMM yyyy', 'tr_TR').format(gosterilenTarih);
    final aktifSoz = diniSozler[aktifSozIndex % diniSozler.length];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: (contentColor == Colors.black87)
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: (contentColor == Colors.black87)
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leadingWidth: 56,
          leading: Center(
            child: Text(
              'NV',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: contentColor,
                letterSpacing: -2,
              ),
            ),
          ),
          title: GestureDetector(
            onTap: () => _sehirSecimiYap(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    secilenSehir,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: contentColor, fontSize: 19),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: contentColor),
              ],
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Tesbih',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(Icons.adjust_rounded, color: contentColor, size: 20),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TesbihSayfasi()),
                );
              },
            ),
            IconButton(
              tooltip: 'Vakit Grafiği',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(Icons.show_chart_rounded, color: contentColor, size: 21),
              onPressed: () {
                if (vakitHaritasi.isEmpty) {
                  _mesajGoster('Grafik için vakit verisi bulunamadı.');
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VakitGrafikSayfasi(
                      sehirAdi: secilenSehir,
                      kayitlar: vakitHaritasi.values.toList()
                        ..sort((a, b) => a.tarih.compareTo(b.tarih)),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Temalar',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(Icons.palette_outlined, color: contentColor, size: 20),
              onPressed: () => _temaMenusuAc(context),
            ),
            IconButton(
              tooltip: 'Karanlık / Açık Mod',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.only(right: 6),
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                color: contentColor,
                size: 20,
              ),
              onPressed: widget.onThemeToggle,
            ),
          ],
        ),
        body: GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 120) return;
            setState(() {
              _satirGuncelle(
                gosterilenTarih.add(Duration(days: v < 0 ? 1 : -1)),
              );
            });
          },
          child: Stack(
            children: [
              // ARKAPLAN GRADIENT
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: _getArkaplanGradient(isDark, aktifIndex, ozelGun),
                ),
              ),

              if (siyahSeritGerekli)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.of(context).padding.top,
                  child: Container(color: Colors.black.withValues(alpha: 0.3)),
                ),

              !veriYuklendi
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        SizedBox(height: MediaQuery.of(context).padding.top + 64),

                        // TARİH SATIRI (BASILI TUTUNCA HİCRİ TARİH GÖSTERİR)
                        GestureDetector(
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            setState(() => hicriGoster = !hicriGoster);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 3),
                            decoration: BoxDecoration(
                              color: contentColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  hicriGoster
                                      ? hicriMetin.toUpperCase()
                                      : miladiMetin.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1.4,
                                    color: contentColor.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (ozelGun != null && bugunMu) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFD54F)
                                          .withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFFFD54F)
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      ozelGun,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFFFE082),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // "VAKTİN ÇIKMASINA" YAZISI VE TAM ARKASINDA YÜZDE İLERLEME BARI
                        if (bugunMu)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 54),
                            child: Container(
                              height: 26,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: contentColor.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned.fill(
                                      child: LinearProgressIndicator(
                                        value: ilerlemeYuzdesi,
                                        backgroundColor: contentColor
                                            .withValues(alpha: 0.10),
                                        color: (ozelGunTemasiAktif &&
                                                ozelGun != null)
                                            ? const Color(0xFFFFD54F)
                                                .withValues(alpha: 0.45)
                                            : (contentColor == Colors.white
                                                ? Colors.blue
                                                    .withValues(alpha: 0.55)
                                                : Colors.black
                                                    .withValues(alpha: 0.22)),
                                      ),
                                    ),
                                    Text(
                                      '         VAKTİN ÇIKMASINA         ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        letterSpacing: 2,
                                        color: contentColor,
                                        fontWeight: FontWeight.bold,
                                        shadows: contentColor == Colors.white
                                            ? const [
                                                Shadow(
                                                  color: Colors.black45,
                                                  blurRadius: 4,
                                                  offset: Offset(0, 1),
                                                ),
                                              ]
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),

                        Text(
                          bugunMu
                              ? kalanSure
                              : DateFormat('EEEE', 'tr_TR')
                                  .format(gosterilenTarih),
                          style: TextStyle(
                            fontSize: bugunMu ? 48 : 34,
                            fontWeight: FontWeight.w900,
                            color: contentColor,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (!bugunMu)
                          TextButton.icon(
                            onPressed: _hizliVeriYukle,
                            icon: Icon(Icons.replay, color: contentColor),
                            label: Text('Bugüne Dön',
                                style: TextStyle(color: contentColor)),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 50, vertical: 8),
                          child: Divider(
                              height: 1,
                              color: contentColor.withValues(alpha: 0.2)),
                        ),

                        // 6 VAKİT LİSTESİ (DAHA KOMPAKT ARALIKLARLA)
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: 6,
                            itemBuilder: (context, i) {
                              final suanMi = bugunMu && i == aktifIndex;
                              final gecmisMi = bugunMu && i < aktifIndex;
                              final saat = (gosterilenVakit != null &&
                                      i < gosterilenVakit!.vakitler.length)
                                  ? gosterilenVakit!.vakitler[i]
                                  : '--:--';

                              final alarmDk = alarmAyarlari[i] ?? -1;
                              final isAlarm = alarmTipleri[i] ?? false;
                              final alarmRenk = isAlarm
                                  ? Colors.purpleAccent
                                  : Colors.blue.withValues(alpha: 0.9);

                              return Opacity(
                                opacity: gecmisMi ? 0.35 : 1.0,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 9),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1.25),
                                  decoration: BoxDecoration(
                                    color: suanMi
                                        ? (isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.15)
                                            : (contentColor == Colors.white
                                                ? Colors.white
                                                    .withValues(alpha: 0.2)
                                                : Colors.black.withValues(
                                                    alpha: 0.05)))
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    border: suanMi
                                        ? Border.all(
                                            color: contentColor, width: 1.5)
                                        : null,
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    minTileHeight: 42,
                                    visualDensity:
                                        const VisualDensity(vertical: -3),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 0),
                                    onLongPress: () =>
                                        _ozelAlarmMenusu(context, i),
                                    leading: Icon(
                                      suanMi
                                          ? Icons.access_time_filled
                                          : (i == 1
                                              ? Icons.wb_sunny
                                              : Icons.circle),
                                      color: i == 1 && !gecmisMi
                                          ? Colors.amber
                                          : (suanMi
                                              ? contentColor
                                              : contentColor
                                                  .withValues(alpha: 0.4)),
                                      size: suanMi ? 26 : 16,
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          vakitIsimleri[i],
                                          style: TextStyle(
                                            fontSize: 22,
                                            color: contentColor,
                                            fontWeight: suanMi
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (alarmDk != -1)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 8.0),
                                            child: Transform.rotate(
                                              angle: -0.2,
                                              child: Text(
                                                alarmDk == 0
                                                    ? '◉'
                                                    : '$alarmDk dk',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: alarmRenk,
                                                  fontStyle: FontStyle.italic,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Text(
                                      saat,
                                      style: TextStyle(
                                        fontSize: 24,
                                        color: contentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // HADİS / ÖZLÜ SÖZ ALANI
                        if (sozGoster)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                aktifSozIndex =
                                    math.Random().nextInt(diniSozler.length);
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(24, 4, 24, 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: contentColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '"${aktifSoz.metin}"',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: contentColor.withValues(alpha: 0.9),
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '— ${aktifSoz.kaynak}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: contentColor.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0, top: 6.0),
                          child: InkWell(
                            onTap: () => _linkAc('https://github.com/esofiso'),
                            child: Column(
                              children: [
                                Container(
                                  width: 180,
                                  height: 2,
                                  decoration: BoxDecoration(
                                    color: contentColor.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '@esofiso | 2026',
                                  style: TextStyle(
                                    color: contentColor.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.bold,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ALARM MENÜSÜ (OVERFLOW KORUMALI) ---
  void _ozelAlarmMenusu(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Hatırlatıcı Ayarla',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                ListTile(
                  title: const Text('Kapat'),
                  leading: const Icon(Icons.alarm_off),
                  onTap: () {
                    alarmDegistir(index, -1);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  title: const Text('Tam Vaktinde'),
                  leading: const Icon(Icons.alarm),
                  onTap: () {
                    alarmDegistir(index, 0, isAlarm: false);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  title: const Text('15 Dakika Kala'),
                  leading: const Icon(Icons.timer),
                  onTap: () {
                    alarmDegistir(index, 15, isAlarm: false);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  title: const Text('30 Dakika Kala'),
                  leading: const Icon(Icons.timer),
                  onTap: () {
                    alarmDegistir(index, 30, isAlarm: false);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  title: const Text('60 Dakika Kala'),
                  leading: const Icon(Icons.timer),
                  onTap: () {
                    alarmDegistir(index, 60, isAlarm: false);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  title: const Text('Özel Ayarla...'),
                  subtitle: const Text('Dakika ve Alarm Modu'),
                  leading: const Icon(Icons.edit_note),
                  onTap: () {
                    Navigator.pop(ctx);
                    _ozelDakikaGirisi(context, index);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _ozelDakikaGirisi(BuildContext context, int index) {
    final controller = TextEditingController();
    bool isAlarmMode = alarmTipleri[index] ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Özel Hatırlatıcı'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Örn: 45, 75...',
                    labelText: 'Kaç dakika önce?',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('Alarm Modu'),
                  subtitle: Text(
                    isAlarmMode
                        ? 'Sürekli çalar (Mor)'
                        : 'Tek bildirim sesi (Mavi)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  secondary: Icon(
                    isAlarmMode ? Icons.access_alarm : Icons.notifications_none,
                    color: isAlarmMode ? Colors.deepPurple : Colors.blue,
                  ),
                  value: isAlarmMode,
                  activeThumbColor: Colors.deepPurple,
                  onChanged: (val) => setStateDialog(() => isAlarmMode = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                final dk = int.tryParse(controller.text);
                if (dk != null && dk >= 0) {
                  alarmDegistir(index, dk, isAlarm: isAlarmMode);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 6. TESBİH SAYFASI (SİMSİYAH TAM EKRAN, 33'LÜK SAYAÇ + TUR + TİTREŞİM)
// ============================================================================

class TesbihSayfasi extends StatefulWidget {
  const TesbihSayfasi({super.key});
  @override
  State<TesbihSayfasi> createState() => _TesbihSayfasiState();
}

class _TesbihSayfasiState extends State<TesbihSayfasi> {
  int _sayac = 0; // 0..32 (33 olunca sıfırlanır)
  int _tur = 0;   // Her 33'te 1 artar

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _yukle();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _yukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sayac = prefs.getInt('tesbih_sayac') ?? 0;
      _tur = prefs.getInt('tesbih_tur') ?? 0;
    });
  }

  Future<void> _kaydet() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tesbih_sayac', _sayac);
    await prefs.setInt('tesbih_tur', _tur);
  }

  void _artir() {
    setState(() {
      _sayac += 1;
      if (_sayac >= 33) {
        _sayac = 0;
        _tur += 1;
        HapticFeedback.vibrate();
      }
    });
    _kaydet();
  }

  void _sifirla() {
    HapticFeedback.selectionClick();
    setState(() {
      _sayac = 0;
      _tur = 0;
    });
    _kaydet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _artir,
        child: Stack(
          children: [
            // Ortada küçük iki sayı
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_sayac',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                      color: Color(0x99FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$_tur',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Color(0x55FFFFFF),
                    ),
                  ),
                ],
              ),
            ),

            // Sol üstte çok soluk çıkış ikonu
            Positioned(
              top: 24,
              left: 12,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    size: 16, color: Color(0x28FFFFFF)),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Sağ altta çok soluk sıfırlama ikonu
            Positioned(
              bottom: 20,
              right: 14,
              child: IconButton(
                icon: const Icon(Icons.refresh,
                    size: 18, color: Color(0x28FFFFFF)),
                onPressed: _sifirla,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. ETKİLEŞİMLİ (KAYDIRILABİLİR & YAKINLAŞTIRILABİLİR) VAKİT GRAFİĞİ
// ============================================================================

class VakitGrafikSayfasi extends StatefulWidget {
  final String sehirAdi;
  final List<GunlukVakit> kayitlar;

  const VakitGrafikSayfasi({
    super.key,
    required this.sehirAdi,
    required this.kayitlar,
  });

  @override
  State<VakitGrafikSayfasi> createState() => _VakitGrafikSayfasiState();
}

class _VakitGrafikSayfasiState extends State<VakitGrafikSayfasi> {
  static const List<String> _vakitAdlari = [
    'İmsak',
    'Güneş',
    'Öğle',
    'İkindi',
    'Akşam',
    'Yatsı',
  ];

  static const List<Color> _renkler = [
    Color(0xFF38BDF8),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFFFB923C),
    Color(0xFFF43F5E),
    Color(0xFFA78BFA),
  ];

  int _seciliVakit = -1; // -1 = Tümü, 0..5 = tek vakit
  double _xMin = 0;
  double _xMax = 30;
  double _yMin = 0;
  double _yMax = 1440;

  double _baslangicXMin = 0;
  double _baslangicXMax = 30;
  double _baslangicYMin = 0;
  double _baslangicYMax = 1440;
  Offset _baslangicFocal = Offset.zero;

  int? _seciliGunIndex;
  int _bugunIndex = -1;

  late List<List<double>> _seriler; // [6][N] dakika cinsinden

  @override
  void initState() {
    super.initState();
    _veriyiHazirla();
    _gorunumuSifirla();
  }

  void _veriyiHazirla() {
    _seriler = List.generate(6, (_) => <double>[]);
    final bugun = DateTime.now();
    for (int idx = 0; idx < widget.kayitlar.length; idx++) {
      final k = widget.kayitlar[idx];
      if (TarihYardimci.ayniGun(k.tarih, bugun)) {
        _bugunIndex = idx;
        _seciliGunIndex = idx;
      }
      for (int v = 0; v < 6; v++) {
        final p = k.vakitler[v].split(':');
        final dk = (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
        _seriler[v].add(dk.toDouble());
      }
    }
  }

  void _gorunumuSifirla() {
    final n = widget.kayitlar.length;
    if (n <= 1) {
      _xMin = 0;
      _xMax = 1;
    } else if (n > 45 && _bugunIndex != -1) {
      // Yıllık veride varsayılan olarak bugünün etrafında ~35 günlük pencere aç (serbestçe kaydırılabilir)
      _xMin = math.max(-0.5, _bugunIndex - 15.0);
      _xMax = math.min(n - 0.5, _xMin + 35.0);
    } else {
      _xMin = -0.5;
      _xMax = n - 0.5;
    }

    _yAraliginiHesapla();
  }

  void _yAraliginiHesapla() {
    final bas = _xMin.floor().clamp(0, widget.kayitlar.length - 1);
    final bit = _xMax.ceil().clamp(0, widget.kayitlar.length - 1);
    final vakitIndeksleri =
        _seciliVakit == -1 ? [0, 1, 2, 3, 4, 5] : [_seciliVakit];

    double mn = 1440;
    double mx = 0;
    for (final v in vakitIndeksleri) {
      for (int i = bas; i <= bit; i++) {
        final val = _seriler[v][i];
        if (val < mn) mn = val;
        if (val > mx) mx = val;
      }
    }
    final pad = _seciliVakit == -1 ? 45.0 : 12.0;
    if (mx - mn < 10) {
      mn -= 10;
      mx += 10;
    }
    _yMin = (mn - pad).clamp(0.0, 1400.0);
    _yMax = (mx + pad).clamp(40.0, 1440.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secilenKayit = (_seciliGunIndex != null &&
            _seciliGunIndex! >= 0 &&
            _seciliGunIndex! < widget.kayitlar.length)
        ? widget.kayitlar[_seciliGunIndex!]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.sehirAdi} — Vakit Grafiği'),
        actions: [
          IconButton(
            tooltip: 'Tüm Veriyi Sığdır',
            icon: const Icon(Icons.fit_screen),
            onPressed: () {
              setState(() {
                _xMin = -0.5;
                _xMax = math.max(1.0, widget.kayitlar.length - 0.5);
                _yAraliginiHesapla();
              });
            },
          ),
          IconButton(
            tooltip: 'Sıfırla',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => setState(_gorunumuSifirla),
          ),
        ],
      ),
      body: Column(
        children: [
          // Vakit filtre çipleri
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _seciliVakit == -1,
                    onSelected: (_) => setState(() {
                      _seciliVakit = -1;
                      _yAraliginiHesapla();
                    }),
                  ),
                ),
                for (int i = 0; i < 6; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: _renkler[i],
                        radius: 5,
                      ),
                      label: Text(_vakitAdlari[i]),
                      selected: _seciliVakit == i,
                      onSelected: (_) => setState(() {
                        _seciliVakit = i;
                        _yAraliginiHesapla();
                      }),
                    ),
                  ),
              ],
            ),
          ),

          // Grafik Alanı (Kaydırılabilir & Yakınlaştırılabilir)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const marginLeft = 52.0;
                const marginRight = 16.0;
                const marginTop = 16.0;
                const marginBottom = 36.0;
                final plotWidth =
                    math.max(10.0, constraints.maxWidth - marginLeft - marginRight);
                final plotHeight =
                    math.max(10.0, constraints.maxHeight - marginTop - marginBottom);

                return GestureDetector(
                  onTapUp: (details) {
                    final local = details.localPosition;
                    final oran = ((local.dx - marginLeft) / plotWidth).clamp(0.0, 1.0);
                    final idx = (_xMin + oran * (_xMax - _xMin)).round();
                    if (idx >= 0 && idx < widget.kayitlar.length) {
                      setState(() => _seciliGunIndex = idx);
                    }
                  },
                  onScaleStart: (details) {
                    _baslangicXMin = _xMin;
                    _baslangicXMax = _xMax;
                    _baslangicYMin = _yMin;
                    _baslangicYMax = _yMax;
                    _baslangicFocal = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    final origXSpan = _baslangicXMax - _baslangicXMin;
                    final origYSpan = _baslangicYMax - _baslangicYMin;

                    final scale = details.scale.clamp(0.25, 6.0);
                    final newXSpan = (origXSpan / scale)
                        .clamp(4.0, math.max(10.0, widget.kayitlar.length + 2.0));
                    final newYSpan = (origYSpan / scale).clamp(15.0, 1440.0);

                    final dxPx = details.localFocalPoint.dx - _baslangicFocal.dx;
                    final dyPx = details.localFocalPoint.dy - _baslangicFocal.dy;

                    final rx = ((_baslangicFocal.dx - marginLeft) / plotWidth)
                        .clamp(0.0, 1.0);
                    final ry = ((marginTop + plotHeight - _baslangicFocal.dy) /
                            plotHeight)
                        .clamp(0.0, 1.0);

                    final focalXData = _baslangicXMin + rx * origXSpan;
                    final focalYData = _baslangicYMin + ry * origYSpan;

                    final panX = -dxPx / plotWidth * newXSpan;
                    final panY = dyPx / plotHeight * newYSpan;

                    setState(() {
                      _xMin = focalXData - rx * newXSpan + panX;
                      _xMax = _xMin + newXSpan;
                      _yMin = (focalYData - ry * newYSpan + panY).clamp(-60.0, 1400.0);
                      _yMax = (_yMin + newYSpan).clamp(40.0, 1500.0);
                    });
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _VakitGrafikPainter(
                      kayitlar: widget.kayitlar,
                      seriler: _seriler,
                      renkler: _renkler,
                      seciliVakit: _seciliVakit,
                      xMin: _xMin,
                      xMax: _xMax,
                      yMin: _yMin,
                      yMax: _yMax,
                      bugunIndex: _bugunIndex,
                      seciliGunIndex: _seciliGunIndex,
                      isDark: isDark,
                    ),
                  ),
                );
              },
            ),
          ),

          // Seçili Günün Vakit Özet Kartı
          if (secilenKayit != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF181C24) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF2D3442) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '${DateFormat('dd MMMM yyyy EEEE', 'tr_TR').format(secilenKayit.tarih)}  •  ${secilenKayit.hicriTarih}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(6, (i) {
                      final vurgulu = _seciliVakit == -1 || _seciliVakit == i;
                      return Opacity(
                        opacity: vurgulu ? 1.0 : 0.35,
                        child: Column(
                          children: [
                            Text(
                              _vakitAdlari[i],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _renkler[i],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              secilenKayit.vakitler[i],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VakitGrafikPainter extends CustomPainter {
  final List<GunlukVakit> kayitlar;
  final List<List<double>> seriler;
  final List<Color> renkler;
  final int seciliVakit;
  final double xMin, xMax, yMin, yMax;
  final int bugunIndex;
  final int? seciliGunIndex;
  final bool isDark;

  _VakitGrafikPainter({
    required this.kayitlar,
    required this.seriler,
    required this.renkler,
    required this.seciliVakit,
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.bugunIndex,
    required this.seciliGunIndex,
    required this.isDark,
  });

  double _uygunAdim(double aralik, List<double> adaylar, int hedef) {
    for (final a in adaylar) {
      if (aralik / a <= hedef + 2) return a;
    }
    return adaylar.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 52.0;
    const right = 16.0;
    const top = 16.0;
    const bottom = 36.0;
    final rect = Rect.fromLTWH(
      left,
      top,
      math.max(10, size.width - left - right),
      math.max(10, size.height - top - bottom),
    );

    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF101319) : const Color(0xFFFFFFFF);
    canvas.drawRect(rect, bgPaint);

    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF242A36) : const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    final textColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    Offset toScreen(double x, double y) {
      final sx = rect.left + (x - xMin) / (xMax - xMin) * rect.width;
      final sy = rect.bottom - (y - yMin) / (yMax - yMin) * rect.height;
      return Offset(sx, sy);
    }

    // Y ekseni (Saatler)
    final yStep = _uygunAdim(
        (yMax - yMin).abs(), [5, 10, 15, 30, 60, 120, 180, 240], 6);
    var yVal = (yMin / yStep).floor() * yStep;
    while (yVal <= yMax + yStep) {
      if (yVal >= yMin && yVal <= yMax && yVal >= 0 && yVal < 1440) {
        final pt = toScreen(xMin, yVal);
        canvas.drawLine(Offset(rect.left, pt.dy), Offset(rect.right, pt.dy), gridPaint);
        final saatStr =
            '${(yVal ~/ 60).toString().padLeft(2, '0')}:${(yVal.toInt() % 60).toString().padLeft(2, '0')}';
        final tp = TextPainter(
          text: TextSpan(
            text: saatStr,
            style: TextStyle(color: textColor, fontSize: 10.5),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(rect.left - tp.width - 6, pt.dy - tp.height / 2));
      }
      yVal += yStep;
    }

    // X ekseni (Günler)
    final xStep = _uygunAdim(
        (xMax - xMin).abs(), [1, 2, 5, 7, 15, 30, 60], 6).toInt();
    var xVal = math.max(0, (xMin / xStep).floor() * xStep);
    while (xVal < kayitlar.length && xVal <= xMax + xStep) {
      if (xVal >= xMin && xVal <= xMax) {
        final pt = toScreen(xVal.toDouble(), yMin);
        canvas.drawLine(Offset(pt.dx, rect.top), Offset(pt.dx, rect.bottom), gridPaint);
        final d = kayitlar[xVal].tarih;
        final etiket = '${d.day}.${d.month.toString().padLeft(2, '0')}';
        final tp = TextPainter(
          text: TextSpan(
            text: etiket,
            style: TextStyle(color: textColor, fontSize: 10.5),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pt.dx - tp.width / 2, rect.bottom + 6));
      }
      xVal += xStep;
    }

    // Çerçeve
    canvas.drawRect(
      rect,
      Paint()
        ..color = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke,
    );

    canvas.save();
    canvas.clipRect(rect);

    // Bugün dikey çizgisi
    if (bugunIndex >= 0 && bugunIndex >= xMin && bugunIndex <= xMax) {
      final bx = toScreen(bugunIndex.toDouble(), yMin).dx;
      canvas.drawLine(
        Offset(bx, rect.top),
        Offset(bx, rect.bottom),
        Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.7)
          ..strokeWidth = 1.4,
      );
    }

    // Seçili gün vurgusu
    if (seciliGunIndex != null &&
        seciliGunIndex! >= 0 &&
        seciliGunIndex! >= xMin &&
        seciliGunIndex! <= xMax) {
      final sx = toScreen(seciliGunIndex!.toDouble(), yMin).dx;
      canvas.drawLine(
        Offset(sx, rect.top),
        Offset(sx, rect.bottom),
        Paint()
          ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );
    }

    // Vakit eğrileri
    final cizilecekler =
        seciliVakit == -1 ? [0, 1, 2, 3, 4, 5] : [seciliVakit];
    final bas = math.max(0, xMin.floor() - 1);
    final bit = math.min(kayitlar.length - 1, xMax.ceil() + 1);

    for (final v in cizilecekler) {
      final path = Path();
      bool ilk = true;
      final linePaint = Paint()
        ..color = renkler[v]
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;

      for (int i = bas; i <= bit; i++) {
        final pt = toScreen(i.toDouble(), seriler[v][i]);
        if (ilk) {
          path.moveTo(pt.dx, pt.dy);
          ilk = false;
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(path, linePaint);

      // Yakınlaştırıldığında noktaları da göster
      if ((xMax - xMin) <= 45) {
        final dotPaint = Paint()..color = renkler[v];
        for (int i = bas; i <= bit; i++) {
          final pt = toScreen(i.toDouble(), seriler[v][i]);
          final r = (i == seciliGunIndex) ? 4.5 : 2.4;
          canvas.drawCircle(pt, r, dotPaint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VakitGrafikPainter oldDelegate) => true;
}