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

// 卫星系统分类
enum GnssType { GPS, GLONASS, Galileo, BeiDou, SBAS, Other }

class SatelliteInfo {
  final int prn;
  final double snr;
  final double elevation;
  final double azimuth;
  final bool used;
  final GnssType type;
  final String name;

  SatelliteInfo({
    required this.prn,
    required this.snr,
    required this.elevation,
    required this.azimuth,
    required this.used,
    required this.type,
    required this.name,
  });
}

GnssType getGnssType(int prn) {
  if (prn >= 1 && prn <= 32) return GnssType.GPS;
  if (prn >= 65 && prn <= 96) return GnssType.GLONASS;
  if (prn >= 1 && prn <= 36) return GnssType.Galileo; // 需要根据实际实现区分
  if (prn >= 1 && prn <= 37) return GnssType.BeiDou;
  if (prn >= 33 && prn <= 64) return GnssType.SBAS;
  return GnssType.Other;
}

String getGnssName(int prn, GnssType type) {
  switch (type) {
    case GnssType.GPS:
      return 'GPS';
    case GnssType.GLONASS:
      return 'GLONASS';
    case GnssType.Galileo:
      return 'Galileo';
    case GnssType.BeiDou:
      return 'BeiDou';
    case GnssType.SBAS:
      return 'SBAS';
    case GnssType.Other:
      return '其他';
  }
}

class _GpsDiagnosticPageState extends State<GpsDiagnosticPage> {
  static const platform = MethodChannel('com.gpsdiag/gps_status');

  bool _isGpsEnabled = false;
  bool _hasPermission = false;
  Map<String, dynamic>? _locationData;
  List<SatelliteInfo> _satellites = [];
  Timer? _refreshTimer;
  String _statusMessage = "正在检查...";

  // 统计各系统卫星数量
  int _gpsCount = 0;
  int _glonassCount = 0;
  int _galileoCount = 0;
  int _beidouCount = 0;
  int _otherCount = 0;
  int _usedCount = 0;

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
    try {
      await platform.invokeMethod('requestLocationUpdate');
    } catch (e) {
      debugPrint('请求位置更新失败: $e');
    }
    
    await _refreshGpsData();
    
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshGpsData();
    });
  }

  Future<void> _refreshGpsData() async {
    try {
      final bool isEnabled = await platform.invokeMethod('isGpsEnabled');
      final gpsData = await platform.invokeMethod('getGpsStatus');
      
      if (!mounted) return;

      setState(() {
        _isGpsEnabled = isEnabled;
        
        if (gpsData != null) {
          final location = gpsData['location'] as Map<dynamic, dynamic>?;
          if (location != null && location.isNotEmpty) {
            _locationData = Map<String, dynamic>.from(location);
          }
          
          final satellites = gpsData['satellites'] as List<dynamic>?;
          if (satellites != null && satellites.isNotEmpty) {
            _satellites = satellites.map((s) {
              final prn = s['prn'] as int;
              final type = getGnssType(prn);
              return SatelliteInfo(
                prn: prn,
                snr: (s['snr'] ?? 0).toDouble(),
                elevation: (s['elevation'] ?? 0).toDouble(),
                azimuth: (s['azimuth'] ?? 0).toDouble(),
                used: s['used'] ?? false,
                type: type,
                name: getGnssName(prn, type),
              );
            }).toList();
            
            // 统计
            _gpsCount = _satellites.where((s) => s.type == GnssType.GPS).length;
            _glonassCount = _satellites.where((s) => s.type == GnssType.GLONASS).length;
            _galileoCount = _satellites.where((s) => s.type == GnssType.Galileo).length;
            _beidouCount = _satellites.where((s) => s.type == GnssType.BeiDou).length;
            _otherCount = _satellites.where((s) => 
              s.type == GnssType.SBAS || s.type == GnssType.Other).length;
            _usedCount = _satellites.where((s) => s.used).length;
          } else {
            _satellites = [];
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

  Color _getGnssColor(GnssType type) {
    switch (type) {
      case GnssType.GPS: return Colors.blue;
      case GnssType.GLONASS: return Colors.red;
      case GnssType.Galileo: return Colors.purple;
      case GnssType.BeiDou: return Colors.orange;
      case GnssType.SBAS: return Colors.teal;
      case GnssType.Other: return Colors.grey;
    }
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
                  _buildGnssStatsCard(),
                  const SizedBox(height: 16),
                  _buildTotalStatsCard(),
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

  Widget _buildGnssStatsCard() {
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
                  '卫星系统统计',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildGnssChip('GPS', _gpsCount, Colors.blue),
                _buildGnssChip('GLONASS', _glonassCount, Colors.red),
                _buildGnssChip('BeiDou', _beidouCount, Colors.orange),
                _buildGnssChip('Galileo', _galileoCount, Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGnssChip(String name, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalStatsCard() {
    return Card(
      color: Colors.blue.shade900,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('卫星总数', _satellites.length.toString(), Icons.satellite_alt),
            _buildStatItem('已定位', _usedCount.toString(), Icons.check_circle),
            _buildStatItem('未定位', (_satellites.length - _usedCount).toString(), Icons.cancel),
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
    final sortedSatellites = List<SatelliteInfo>.from(_satellites)
      ..sort((a, b) => b.snr.compareTo(a.snr));

    // 按系统分组
    final grouped = <GnssType, List<SatelliteInfo>>{};
    for (final sat in sortedSatellites) {
      grouped.putIfAbsent(sat.type, () => []).add(sat);
    }

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
            ...grouped.entries.map((entry) => _buildGnssSection(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildGnssSection(GnssType type, List<SatelliteInfo> satellites) {
    final color = _getGnssColor(type);
    final name = getGnssName(satellites.first.prn, type);
    final usedInFix = satellites.where((s) => s.used).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                name,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '($usedInFix/${satellites.length})',
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 12),
              ),
            ],
          ),
        ),
        ...satellites.map((sat) => _buildSatelliteItem(sat, color)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSatelliteItem(SatelliteInfo sat, Color gnssColor) {
    final used = sat.used;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: used 
            ? gnssColor.withOpacity(0.1) 
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: used 
              ? gnssColor.withOpacity(0.3) 
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          // PRN编号
          Container(
            width: 45,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: gnssColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${sat.prn}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14, 
                fontWeight: FontWeight.bold,
                color: gnssColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 信号强度
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${sat.snr.toStringAsFixed(1)} dBHz',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getSignalColor(sat.snr),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '方位 ${sat.azimuth.toStringAsFixed(0)}°',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '仰角 ${sat.elevation.toStringAsFixed(0)}°',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            used ? Icons.check_circle : Icons.circle_outlined,
            color: used ? Colors.green : Colors.grey,
            size: 18,
          ),
        ],
      ),
    );
  }
}
