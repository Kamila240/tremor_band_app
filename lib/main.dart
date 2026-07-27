import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const TremorBandApp());

class TremorBandApp extends StatelessWidget {
  const TremorBandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tremor Band',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF325BFF),
          primary: const Color(0xFF325BFF),
          surface: const Color(0xFFF7F8FC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final controller = BandController();
  int index = 0;

  @override
  void initState() {
    super.initState();
    controller.startDemo();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      Dashboard(controller: controller),
      MonitorPage(controller: controller),
      ControlPage(controller: controller),
      DevicePage(controller: controller),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Мониторинг'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Управление'),
          NavigationDestination(icon: Icon(Icons.watch_outlined), label: 'Браслет'),
        ],
      ),
    );
  }
}

class BandController extends ChangeNotifier {
  static final serviceUuid = Guid('8f400001-91b5-4b6a-9f68-74f42a9db001');
  static final controlUuid = Guid('8f400002-91b5-4b6a-9f68-74f42a9db001');
  static final telemetryUuid = Guid('8f400003-91b5-4b6a-9f68-74f42a9db001');

  final samples = <TremorSample>[];
  final _random = Random();
  Timer? _demoTimer;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  StreamSubscription<List<int>>? _telemetrySub;
  bool demoMode = true;
  bool therapyOn = false;
  bool scanning = false;
  double intensity = 60;
  double strapDelay = 180;
  double tremorHz = 5.7;
  double amplitude = 1.25;
  int battery = 82;
  String pattern = 'Чередование';

  bool get connected => demoMode || _device?.isConnected == true;

  void startDemo() {
    demoMode = true;
    _demoTimer?.cancel();
    var t = 0.0;
    _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      t += 0.1;
      final damping = therapyOn ? 0.58 : 1.0;
      final value = (sin(t * tremorHz * pi * 2) * 1.2 + (_random.nextDouble() - .5) * .35) * damping;
      samples.add(TremorSample(DateTime.now(), value));
      if (samples.length > 120) samples.removeAt(0);
      amplitude = 1.25 * damping + (_random.nextDouble() - .5) * .08;
      tremorHz = 5.7 + (_random.nextDouble() - .5) * .12;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> scanAndConnect() async {
    scanning = true;
    notifyListeners();
    try {
      await FlutterBluePlus.startScan(withServices: [serviceUuid], timeout: const Duration(seconds: 8));
      final result = await FlutterBluePlus.scanResults.expand((items) => items).first;
      await FlutterBluePlus.stopScan();
      //await result.device.connect(timeout: const Duration(seconds: 12));
      await result.device.connect(
        timeout: const Duration(seconds: 12),
        license: License.free,
      );
      final services = await result.device.discoverServices();
      final service = services.firstWhere((item) => item.uuid == serviceUuid);
      _control = service.characteristics.firstWhere((item) => item.uuid == controlUuid);
      final telemetry = service.characteristics.firstWhere((item) => item.uuid == telemetryUuid);
      await telemetry.setNotifyValue(true);
      _telemetrySub = telemetry.onValueReceived.listen(_readTelemetry);
      _device = result.device;
      demoMode = false;
      _demoTimer?.cancel();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  void _readTelemetry(List<int> bytes) {
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      tremorHz = (data['tremor_hz'] as num?)?.toDouble() ?? tremorHz;
      amplitude = (data['amplitude'] as num?)?.toDouble() ?? amplitude;
      battery = (data['battery'] as num?)?.toInt() ?? battery;
      final gyro = (data['gyro'] as num?)?.toDouble() ?? amplitude;
      samples.add(TremorSample(DateTime.now(), gyro));
      if (samples.length > 120) samples.removeAt(0);
      notifyListeners();
    } catch (_) {
      // Ignore incomplete BLE packets; the next notification remains usable.
    }
  }

  Future<void> sendSettings() async {
    final command = jsonEncode({
      'cmd': therapyOn ? 'start' : 'stop',
      'pattern': patternCode(pattern),
      'intensity': intensity.round(),
      'delay_ms': strapDelay.round(),
    });
    await _control?.write(utf8.encode(command), withoutResponse: false);
    notifyListeners();
  }

  Future<void> setTherapy(bool value) async {
    therapyOn = value;
    await sendSettings();
  }

  int patternCode(String label) => switch (label) {
        'Одновременно' => 0,
        'Чередование' => 1,
        'Волна' => 2,
        'Импульсы' => 3,
        _ => 1,
      };

  @override
  void dispose() {
    _demoTimer?.cancel();
    _telemetrySub?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}

class TremorSample {
  const TremorSample(this.time, this.value);
  final DateTime time;
  final double value;
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.controller});
  final BandController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          const Text('Tremor Band', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Контроль и наблюдение в реальном времени', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          _DeviceCard(controller: controller),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _MetricCard(label: 'Тремор', value: controller.tremorHz.toStringAsFixed(1), unit: 'Hz', color: const Color(0xFF325BFF))),
            const SizedBox(width: 12),
            Expanded(child: _MetricCard(label: 'Амплитуда', value: controller.amplitude.toStringAsFixed(2), unit: '°/s', color: const Color(0xFF18A47B))),
          ]),
          const SizedBox(height: 16),
          _TherapyCard(controller: controller),
          const SizedBox(height: 16),
          _ChartCard(controller: controller, compact: true),
        ],
      ),
    );
  }
}

class MonitorPage extends StatelessWidget {
  const MonitorPage({super.key, required this.controller});
  final BandController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Мониторинг', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Поток MPU6500 · 10 выборок/сек в Demo', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            _ChartCard(controller: controller, compact: false),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Текущий анализ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  _DataRow('Доминирующая частота', '${controller.tremorHz.toStringAsFixed(1)} Hz'),
                  _DataRow('Угловая амплитуда', '${controller.amplitude.toStringAsFixed(2)} °/s'),
                  _DataRow('Воздействие', controller.therapyOn ? 'Включено' : 'Выключено'),
                  _DataRow('Источник', controller.demoMode ? 'Симуляция' : 'ESP32'),
                ]),
              ),
            ),
          ],
        ),
      );
}

class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.controller});
  final BandController controller;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Управление', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Паттерн', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: ['Одновременно', 'Чередование', 'Волна', 'Импульсы'].map((name) {
                  return ChoiceChip(
                    label: Text(name),
                    selected: c.pattern == name,
                    onSelected: (_) => setState(() => c.pattern = name),
                  );
                }).toList()),
                const SizedBox(height: 24),
                _SliderTitle(label: 'Интенсивность', value: '${c.intensity.round()}%'),
                Slider(value: c.intensity, min: 0, max: 100, divisions: 20, onChanged: (v) => setState(() => c.intensity = v)),
                const SizedBox(height: 8),
                _SliderTitle(label: 'Задержка между ремешками', value: '${c.strapDelay.round()} ms'),
                Slider(value: c.strapDelay, min: 0, max: 600, divisions: 24, onChanged: (v) => setState(() => c.strapDelay = v)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: c.sendSettings,
                    icon: const Icon(Icons.send),
                    label: const Padding(padding: EdgeInsets.symmetric(vertical: 13), child: Text('Отправить настройки')),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class DevicePage extends StatelessWidget {
  const DevicePage({super.key, required this.controller});
  final BandController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Браслет', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            _DeviceCard(controller: controller),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  _DataRow('Контроллер', 'ESP32'),
                  _DataRow('Датчик', 'MPU6500'),
                  _DataRow('Каналы моторов', '4'),
                  _DataRow('Соединение', controller.demoMode ? 'Demo mode' : 'Bluetooth LE'),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: controller.scanning ? null : controller.scanAndConnect,
              icon: controller.scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bluetooth_searching),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(controller.scanning ? 'Поиск…' : 'Найти ESP32-браслет'),
              ),
            ),
            TextButton(onPressed: controller.startDemo, child: const Text('Вернуться в Demo mode')),
          ],
        ),
      );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller});
  final BandController controller;

  @override
  Widget build(BuildContext context) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: const Color(0xFFE9EEFF), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.watch, color: Color(0xFF325BFF)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tremor Band 01', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(controller.connected ? 'Подключён${controller.demoMode ? ' · Demo' : ''}' : 'Не подключён', style: const TextStyle(color: Color(0xFF18A47B))),
            ])),
            const Icon(Icons.battery_5_bar, color: Color(0xFF18A47B)),
            Text('${controller.battery}%'),
          ]),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.unit, required this.color});
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            RichText(text: TextSpan(style: const TextStyle(color: Color(0xFF121629)), children: [
              TextSpan(text: value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
              TextSpan(text: ' $unit', style: const TextStyle(fontSize: 13)),
            ])),
          ]),
        ),
      );
}

class _TherapyCard extends StatelessWidget {
  const _TherapyCard({required this.controller});
  final BandController controller;

  @override
  Widget build(BuildContext context) => Card(
        color: controller.therapyOn ? const Color(0xFF152353) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Стабилизация', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: controller.therapyOn ? Colors.white : null)),
              const SizedBox(height: 5),
              Text(controller.therapyOn ? '${controller.pattern} · ${controller.intensity.round()}%' : 'Воздействие выключено', style: TextStyle(color: controller.therapyOn ? Colors.white70 : Colors.grey.shade600)),
            ])),
            Switch(value: controller.therapyOn, onChanged: controller.setTherapy),
          ]),
        ),
      );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.controller, required this.compact});
  final BandController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final spots = controller.samples.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(compact ? 'Сигнал сейчас' : 'График тремора', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFE9FBF5), borderRadius: BorderRadius.circular(12)),
              child: const Text('LIVE', style: TextStyle(color: Color(0xFF148361), fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: compact ? 130 : 280,
            child: LineChart(LineChartData(
              minY: -1.8,
              maxY: 1.8,
              gridData: FlGridData(show: !compact, drawVerticalLine: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(enabled: !compact),
              lineBarsData: [LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: .18,
                barWidth: 2.5,
                color: const Color(0xFF325BFF),
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: const Color(0xFF325BFF).withValues(alpha: .10)),
              )],
            )),
          ),
        ]),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _SliderTitle extends StatelessWidget {
  const _SliderTitle({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Text(value, style: const TextStyle(color: Color(0xFF325BFF), fontWeight: FontWeight.w700)),
      ]);
}
