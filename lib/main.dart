// @esofiso
// 12.01.2026

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:home_widget/home_widget.dart';

// --- GELİŞMİŞ BİLDİRİM SERVİSİ (GÜNCELLENDİ) ---
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

  // 1. KANAL: STANDART BİLDİRİM (Mavi, Tek Ses)
  AndroidNotificationDetails get _standardDetails =>
      const AndroidNotificationDetails(
        'nvapp_standard_v1', // Kanal ID
        'Standart Hatırlatıcı',
        importance: Importance.max,
        priority: Priority.high,
        color: Colors.blue, // Uygulama mavisi
        playSound: true,
        category: AndroidNotificationCategory.reminder,
      );

  // 2. KANAL: ALARM MODU (Mor, Sürekli Çalar)
  AndroidNotificationDetails get _alarmDetails => AndroidNotificationDetails(
        'nvapp_alarm_mode_v1', // Kanal ID
        'Alarm Modu',
        importance: Importance.max,
        priority: Priority.max,
        color: Colors.deepPurple, // Mor renk
        playSound: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        // Bu flag (4) bildirimin kullanıcı dokunana kadar susmamasını sağlar (Insistent)
        additionalFlags: Int32List.fromList(<int>[4]),
      );

  Future<void> bildirimKur(int id, String vakitAdi, DateTime vakit,
      int dakikaKala, bool isAlarm) async {
    final hedef = vakit.subtract(Duration(minutes: dakikaKala));
    if (hedef.isBefore(DateTime.now())) {
      return;
    }

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        dakikaKala == 0
            ? '$vakitAdi Vakti Girdi!'
            : '$vakitAdi Vaktine $dakikaKala dk Kaldı',
        isAlarm ? 'Alarmı kapatmak için dokunun' : 'Vakit hatırlatıcısı',
        tz.TZDateTime.from(hedef, tz.local),
        NotificationDetails(
          // Seçime göre kanal detayını belirliyoruz
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

class AnaSayfa extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const AnaSayfa({super.key, required this.onThemeToggle});
  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  Map<String, String> sehirDosyalari = {
    "Çorum": "vakitler_corum.csv",
    "Niğde": "vakitler_nigde.csv",
    "Ankara": "vakitler_ankara.csv"
  };
  String secilenSehir = "Çorum";

  List<String> tumSatirlar = [];
  String? bugunkuSatirHam;

  String kalanSure = "--:--:--";
  double ilerlemeYuzdesi = 0.0;
  int aktifIndex = -1;
  DateTime gosterilenTarih = DateTime.now();
  bool veriYuklendi = false;

  final List<String> vakitIsimleri = [
    "İmsak",
    "Güneş",
    "Öğle",
    "İkindi",
    "Akşam",
    "Yatsı"
  ];
  Map<int, int> alarmAyarlari = {};
  Map<int, bool> alarmTipleri = {}; // YENİ: Alarm tipi (false=Standart, true=Alarm)

  @override
  void initState() {
    super.initState();
    _veriVeAyarlariYukle();
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && veriYuklendi) {
        _sayaciGuncelle();
      }
    });
  }

  Future<void> _veriVeAyarlariYukle() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }

    setState(() {
      secilenSehir = prefs.getString('secilenSehir') ?? "Çorum";
      for (int i = 0; i < 6; i++) {
        alarmAyarlari[i] = prefs.getInt('alarm_$i') ?? -1;
        // Tip verisini yükle, yoksa false (Standart) kabul et
        alarmTipleri[i] = prefs.getBool('alarm_type_$i') ?? false;
      }
    });

    await _hizliVeriYukle();
  }

  Future<void> _hizliVeriYukle() async {
    try {
      final rawData =
          await rootBundle.loadString("assets/${sehirDosyalari[secilenSehir]}");

      tumSatirlar = const LineSplitter().convert(rawData);

      DateTime simdi = DateTime.now();
      _gunuBelirle(simdi);

      setState(() => veriYuklendi = true);

      _alarmlariYonet();
    } catch (_) {}
  }

  void _gunuBelirle(DateTime referansTarih) {
    String arananTarih =
        DateFormat('dd MMMM yyyy', 'tr_TR').format(referansTarih);

    int index = tumSatirlar.indexWhere((line) => line.contains(arananTarih));

    if (index != -1) {
      String hamVeri = tumSatirlar[index];
      List<String> parcalar = hamVeri.split(',');

      List<String> yatsiP = parcalar[7].trim().split(':');
      DateTime yatsiVakti = DateTime(referansTarih.year, referansTarih.month,
          referansTarih.day, int.parse(yatsiP[0]), int.parse(yatsiP[1]));

      if (DateFormat('yMd').format(referansTarih) ==
              DateFormat('yMd').format(DateTime.now()) &&
          DateTime.now().isAfter(yatsiVakti)) {
        gosterilenTarih = referansTarih.add(const Duration(days: 1));
        String yarinTarih =
            DateFormat('dd MMMM yyyy', 'tr_TR').format(gosterilenTarih);
        bugunkuSatirHam = tumSatirlar
            .firstWhere((line) => line.contains(yarinTarih), orElse: () => "");
      } else {
        gosterilenTarih = referansTarih;
        bugunkuSatirHam = hamVeri;
      }
    }
  }

  void _satirGuncelle(DateTime tarih) {
    String aranan = DateFormat('dd MMMM yyyy', 'tr_TR').format(tarih);
    bugunkuSatirHam = tumSatirlar.firstWhere((line) => line.contains(aranan),
        orElse: () => "");
  }

  // ALARM DEĞİŞTİRME FONKSİYONU GÜNCELLENDİ
  Future<void> alarmDegistir(int index, int dakika,
      {bool isAlarm = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('alarm_$index', dakika);
    await prefs.setBool('alarm_type_$index', isAlarm); // Tipi kaydet

    setState(() {
      alarmAyarlari[index] = dakika;
      alarmTipleri[index] = isAlarm;
    });
    _alarmlariYonet();
  }

  Future<void> _alarmlariYonet() async {
    if (tumSatirlar.isEmpty) {
      return;
    }

    await notificationService.iptalEt();

    for (int gunOffset = 0; gunOffset < 3; gunOffset++) {
      DateTime hedefGun = DateTime.now().add(Duration(days: gunOffset));
      String arananGun = DateFormat('dd MMMM yyyy', 'tr_TR').format(hedefGun);

      String satir = tumSatirlar
          .firstWhere((line) => line.contains(arananGun), orElse: () => "");

      if (satir.isNotEmpty) {
        List<String> parcalar = satir.split(',');
        for (int i = 0; i < 6; i++) {
          if (alarmAyarlari[i] != -1) {
            try {
              List<String> p = parcalar[i + 2].trim().split(':');
              DateTime v = DateTime(hedefGun.year, hedefGun.month, hedefGun.day,
                  int.parse(p[0]), int.parse(p[1]));

              // Tipi kontrol et (true ise Alarm, false ise Standart)
              bool isAlarm = alarmTipleri[i] ?? false;

              notificationService.bildirimKur((gunOffset * 10) + i,
                  vakitIsimleri[i], v, alarmAyarlari[i]!, isAlarm);
            } catch (_) {
              continue;
            }
          }
        }
      }
    }
  }

  void _sayaciGuncelle() {
    if (bugunkuSatirHam == null || bugunkuSatirHam!.isEmpty) {
      return;
    }

    DateTime simdi = DateTime.now();
    String bugunStr = DateFormat('dd MMMM yyyy', 'tr_TR').format(simdi);

    String referansSatir = (DateFormat('yMd').format(gosterilenTarih) ==
            DateFormat('yMd').format(simdi))
        ? bugunkuSatirHam!
        : tumSatirlar.firstWhere((l) => l.contains(bugunStr), orElse: () => "");

    if (referansSatir.isEmpty) {
      return;
    }

    List<String> parcalar = referansSatir.split(',');
    int bulunanIndex = -1;
    DateTime? hedefZaman;
    DateTime? baslangicZamani;

    for (int i = 0; i < 6; i++) {
      try {
        List<String> p = parcalar[i + 2].trim().split(':');
        DateTime tamVakit = DateTime(simdi.year, simdi.month, simdi.day,
            int.parse(p[0]), int.parse(p[1]));
        if (simdi.isBefore(tamVakit)) {
          if (bulunanIndex == -1) {
            bulunanIndex = i - 1;
            hedefZaman = tamVakit;
            if (i > 0) {
              List<String> prevP = parcalar[i + 1].trim().split(':');
              baslangicZamani = DateTime(simdi.year, simdi.month, simdi.day,
                  int.parse(prevP[0]), int.parse(prevP[1]));
            }
          }
        }
      } catch (_) {
        continue;
      }
    }

    List<String> yatsiP = parcalar[7].trim().split(':');
    DateTime yatsiVakti = DateTime(simdi.year, simdi.month, simdi.day,
        int.parse(yatsiP[0]), int.parse(yatsiP[1]));

    if (bulunanIndex == -1) {
      if (simdi.isBefore(yatsiVakti)) {
        bulunanIndex = 4;
      } else {
        bulunanIndex = 5;
      }
    }

    if (mounted) {
      setState(() {
        aktifIndex = bulunanIndex;
        if (DateFormat('yMd').format(gosterilenTarih) ==
                DateFormat('yMd').format(simdi) &&
            hedefZaman != null) {
          Duration f = hedefZaman.difference(simdi);
          kalanSure =
              "${f.inHours.toString().padLeft(2, '0')}:${(f.inMinutes % 60).toString().padLeft(2, '0')}:${(f.inSeconds % 60).toString().padLeft(2, '0')}";

          if (baslangicZamani != null) {
            ilerlemeYuzdesi = (simdi.difference(baslangicZamani).inSeconds /
                    hedefZaman.difference(baslangicZamani).inSeconds)
                .clamp(0.0, 1.0);
          }
        } else {
          kalanSure = "--:--:--";
        }
      });

      String sonraki = (aktifIndex == -1 || aktifIndex >= 5)
          ? "İmsak"
          : vakitIsimleri[(aktifIndex + 1) % 6];
      HomeWidget.saveWidgetData('vakit_adi', sonraki);
      HomeWidget.saveWidgetData('kalan_sure', kalanSure);
      HomeWidget.updateWidget(name: 'HomeScreenWidgetProvider');
    }
  }

  // --- TEMA FONKSİYONLARI ---
  LinearGradient _getVakitGradient(bool isDark, int index) {
    if (isDark) {
      switch (index) {
        case 0:
          return const LinearGradient(
              colors: [Color(0xFF000000), Color(0xFF0F2027)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 1:
          return const LinearGradient(
              colors: [Color(0xFF232526), Color(0xFF414345)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 2:
          return const LinearGradient(
              colors: [Color(0xFF141E30), Color(0xFF243B55)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 3:
          return const LinearGradient(
              colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 4:
          return const LinearGradient(
              colors: [Color(0xFF0f0c29), Color(0xFF302b63)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 5:
          return const LinearGradient(
              colors: [Color(0xFF000000), Color(0xFF1A1A2E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        default:
          return const LinearGradient(
              colors: [Colors.black, Colors.grey],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
      }
    } else {
      switch (index) {
        case 0:
          return const LinearGradient(
              colors: [Color(0xFF2b5876), Color(0xFF4e4376)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 1:
          return const LinearGradient(
              colors: [Color.fromARGB(255, 218, 168, 114), Color.fromARGB(255, 228, 199, 119)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 2:
          return const LinearGradient(
              colors: [Color(0xFF6DD5FA), Color.fromARGB(255, 20, 63, 91)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 3:
          return const LinearGradient(
              colors: [Color(0xFFE67E22), Color(0xFF2C3E50)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 4:
          return const LinearGradient(
              colors: [Color(0xFFc31432), Color(0xFF240b36)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        case 5:
          return const LinearGradient(
              colors: [Color(0xFF141E30), Color(0xFF243B55)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
        default:
          return const LinearGradient(
              colors: [Colors.blue, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter);
      }
    }
  }

  Color _getTextColor(bool isDark) {
    if (isDark) {
      return Colors.white;
    }
    if (aktifIndex == 1) {
      return Colors.black87;
    }
    return Colors.white;
  }

  Future<void> _githubLinkiniAc() async {
    final Uri url = Uri.parse('https://github.com/esofiso');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {}
    } catch (_) {}
  }

  void _sehirSecimiYap(BuildContext context) {
    showModalBottomSheet(
        context: context,
        builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: sehirDosyalari.keys
                .map((s) => ListTile(
                    title: Text(s),
                    onTap: () {
                      setState(() {
                        secilenSehir = s;
                      });
                      _hizliVeriYukle();
                      Navigator.pop(ctx);
                      SharedPreferences.getInstance()
                          .then((p) => p.setString('secilenSehir', s));
                    }))
                .toList()));
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool bugunMu = DateFormat('yMd').format(gosterilenTarih) ==
        DateFormat('yMd').format(DateTime.now());

    Color contentColor = _getTextColor(isDark);
    bool siyahSeritGerekli = !isDark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: (!isDark && aktifIndex == 1)
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: (!isDark && aktifIndex == 1)
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leadingWidth: 70,
          leading: Center(
              child: Text("NV",
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: contentColor,
                      letterSpacing: -2))),
          title: GestureDetector(
              onTap: () => _sehirSecimiYap(context),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(secilenSehir, style: TextStyle(color: contentColor)),
                Icon(Icons.arrow_drop_down, color: contentColor)
              ])),
          centerTitle: true,
          actions: [
            IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                    color: contentColor),
                onPressed: widget.onThemeToggle)
          ],
        ),
        body: GestureDetector(
          onHorizontalDragEnd: (d) => setState(() {
            gosterilenTarih = gosterilenTarih
                .add(Duration(days: d.primaryVelocity! < 0 ? 1 : -1));
            _satirGuncelle(gosterilenTarih);
          }),
          child: Stack(
            children: [
              // ARKAPLAN GRADIENT
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                    gradient: _getVakitGradient(isDark, aktifIndex)),
              ),

              // SİYAH ŞERİT
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
                        const SizedBox(height: 100),
                        Text(
                            bugunMu
                                ? "VAKTİN ÇIKMASINA"
                                : DateFormat('dd MMMM yyyy', 'tr_TR')
                                    .format(gosterilenTarih)
                                    .toUpperCase(),
                            style: TextStyle(
                                letterSpacing: 2,
                                color: Colors.blue.withValues(alpha: 0.9),
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(
                            bugunMu
                                ? kalanSure
                                : DateFormat('EEEE', 'tr_TR')
                                    .format(gosterilenTarih),
                            style: TextStyle(
                                fontSize: bugunMu ? 54 : 36,
                                fontWeight: FontWeight.w900,
                                color: contentColor,
                                fontFamily: 'monospace')),
                        const SizedBox(height: 20),
                        if (bugunMu)
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 50),
                              child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                      value: ilerlemeYuzdesi,
                                      minHeight: 8,
                                      backgroundColor:
                                          contentColor.withValues(alpha: 0.1),
                                      color: contentColor == Colors.white
                                          ? Colors.blue
                                          : Colors.black))),
                        if (!bugunMu)
                          TextButton.icon(
                              onPressed: () {
                                _hizliVeriYukle();
                              },
                              icon: Icon(Icons.replay, color: contentColor),
                              label: Text("Bugüne Dön",
                                  style: TextStyle(color: contentColor))),
                        Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 50, vertical: 20),
                            child: Divider(
                                color: contentColor.withValues(alpha: 0.2))),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: 6,
                            itemBuilder: (context, i) {
                              bool suanMi = bugunMu && i == aktifIndex;
                              bool gecmisMi = bugunMu && i < aktifIndex;

                              String saat = "--:--";
                              if (bugunkuSatirHam != null &&
                                  bugunkuSatirHam!.isNotEmpty) {
                                saat = bugunkuSatirHam!
                                    .split(',')[i + 2]
                                    .trim();
                              }

                              int alarmDk = alarmAyarlari[i] ?? -1;
                              bool isAlarm = alarmTipleri[i] ?? false;

                              // Görsel ayrıştırma için renk seçimi
                              Color alarmRenk = isAlarm
                                  ? Colors.purpleAccent
                                  : Colors.blue.withValues(alpha: 0.9);

                              return Opacity(
                                opacity: gecmisMi ? 0.35 : 1.0,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 25, vertical: 4),
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
                                      borderRadius: BorderRadius.circular(15),
                                      border: suanMi
                                          ? Border.all(
                                              color: contentColor, width: 1.5)
                                          : null),
                                  child: ListTile(
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
                                        size: suanMi ? 24 : 14),
                                    title: Row(children: [
                                      Text(vakitIsimleri[i],
                                          style: TextStyle(
                                              fontSize: 18,
                                              color: contentColor,
                                              fontWeight: suanMi
                                                  ? FontWeight.bold
                                                  : FontWeight.normal)),
                                      if (alarmDk != -1)
                                        Padding(
                                            padding: const EdgeInsets.only(
                                                left: 8.0),
                                            child: Transform.rotate(
                                                angle: -0.2,
                                                child: Text(
                                                    alarmDk == 0
                                                        ? "◉"
                                                        : "$alarmDk dk",
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: alarmRenk, // MOR veya MAVİ
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        fontWeight: FontWeight
                                                            .bold))))
                                    ]),
                                    trailing: Text(saat,
                                        style: TextStyle(
                                            fontSize: 20,
                                            color: contentColor,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                            padding: const EdgeInsets.only(
                                bottom: 20.0, top: 15.0),
                            child: InkWell(
                                onTap: _githubLinkiniAc,
                                child: Column(children: [
                                  Container(
                                    width: 180,
                                    height: 2,
                                    decoration: BoxDecoration(
                                        color: contentColor.withValues(
                                            alpha: 0.3),
                                        borderRadius: BorderRadius.circular(2)),
                                  ),
                                  const SizedBox(height: 8),
                                  Text("@esofiso | 2026",
                                      style: TextStyle(
                                          color: contentColor
                                              .withValues(alpha: 0.6),
                                          fontWeight: FontWeight.bold,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 12))
                                  ]))),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // GÜNCELLENMİŞ MENÜ YAPISI
  void _ozelAlarmMenusu(BuildContext context, int index) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Hatırlatıcı Ayarla",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18))),
              ListTile(
                  title: const Text("Kapat"),
                  leading: const Icon(Icons.alarm_off),
                  onTap: () {
                    alarmDegistir(index, -1);
                    Navigator.pop(ctx);
                  }),
              // Hızlı seçenekler "Standart" (false) olarak ayarlandı
              ListTile(
                  title: const Text("Tam Vaktinde"),
                  leading: const Icon(Icons.alarm),
                  onTap: () {
                    alarmDegistir(index, 0, isAlarm: false);
                    Navigator.pop(ctx);
                  }),
              ListTile(
                  title: const Text("15 Dakika Kala"),
                  leading: const Icon(Icons.timer),
                  onTap: () {
                    alarmDegistir(index, 15, isAlarm: false);
                    Navigator.pop(ctx);
                  }),
              ListTile(
                  title: const Text("30 Dakika Kala"),
                  leading: const Icon(Icons.timer),
                  onTap: () {
                    alarmDegistir(index, 30, isAlarm: false);
                    Navigator.pop(ctx);
                  }),
              ListTile(
                  title: const Text("60 Dakika Kala"),
                  leading: const Icon(Icons.timer),
                  onTap: () {
                    alarmDegistir(index, 60, isAlarm: false);
                    Navigator.pop(ctx);
                  }),
              ListTile(
                  title: const Text("Özel Ayarla..."),
                  subtitle: const Text("Dakika ve Alarm Modu"),
                  leading: const Icon(Icons.edit_note),
                  onTap: () {
                    Navigator.pop(ctx);
                    _ozelDakikaGirisi(context, index);
                  }),
              const SizedBox(height: 20)
            ])));
  }

  void _ozelDakikaGirisi(BuildContext context, int index) {
    TextEditingController controller = TextEditingController();
    bool isAlarmMode = false; // Varsayılan kapalı

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            // Dialog içi state değişimi için gerekli
            builder: (context, setStateDialog) {
              return AlertDialog(
                  title: const Text("Özel Hatırlatıcı"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          decoration: const InputDecoration(
                              hintText: "Örn: 45, 75...",
                              labelText: "Kaç dakika önce?",
                              border: OutlineInputBorder())),
                      const SizedBox(height: 20),
                      SwitchListTile(
                        title: const Text("Alarm Modu"),
                        subtitle: Text(
                          isAlarmMode
                              ? "Sürekli çalar (Mor)"
                              : "Tek bildirim sesi (Mavi)",
                          style: const TextStyle(fontSize: 12),
                        ),
                        secondary: Icon(
                            isAlarmMode
                                ? Icons.access_alarm
                                : Icons.notifications_none,
                            color:
                                isAlarmMode ? Colors.deepPurple : Colors.blue),
                        value: isAlarmMode,
                        // ignore: deprecated_member_use
                        activeColor: Colors.deepPurple,
                        onChanged: (val) {
                          setStateDialog(() {
                            isAlarmMode = val;
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("İptal")),
                    ElevatedButton(
                        onPressed: () {
                          int? dk = int.tryParse(controller.text);
                          if (dk != null && dk >= 0) {
                            // isAlarmMode parametresini iletiyoruz
                            alarmDegistir(index, dk, isAlarm: isAlarmMode);
                            Navigator.pop(ctx);
                          }
                        },
                        child: const Text("Kaydet"))
                  ]);
            },
          );
        });
  }
}
