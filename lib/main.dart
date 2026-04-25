import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

void main() {
  runApp(const GpsDiagApp());
}

class GpsDiagApp extends StatelessWidget {
  const GpsDiagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPS卫星诊断',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const GpsDiagnosticPage(),
    );
  }
}

class GpsDiagnosticPage extends StatefulWidget {
  const GpsDiagnosticPage({super.key});

  @override
  State<GpsDiagnosticPage> createState() => _GpsDiagnosticPageState();
}

class _GpsDiagnosticPageState extends State<GpsDiagnosticPage> {
  static const platform = MethodChannel('com.gpsdiag/gps_status');

  bool _isGpsEnabled = false;
  bool _hasPermission = false;
  Map<String, dynamic>? _locationData;
  List<Map<String, dynamic>> _satellites = [];
  int _usedSatellites = 0;
  Timer? _refreshTimer;
  String _statusMessage = "正在检查...";

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    setState(() => _statusMessage = "正在请求权限...");

    final status = await Permission.location.request();
    
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _statusMessage = "权限已获取";
      });
      _startMonitoring();
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _hasPermission = false;
        _statusMessage = "权限被拒绝，请在设置中开启";
      });
    } else {
      setState(() {
        _hasPermission = false;
        _statusMessage = "需要定位权限";
      });
    }
  }

  Future<void> _startMonitoring() async {
    // 请求位置更新
    try {
      await platform.invokeMethod('requestLocationUpdate');
    } catch (e) {
      debugPrint('请求位置更新失败: $e');
    }
    
    await _refreshGpsData();
    
    // 每秒刷新一次
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshGpsData();
    });
  }

  Future<void> _refreshGpsData() async {
    try {
      // 直接检查GPS是否启用
      final bool isEnabled = await platform.invokeMethod('isGpsEnabled');
      
      // 获取GPS数据
      final gpsData = await platform.invokeMethod('getGpsStatus');
      
      if (!mounted) return;

      setState(() {
        _isGpsEnabled = isEnabled;
        
        if (gpsData != null) {
          // 获取位置信息
          final location = gpsData['location'] as Map<dynamic, dynamic>?;
          if (location != null && location.isNotEmpty) {
            _locationData = Map<String, dynamic>.from(location);
          }
          
          // 获取卫星列表
          final satellites = gpsData['satellites'] as List<dynamic>?;
          if (satellites != null) {
            _satellites = satellites.map((s) => Map<String, dynamic>.from(s as Map)).toList();
            _usedSatellites = _satellites.where((s) => s['used'] == true).length;
          }
        }
      });
    } on PlatformException catch (e) {
      debugPrint('获取GPS数据失败: ${e.message}');
    }
  }

  Color _getSignalColor(double snr) {
    if (snr >= 40) return Colors.green;
    if (snr >= 25) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📡 GPS卫星诊断'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _hasPermission ? _refreshGpsData : null,
          ),
        ],
      ),
      body: !_hasPermission
          ? _buildPermissionRequest()
          : RefreshIndicator(
              onRefresh: _refreshGpsData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildLocationCard(),
                  const SizedBox(height: 16),
                  _buildSatelliteStatsCard(),
                  const SizedBox(height: 16),
                  _buildSatelliteList(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 80, color: Colors.orange),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              '此应用需要定位权限来获取GPS卫星信息',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _checkPermissions,
              icon: const Icon(Icons.check),
              label: const Text('授予权限'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isGpsEnabled ? Icons.gps_fixed : Icons.gps_off,
                  color: _isGpsEnabled ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'GPS状态: ${_isGpsEnabled ? "已开启 ✓" : "已关闭 ✗"}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _isGpsEnabled ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            if (!_isGpsEnabled) ...[
              const SizedBox(height: 16),
              const Text(
                '⚠️ 请在设置中开启GPS定位服务',
                style: TextStyle(color: Colors.orange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    if (_locationData == null || _locationData!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.location_searching, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text(
                _isGpsEnabled ? "正在获取位置..." : "GPS未开启",
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '位置信息',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow('纬度', '${_locationData!['latitude']?.toStringAsFixed(6) ?? "N/A"}°'),
            _buildInfoRow('经度', '${_locationData!['longitude']?.toStringAsFixed(6) ?? "N/A"}°'),
            _buildInfoRow('海拔', '${_locationData!['altitude']?.toStringAsFixed(1) ?? "N/A"} m'),
            _buildInfoRow('精度', '${_locationData!['accuracy']?.toStringAsFixed(1) ?? "N/A"} m'),
            _buildInfoRow('速度', '${((_locationData!['speed'] ?? 0) * 3.6).toStringAsFixed(1)} km/h'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSatelliteStatsCard() {
    return Card(
      color: Colors.blue.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('卫星总数', _satellites.length.toString(), Icons.satellite_alt),
            _buildStatItem('已定位', _usedSatellites.toString(), Icons.check_circle),
            _buildStatItem('未定位', (_satellites.length - _usedSatellites).toString(), Icons.cancel),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.white70),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildSatelliteList() {
    if (_satellites.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.satellite,
                size: 48,
                color: _isGpsEnabled ? Colors.cyan : Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _isGpsEnabled ? "正在搜索卫星..." : "请开启GPS",
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // 按信噪比排序
    final sortedSatellites = List<Map<String, dynamic>>.from(_satellites)
      ..sort((a, b) => ((b['snr'] ?? 0) as num).compareTo((a['snr'] ?? 0) as num));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.satellite_alt, color: Colors.cyan),
                const SizedBox(width: 8),
                Text(
                  '卫星列表 (${_satellites.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            ...sortedSatellites.map((sat) => _buildSatelliteItem(sat)),
          ],
        ),
      ),
    );
  }

  Widget _buildSatelliteItem(Map<String, dynamic> sat) {
    final snr = (sat['snr'] ?? 0).toDouble();
    final used = sat['used'] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: used 
            ? Colors.green.withOpacity(0.1) 
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: used 
              ? Colors.green.withOpacity(0.5) 
              : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // PRN编号
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'PRN\n${sat['prn']}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          // 信号强度
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('信噪比: ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '${snr.toStringAsFixed(1)} dBHz',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getSignalColor(snr),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (snr / 55).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation(_getSignalColor(snr)),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 方位角和仰角
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '方位 ${(sat['azimuth'] ?? 0).toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                '仰角 ${(sat['elevation'] ?? 0).toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Icon(
            used ? Icons.check_circle : Icons.circle_outlined,
            color: used ? Colors.green : Colors.grey,
          ),
        ],
      ),
    );
  }
}
