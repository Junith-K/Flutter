import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  runApp(DualStageAlarmApp(flutterLocalNotificationsPlugin));
}

class DualStageAlarmApp extends StatelessWidget {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  DualStageAlarmApp(this.flutterLocalNotificationsPlugin);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(flutterLocalNotificationsPlugin),
    );
  }
}

class Alarm {
  TimeOfDay time;
  String sound;
  bool vibration;
  bool enabled;

  Alarm({
    required this.time,
    required this.sound,
    required this.vibration,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'time': {'hour': time.hour, 'minute': time.minute},
        'sound': sound,
        'vibration': vibration,
        'enabled': enabled,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      time: TimeOfDay(hour: json['time']['hour'], minute: json['time']['minute']),
      sound: json['sound'],
      vibration: json['vibration'],
      enabled: json['enabled'],
    );
  }
}

class AlarmStorage {
  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/alarms.json');
  }

  static Future<List<Alarm>> loadAlarms() async {
    try {
      final file = await _localFile;
      String contents = await file.readAsString();
      List<dynamic> jsonData = json.decode(contents);
      return jsonData.map((json) => Alarm.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveAlarms(List<Alarm> alarms) async {
    final file = await _localFile;
    List<Map<String, dynamic>> jsonData = alarms.map((alarm) => alarm.toJson()).toList();
    await file.writeAsString(json.encode(jsonData));
  }
}

class HomeScreen extends StatefulWidget {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  HomeScreen(this.flutterLocalNotificationsPlugin);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Alarm> alarms = [];
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _loadAlarms();
    _initializeNotifications();
  }

  void _loadAlarms() async {
    alarms = await AlarmStorage.loadAlarms();
    setState(() {});
    _scheduleNotifications();
  }

  void _saveAlarms() {
    AlarmStorage.saveAlarms(alarms);
    _scheduleNotifications();
  }

  void _deleteAlarm(int index) {
    setState(() {
      alarms.removeAt(index);
    });
    _saveAlarms();
  }

  void _navigateToAddEditAlarm([Alarm? alarm, int? index]) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddEditAlarmScreen(alarm: alarm)),
    );
    if (result != null) {
      if (index != null) {
        setState(() {
          alarms[index] = result;
        });
      } else {
        setState(() {
          alarms.add(result);
        });
      }
      _saveAlarms();
    }
  }

  void _initializeNotifications() {
    var initializationSettingsAndroid = AndroidInitializationSettings('app_icon');
    var initializationSettingsIOS = IOSInitializationSettings();
    var initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _scheduleNotifications() {
    flutterLocalNotificationsPlugin.cancelAll();
    alarms.forEach((alarm) {
      if (alarm.enabled) {
        var time = Time(alarm.time.hour, alarm.time.minute, 0);
        var androidPlatformChannelSpecifics = AndroidNotificationDetails(
          'alarm_channel',
          'Alarms',
          channelDescription: 'Channel for alarms',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound('alarm_sound'),
        );
        var iOSPlatformChannelSpecifics = IOSNotificationDetails();
        var platformChannelSpecifics = NotificationDetails(
            android: androidPlatformChannelSpecifics,
            iOS: iOSPlatformChannelSpecifics);
        flutterLocalNotificationsPlugin.showDailyAtTime(
          alarm.hashCode,
          'Alarm',
          'Time to wake up!',
          time,
          platformChannelSpecifics,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dual-Stage Alarm')),
      body: ListView.builder(
        itemCount: alarms.length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(alarms[index].time.format(context)),
            subtitle: Text(alarms[index].sound),
            trailing: Switch(
              value: alarms[index].enabled,
              onChanged: (bool value) {
                setState(() {
                  alarms[index].enabled = value;
                });
                _saveAlarms();
              },
            ),
            onTap: () {
              _navigateToAddEditAlarm(alarms[index], index);
            },
            onLongPress: () {
              _deleteAlarm(index);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _navigateToAddEditAlarm();
        },
        child: Icon(Icons.add),
      ),
    );
  }
}

class AddEditAlarmScreen extends StatefulWidget {
  final Alarm? alarm;

  AddEditAlarmScreen({this.alarm});

  @override
  _AddEditAlarmScreenState createState() => _AddEditAlarmScreenState();
}

class _AddEditAlarmScreenState extends State<AddEditAlarmScreen> {
  late TimeOfDay _time;
  late String _sound;
  bool _vibration = false;
  final List<String> _sounds = [
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
  ];
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlaying;

  @override
  void initState() {
    super.initState();
    _time = widget.alarm?.time ?? TimeOfDay.now();
    _sound = widget.alarm?.sound ?? _sounds[0];
    _vibration = widget.alarm?.vibration ?? false;
  }

  void _selectSound() async {
    String? selectedSound = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SimpleDialog(
              title: const Text('Select Sound'),
              children: _sounds.map((String sound) {
                bool isPlaying = _currentlyPlaying == sound;
                return SimpleDialogOption(
                  onPressed: () {
                    setState(() {
                      _sound = sound;
                    });
                    Navigator.pop(context, sound);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sound.split('/').last),
                      IconButton(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        onPressed: () async {
                          if (isPlaying) {
                            await _audioPlayer.stop();
                            setState(() {
                              _currentlyPlaying = null;
                            });
                          } else {
                            await _audioPlayer.setUrl(sound);
                            await _audioPlayer.play(sound);
                            setState(() {
                              _currentlyPlaying = sound;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
    if (selectedSound != null) {
      setState(() {
        _sound = selectedSound;
      });
    }
    await _audioPlayer.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.alarm == null ? 'Add Alarm' : 'Edit Alarm'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              title: Text('Time'),
              trailing: Text(_time.format(context)),
              onTap: () async {
                TimeOfDay? newTime = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (newTime != null) {
                  setState(() {
                    _time = newTime;
                  });
                }
              },
            ),
            ListTile(
              title: Text('Sound'),
              trailing: Text(_sound.split('/').last),
              onTap: _selectSound,
            ),
            SwitchListTile(
              title: Text('Vibration'),
              value: _vibration,
              onChanged: (bool value) {
                setState(() {
                  _vibration = value;
                });
              },
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  Alarm(time: _time, sound: _sound, vibration: _vibration),
                );
              },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class AlarmRingingScreen extends StatelessWidget {
  final Alarm alarm;
  final AudioPlayer _player = AudioPlayer();

  AlarmRingingScreen({required this.alarm});

  void _stopSound() async {
    await _player.stop();
  }

  void _startVibration() {
    if (alarm.vibration) {
      Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 0);
    }
  }

  void _playSound() async {
    await _player.setUrl(alarm.sound);
    await _player.play(alarm.sound, isLocal: false);
  }

  @override
  Widget build(BuildContext context) {
    _startVibration();
    _playSound();
    return Scaffold(
      appBar: AppBar(title: Text('Alarm Ringing')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            _stopSound();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => VibrationModeScreen(alarm: alarm)),
            );
          },
          child: Text('Stop Sound'),
        ),
      ),
    );
  }
}

class VibrationModeScreen extends StatefulWidget {
  final Alarm alarm;

  VibrationModeScreen({required this.alarm});

  @override
  _VibrationModeScreenState createState() => _VibrationModeScreenState();
}

class _VibrationModeScreenState extends State<VibrationModeScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void _stopVibration() {
    Vibration.cancel();
  }

  void _onQRViewCreated(QRViewController controller) {
    this.controller = controller;
    controller.scannedDataStream.listen((scanData) {
      _stopVibration();
      controller.dispose();
      Navigator.popUntil(context, (route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Stop Vibration')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Scan QR code to stop vibration'),
            SizedBox(
              width: 300,
              height: 300,
              child: QRView(
                key: qrKey,
                onQRViewCreated: _onQRViewCreated,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
