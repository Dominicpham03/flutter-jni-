import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'iperf3_service.dart';

void main() {
  runApp(const Iperf3App());
}

class Iperf3App extends StatelessWidget {
  const Iperf3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iperf3 Tester',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const Iperf3TestPage(),
    );
  }
}

class Iperf3TestPage extends StatefulWidget {
  const Iperf3TestPage({super.key});

  @override
  State<Iperf3TestPage> createState() => _Iperf3TestPageState();
}

class _Iperf3TestPageState extends State<Iperf3TestPage> {
  final _formKey = GlobalKey<FormState>();
  final _iperf3Service = Iperf3Service();

  // Form controllers
  final _serverHostController = TextEditingController(text: 'iperf.he.net');
  final _portController = TextEditingController(text: '5201');
  final _durationController = TextEditingController(text: '10');
  final _streamsController = TextEditingController(text: '1');
  final _bandwidthController = TextEditingController(text: '10');

  // Test configuration
  bool _useUdp = false;
  bool _reverse = false;
  bool _isRunning = false;
  bool _canCancel = false;

  // Results
  Map<String, dynamic>? _testResults;
  String? _errorMessage;
  Map<String, dynamic>? _currentProgress; // Single live update (replaces previous)
  bool _hostFieldEdited = false;
  bool _settingHostProgrammatically = false;

  @override
  void initState() {
    super.initState();
    _serverHostController.addListener(() {
      if (!_settingHostProgrammatically) {
        _hostFieldEdited = true;
      }
    });
    _listenToProgress();
    _initializeDefaultGateway();
  }

  void _listenToProgress() {
    _iperf3Service.getProgressStream().listen((progress) {
      if (!mounted) return;
      setState(() {
        final status = progress['status'];
        if (status is String) {
          final details = progress['details'];
          switch (status) {
            case 'starting':
              _currentProgress = null;
              _canCancel = false;
              break;
            case 'running':
              _errorMessage = null;
              break;
            case 'completed':
              _canCancel = false;
              break;
            case 'cancelled':
              _canCancel = false;
              _errorMessage = 'Test cancelled by user.';
              _testResults = null;
              break;
            case 'error':
              final message = (details is Map && details['message'] != null)
                  ? details['message'].toString()
                  : 'iperf3 test failed';
              final code = (details is Map && details['code'] != null)
                  ? ' (code ${details['code']})'
                  : '';
              _errorMessage = '$message$code';
              _testResults = null;
              _canCancel = false;
              break;
            case 'idle':
              _canCancel = false;
              break;
          }
        } else {
          _currentProgress = progress; // Replace previous with latest
          if (_isRunning && !_canCancel) {
            _canCancel = true;
          }
        }
      });
    });
  }

  Future<void> _initializeDefaultGateway() async {
    try {
      final gateway = await _iperf3Service.getDefaultGateway();
      if (!mounted) return;
      if (gateway != null && !_hostFieldEdited && _serverHostController.text.isEmpty) {
        _settingHostProgrammatically = true;
        _serverHostController.text = gateway;
        _settingHostProgrammatically = false;
      }
    } catch (e) {
      // Non-fatal: just leave the field empty.
      debugPrint('Failed to fetch default gateway: $e');
    }
  }

  Future<void> _runTest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isRunning = true;
      _testResults = null;
      _errorMessage = null;
      _currentProgress = null; // Clear previous progress
      _canCancel = false;
    });

    try {
      final result = await _iperf3Service.runClient(
        serverHost: _serverHostController.text,
        port: int.parse(_portController.text),
        durationSeconds: int.parse(_durationController.text),
        parallelStreams: int.parse(_streamsController.text),
        reverse: _reverse,
        useUdp: _useUdp,
        bandwidthMbps: _useUdp ? int.tryParse(_bandwidthController.text) : null,
      );

      setState(() {
        final success = result['success'] == true;
        if (success) {
          _testResults = result;
          _errorMessage = null;
        } else {
          _testResults = null;
          final code = result['errorCode'];
          final error = result['error']?.toString() ?? 'iperf3 test failed';
          _errorMessage = code != null ? '$error (code $code)' : error;
        }
        _isRunning = false;
        _canCancel = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e is PlatformException && e.code == 'IPERF3_CANCELLED'
            ? 'Test cancelled by user.'
            : e.toString();
        _isRunning = false;
        _canCancel = false;
      });
    }
  }

  Future<void> _cancelTest() async {
    try {
      final bool wasRunning = await _iperf3Service.cancelClient();
      if (wasRunning) {
        setState(() {
          _isRunning = false;
          _errorMessage = 'Test cancelled by user.';
          _testResults = null;
          _currentProgress = null;
          _canCancel = false;
        });
      } else {
        setState(() {
          _isRunning = false;
          _errorMessage = 'No active test to cancel.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to cancel test: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iperf3 Network Tester'),
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Server Configuration Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server Configuration',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _serverHostController,
                        decoration: const InputDecoration(
                          labelText: 'Server Host',
                          hintText: '192.168.1.100',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.dns),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter server host';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '5201',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.settings_ethernet),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter port';
                          }
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) {
                            return 'Port must be between 1 and 65535';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Test Parameters Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Parameters',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _durationController,
                              decoration: const InputDecoration(
                                labelText: 'Duration (seconds)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.timer),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final duration = int.tryParse(value);
                                if (duration == null || duration < 1) {
                                  return 'Must be >= 1';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _streamsController,
                              decoration: const InputDecoration(
                                labelText: 'Parallel Streams',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.stream),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final streams = int.tryParse(value);
                                if (streams == null || streams < 1) {
                                  return 'Must be >= 1';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Protocol Selection Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Protocol',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('TCP'),
                              subtitle: const Text('Measures RTT'),
                              value: false,
                              groupValue: _useUdp,
                              onChanged: (value) {
                                setState(() {
                                  _useUdp = value!;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text('UDP'),
                              subtitle: const Text('Measures Jitter'),
                              value: true,
                              groupValue: _useUdp,
                              onChanged: (value) {
                                setState(() {
                                  _useUdp = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      // Show bandwidth option only for UDP
                      if (_useUdp) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _bandwidthController,
                          decoration: const InputDecoration(
                            labelText: 'Bandwidth (Mbits/sec)',
                            hintText: 'Leave empty for default (1 Mbit/sec)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.speed),
                            helperText: 'Optional: Target bandwidth (default: 1 Mbit/sec)',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            // Allow empty for default behavior
                            if (value == null || value.isEmpty) {
                              return null; // Valid - will use iperf3 default
                            }
                            final bandwidth = int.tryParse(value);
                            if (bandwidth == null || bandwidth < 1) {
                              return 'Bandwidth must be >= 1 Mbits/sec';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 8),
                      SwitchListTile(
                        title: const Text('Reverse Mode'),
                        subtitle: const Text('Server sends, client receives'),
                        value: _reverse,
                        onChanged: (value) {
                          setState(() {
                            _reverse = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Run Test Button
              ElevatedButton.icon(
                onPressed: _isRunning ? null : _runTest,
                icon: _isRunning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _isRunning ? 'Running Test...' : 'Run Test',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
              if (_isRunning) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _canCancel ? _cancelTest : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text(
                    'Cancel Test',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Live Progress Update (single, updating display)
              if (_currentProgress != null) ...[
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.trending_up, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              'Live Test Progress',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Interval number
                        Row(
                          children: [
                            Text(
                              'Interval:',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(width: 8),
                            CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Text(
                                '${_currentProgress!['interval']}',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Speed
                        Text(
                          '${_currentProgress!['mbps']?.toStringAsFixed(2)} Mbits/sec',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        // Protocol-specific metrics
                        if (_currentProgress!.containsKey('rtt') && _currentProgress!['rtt'] > 0)
                          Text(
                            'RTT: ${_currentProgress!['rtt']?.toStringAsFixed(2)} ms',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        if (_currentProgress!.containsKey('jitter'))
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jitter: ${_currentProgress!['jitter']?.toStringAsFixed(2)} ms',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (_currentProgress!.containsKey('lostPackets'))
                                Text(
                                  'Lost Packets: ${_currentProgress!['lostPackets']}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        if (_currentProgress!.containsKey('bytesTransferred'))
                          Text(
                            'Bytes: ${(_currentProgress!['bytesTransferred'] / 1024 / 1024).toStringAsFixed(2)} MB',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Error Display
              if (_errorMessage != null) ...[
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Error',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.red.shade700,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(_errorMessage!),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Results Display
              if (_testResults != null) ...[
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Test Results',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.green.shade700,
                                  ),
                            ),
                          ],
                        ),
                        const Divider(),
                        _buildResultRow('Send Speed', '${_testResults!['sendMbps']?.toStringAsFixed(2)} Mbits/sec'),
                        _buildResultRow('Receive Speed', '${_testResults!['receiveMbps']?.toStringAsFixed(2)} Mbits/sec'),
                        if (_testResults!.containsKey('rtt'))
                          _buildResultRow('RTT (Latency)', '${_testResults!['rtt']?.toStringAsFixed(2)} ms'),
                        if (_testResults!.containsKey('jitter'))
                          _buildResultRow('Jitter', '${_testResults!['jitter']?.toStringAsFixed(2)} ms'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverHostController.dispose();
    _portController.dispose();
    _durationController.dispose();
    _streamsController.dispose();
    _bandwidthController.dispose();
    super.dispose();
  }
}
