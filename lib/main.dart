import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Analysis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LabelingPage(),
    );
  }
}

class LabelInterval {
  double start;
  double? end;
  String label;
  LabelInterval(this.start, this.label);
}

class LabelingPage extends StatefulWidget {
  const LabelingPage({super.key});

  @override
  State<LabelingPage> createState() => _LabelingPageState();
}

class _LabelingPageState extends State<LabelingPage> {
  final String _broker = '127.0.0.1';
  final int _port = 1883;
  final String _imuTopic = '/mobile/imu';
  final String _gpsTopic = '/mobile/gps';

  MqttServerClient? _client;
  bool _isConnected = false;
  bool _isRecording = false;
  bool _isLabeling = false;
  
  final TextEditingController _labelController = TextEditingController(text: 'Walking');
  DateTime? _labelStartTime;
  Duration _currentLabelDuration = Duration.zero;
  Timer? _labelTimer;

  final List<Map<String, dynamic>> _recordedData = [];
  
  // Spots
  final List<FlSpot> _axSpots = [];
  final List<FlSpot> _aySpots = [];
  final List<FlSpot> _azSpots = [];
  final List<FlSpot> _gxSpots = [];
  final List<FlSpot> _gySpots = [];
  final List<FlSpot> _gzSpots = [];
  final List<FlSpot> _latSpots = [];
  final List<FlSpot> _lonSpots = [];

  // GPS Map
  final List<LatLng> _gpsPath = [];
  final MapController _mapController = MapController();
  
  // Label Windows for visualization on chart
  final List<LabelInterval> _labelWindows = [];
  LabelInterval? _currentActiveWindow;

  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _setupMqtt();
  }

  Future<void> _setupMqtt() async {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) return;

    _client = MqttServerClient(_broker, 'flutter_client_${DateTime.now().millisecondsSinceEpoch}');
    _client!.port = _port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
    } catch (e) {
      debugPrint('MQTT Connect Exception: $e');
      _client!.disconnect();
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      _client!.subscribe(_imuTopic, MqttQos.atMostOnce);
      _client!.subscribe(_gpsTopic, MqttQos.atMostOnce);

      _subscription?.cancel();
      _subscription = _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        _handleMessage(c[0].topic, pt);
      });
    }
  }

  void _handleMessage(String topic, String payloadStr) {
    try {
      final payload = jsonDecode(payloadStr);
      final timestamp = payload['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
      final session = payload['session'] ?? 'default';
      final receivedAt = DateTime.now().toIso8601String();
      final double xVal = timestamp / 1000.0;

      if (topic == _imuTopic) {
        final ax = (payload['acc']?['x'] ?? 0.0).toDouble();
        final ay = (payload['acc']?['y'] ?? 0.0).toDouble();
        final az = (payload['acc']?['z'] ?? 0.0).toDouble();
        final gx = (payload['gyro']?['x'] ?? 0.0).toDouble();
        final gy = (payload['gyro']?['y'] ?? 0.0).toDouble();
        final gz = (payload['gyro']?['z'] ?? 0.0).toDouble();
        
        setState(() {
          _axSpots.add(FlSpot(xVal, ax));
          _aySpots.add(FlSpot(xVal, ay));
          _azSpots.add(FlSpot(xVal, az));
          _gxSpots.add(FlSpot(xVal, gx));
          _gySpots.add(FlSpot(xVal, gy));
          _gzSpots.add(FlSpot(xVal, gz));
          
          final double minX = xVal - 30.0;
          _axSpots.removeWhere((s) => s.x < minX);
          _aySpots.removeWhere((s) => s.x < minX);
          _azSpots.removeWhere((s) => s.x < minX);
          _gxSpots.removeWhere((s) => s.x < minX);
          _gySpots.removeWhere((s) => s.x < minX);
          _gzSpots.removeWhere((s) => s.x < minX);

          // Prune old label windows
          _labelWindows.removeWhere((w) => (w.end ?? xVal) < minX);
        });

        if (_isRecording) {
          _recordedData.add({
            'topic': topic, 'timestamp': timestamp, 'session': session,
            'received_at': receivedAt, 'label': _isLabeling ? _labelController.text : 'None',
            'ax': ax, 'ay': ay, 'az': az, 'gx': gx, 'gy': gy, 'gz': gz,
          });
        }
      } else if (topic == _gpsTopic) {
        final lat = (payload['gps']?['lat'] ?? 0.0).toDouble();
        final lon = (payload['gps']?['lon'] ?? 0.0).toDouble();

        setState(() {
          _latSpots.add(FlSpot(xVal, lat));
          _lonSpots.add(FlSpot(xVal, lon));
          final double minX = xVal - 30.0;
          _latSpots.removeWhere((s) => s.x < minX);
          _lonSpots.removeWhere((s) => s.x < minX);

          final latLng = LatLng(lat, lon);
          if (_isRecording) {
            _gpsPath.add(latLng);
          }
          // Center the map on the latest point
          _mapController.move(latLng, _mapController.camera.zoom);
        });

        if (_isRecording) {
          _recordedData.add({
            'topic': topic, 'timestamp': timestamp, 'session': session,
            'received_at': receivedAt, 'label': _isLabeling ? _labelController.text : 'None',
            'lat': lat, 'lon': lon,
          });
        }
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _onConnected() {
    setState(() => _isConnected = true);
    debugPrint('Connected to MQTT');
  }

  void _onDisconnected() {
    setState(() => _isConnected = false);
    debugPrint('Disconnected from MQTT');
  }

  Future<void> _saveData() async {
    if (_recordedData.isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final fileName = 'session_${DateTime.now().millisecondsSinceEpoch}.csv';
    final path = '${directory.path}/$fileName';
    final file = File(path);

    List<List<dynamic>> rows = [['topic', 'timestamp', 'session', 'received_at', 'label', 'ax', 'ay', 'az', 'gx', 'gy', 'gz', 'lat', 'lon']];
    for (var data in _recordedData) {
      rows.add([data['topic'], data['timestamp'], data['session'], data['received_at'], data['label'], data['ax'] ?? '', data['ay'] ?? '', data['az'] ?? '', data['gx'] ?? '', data['gy'] ?? '', data['gz'] ?? '', data['lat'] ?? '', data['lon'] ?? '']);
    }

    String csv = rows.map((row) => row.join(',')).join('\n');
    await file.writeAsString(csv);
    print('Saving to: ${directory.path}');
    _recordedData.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $fileName')));
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (!_isRecording) {
        if (_isLabeling) _stopLabeling();
        _saveData();
      } else {
        _gpsPath.clear();
      }
    });
  }

  void _startLabeling() {
    if (!_isRecording) return;
    
    // Create labeling window for visualization
    double currentX = 0;
    if (_axSpots.isNotEmpty) currentX = _axSpots.last.x;
    
    setState(() {
      _isLabeling = true;
      _labelStartTime = DateTime.now();
      _currentLabelDuration = Duration.zero;
      
      _currentActiveWindow = LabelInterval(currentX, _labelController.text);
      _labelWindows.add(_currentActiveWindow!);
    });

    _labelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_labelStartTime != null) {
        setState(() {
          _currentLabelDuration = DateTime.now().difference(_labelStartTime!);
        });
      }
    });
  }

  void _stopLabeling() {
    _labelTimer?.cancel();
    
    double currentX = 0;
    if (_axSpots.isNotEmpty) currentX = _axSpots.last.x;

    setState(() {
      _isLabeling = false;
      _currentLabelDuration = Duration.zero;
      _labelStartTime = null;
      
      if (_currentActiveWindow != null) {
        _currentActiveWindow!.end = currentX;
        _currentActiveWindow = null;
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _client?.disconnect();
    _labelController.dispose();
    _labelTimer?.cancel();
    super.dispose();
  }

  Widget _buildChart(String title, List<LineChartBarData> bars) {
    double lastX = bars.isNotEmpty && bars.first.spots.isNotEmpty ? bars.first.spots.last.x : 0;
    
    // Current active labeling window should be updated to current time
    for (var window in _labelWindows) {
      if (window == _currentActiveWindow) {
        window.end = lastX;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 2.5,
          child: Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: LineChart(
              LineChartData(
                minX: lastX - 30,
                maxX: lastX,
                lineBarsData: bars,
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: [
                    ..._labelWindows.map((w) => VerticalRangeAnnotation(
                      x1: w.start,
                      x2: w.end ?? lastX,
                      color: Colors.orange.withOpacity(0.3),
                    )),
                  ],
                ),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: true, drawVerticalLine: true),
                borderData: FlBorderData(show: true),
                lineTouchData: const LineTouchData(enabled: false),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Analysis'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off, color: _isConnected ? Colors.green : Colors.red),
            onPressed: _setupMqtt,
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildChart('Acceleration (m/s²)', [
                    LineChartBarData(spots: _axSpots, color: Colors.red, isCurved: true, dotData: const FlDotData(show: false)),
                    LineChartBarData(spots: _aySpots, color: Colors.green, isCurved: true, dotData: const FlDotData(show: false)),
                    LineChartBarData(spots: _azSpots, color: Colors.blue, isCurved: true, dotData: const FlDotData(show: false)),
                  ]),
                  _buildChart('Gyroscope (rad/s)', [
                    LineChartBarData(spots: _gxSpots, color: Colors.orange, isCurved: true, dotData: const FlDotData(show: false)),
                    LineChartBarData(spots: _gySpots, color: Colors.purple, isCurved: true, dotData: const FlDotData(show: false)),
                    LineChartBarData(spots: _gzSpots, color: Colors.cyan, isCurved: true, dotData: const FlDotData(show: false)),
                  ]),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Map View', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 400,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: const MapOptions(
                        initialCenter: LatLng(0, 0),
                        initialZoom: 15,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.mobile_analysis',
                        ),
                        if (_gpsPath.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: List.from(_gpsPath),
                                strokeWidth: 4,
                                color: Colors.blueAccent,
                              ),
                            ],
                          ),
                        MarkerLayer(
                          markers: [
                            if (_latSpots.isNotEmpty && _lonSpots.isNotEmpty)
                              Marker(
                                point: LatLng(_latSpots.last.y, _lonSpots.last.y),
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2))],
            ),
            child: Column(
              children: [
                if (!_isConnected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: _setupMqtt,
                      icon: const Icon(Icons.refresh),
                      label: const Text('RECONNECT TO BROKER'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    ),
                  ),
                TextField(
                  controller: _labelController,
                  decoration: const InputDecoration(labelText: 'Label Name', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isConnected ? _toggleRecording : null,
                        icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
                        label: Text(_isRecording ? 'STOP' : 'RECORD'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRecording ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => _startLabeling(),
                        onPointerUp: (_) => _stopLabeling(),
                        onPointerCancel: (_) => _stopLabeling(),
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.tag),
                          label: Text(_isLabeling ? 'LABELING...' : 'HOLD TO LABEL'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecording ? (_isLabeling ? Colors.orange : Colors.indigo) : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isLabeling)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Window: ${(_currentLabelDuration.inMilliseconds / 1000.0).toStringAsFixed(1)}s',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
