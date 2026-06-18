import 'package:flutter/material.dart';
import '../../models/student.dart';
import '../../models/transport_route.dart';
import '../../services/student_service.dart';
import '../../services/transport_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/utils/app_transitions.dart';

class TransportDriverScreen extends StatefulWidget {
  const TransportDriverScreen({super.key});

  @override
  State<TransportDriverScreen> createState() => _TransportDriverScreenState();
}

class _TransportDriverScreenState extends State<TransportDriverScreen>
    with SingleTickerProviderStateMixin {
  final TransportService _transportService = TransportService.instance;
  final StudentService _studentService = StudentService.instance;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateMockRoutes() async {
    try {
      final route1 = TransportRoute(
        id: '',
        schoolId: '',
        name: 'Route 101 - Dwarka Express',
        driverName: 'Satish Yadav',
        driverPhone: '+91 98765 12345',
        isActive: false,
        currentStopIndex: -1,
        lastUpdated: DateTime.now(),
        stops: const [
          TransportStop(name: 'Dwarka Sector 10 Metro', expectedTime: '07:15 AM', sequence: 1),
          TransportStop(name: 'Dwarka Sector 6 Chowk', expectedTime: '07:30 AM', sequence: 2),
          TransportStop(name: 'Palam Flyover Junction', expectedTime: '07:45 AM', sequence: 3),
          TransportStop(name: 'Delhi Cantonment Gate', expectedTime: '08:00 AM', sequence: 4),
          TransportStop(name: 'School Campus', expectedTime: '08:20 AM', sequence: 5),
        ],
      );

      final route2 = TransportRoute(
        id: '',
        schoolId: '',
        name: 'Route 202 - Noida Links',
        driverName: 'Maninder Singh',
        driverPhone: '+91 99991 88882',
        isActive: false,
        currentStopIndex: -1,
        lastUpdated: DateTime.now(),
        stops: const [
          TransportStop(name: 'Noida City Center', expectedTime: '07:00 AM', sequence: 1),
          TransportStop(name: 'Noida Sector 62 HDFC', expectedTime: '07:20 AM', sequence: 2),
          TransportStop(name: 'Akshardham Flyway', expectedTime: '07:45 AM', sequence: 3),
          TransportStop(name: 'Mayur Vihar Ext.', expectedTime: '08:00 AM', sequence: 4),
          TransportStop(name: 'School Campus', expectedTime: '08:25 AM', sequence: 5),
        ],
      );

      await _transportService.addRoute(route1);
      await _transportService.addRoute(route2);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mock routes created successfully!')),
        );
      }
    } catch (e, st) {
      AppLogger.e('TransportDriver', 'Failed to generate mock routes', e, st);
    }
  }

  void _showAddRouteDialog() {
    final nameCtrl = TextEditingController();
    final driverCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final stopsTextCtrl = TextEditingController(
      text: 'Stop A (07:30 AM), Stop B (07:50 AM), School Campus (08:15 AM)',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Transport Route', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Route Name (e.g. Bus 42 - South Delhi)'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter route name' : null,
                ),
                TextFormField(
                  controller: driverCtrl,
                  decoration: const InputDecoration(labelText: 'Driver/Conductor Name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter driver name' : null,
                ),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Driver Phone Contact'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter phone number' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: stopsTextCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Stops & Timings (Format: Name (Time), ...)',
                    hintText: 'e.g. Stop 1 (07:00 AM), Stop 2 (07:30 AM)',
                  ),
                  maxLines: 3,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter at least one stop';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter stops sequentially separated by commas. Make sure to specify the time in brackets.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              // Parse stops
              final stopsStr = stopsTextCtrl.text.split(',');
              final List<TransportStop> parsedStops = [];
              int seq = 1;
              for (var s in stopsStr) {
                s = s.trim();
                if (s.isEmpty) continue;
                String name = s;
                String time = '';
                if (s.contains('(') && s.contains(')')) {
                  final start = s.indexOf('(');
                  final end = s.indexOf(')');
                  name = s.substring(0, start).trim();
                  time = s.substring(start + 1, end).trim();
                }
                parsedStops.add(TransportStop(name: name, expectedTime: time, sequence: seq++));
              }

              final route = TransportRoute(
                id: '',
                schoolId: '',
                name: nameCtrl.text.trim(),
                driverName: driverCtrl.text.trim(),
                driverPhone: phoneCtrl.text.trim(),
                isActive: false,
                currentStopIndex: -1,
                lastUpdated: DateTime.now(),
                stops: parsedStops,
              );

              await _transportService.addRoute(route);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Transport Tracking', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Add Route',
            onPressed: _showAddRouteDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          tabs: const [
            Tab(icon: Icon(Icons.directions_bus_outlined), text: 'Active Transit'),
            Tab(icon: Icon(Icons.settings_outlined), text: 'Routes Info'),
            Tab(icon: Icon(Icons.people_outline), text: 'Student Roster'),
          ],
        ),
      ),
      body: PremiumTabBarView(
        controller: _tabCtrl,
        children: [
          _buildActiveTrackingTab(),
          _buildRoutesInfoTab(),
          _buildRosterTab(),
        ],
      ),
    );
  }

  // ── Tab 1: Active Transit (Update progress stop by stop) ─────────────────────
  Widget _buildActiveTrackingTab() {
    return StreamBuilder<List<TransportRoute>>(
      stream: _transportService.watchAllRoutes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final routes = snapshot.data ?? [];
        if (routes.isEmpty) {
          return _buildEmptyState('No transit routes defined yet.');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final route = routes[index];
            final currentStopName = route.currentStopIndex >= 0 &&
                    route.currentStopIndex < route.stops.length
                ? route.stops[route.currentStopIndex].name
                : 'Not Started';

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: route.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                    child: Icon(
                      Icons.directions_bus,
                      color: route.isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(
                    route.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Text(
                    route.isActive
                        ? 'Active Stop: $currentStopName'
                        : 'Status: Idle / Inactive',
                    style: TextStyle(
                      color: route.isActive ? Colors.green.shade700 : Colors.grey.shade600,
                      fontWeight: route.isActive ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Driver: ${route.driverName}',
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                              Text(
                                'Contact: ${route.driverPhone}',
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final nextActive = !route.isActive;
                                    final nextIndex = nextActive ? 0 : -1;
                                    await _transportService.updateRouteStatus(
                                      route.id,
                                      isActive: nextActive,
                                      currentStopIndex: nextIndex,
                                    );
                                  },
                                  icon: Icon(route.isActive ? Icons.stop : Icons.play_arrow),
                                  label: Text(route.isActive ? 'Stop Journey' : 'Start Journey'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: route.isActive ? Colors.red.shade600 : Colors.green.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (route.isActive) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Update Current Transit Stop:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: List.generate(route.stops.length, (idx) {
                                final stop = route.stops[idx];
                                final isReached = idx <= route.currentStopIndex;
                                final isCurrent = idx == route.currentStopIndex;

                                return ChoiceChip(
                                  label: Text('${stop.sequence}. ${stop.name} (${stop.expectedTime})'),
                                  selected: isCurrent,
                                  onSelected: (selected) async {
                                    if (selected) {
                                      await _transportService.updateRouteStatus(
                                        route.id,
                                        isActive: true,
                                        currentStopIndex: idx,
                                      );
                                    }
                                  },
                                  selectedColor: AppTheme.primary,
                                  disabledColor: Colors.grey.shade100,
                                  labelStyle: TextStyle(
                                    color: isCurrent
                                        ? Colors.white
                                        : isReached
                                            ? Colors.green.shade800
                                            : Colors.grey.shade600,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  backgroundColor: isReached ? Colors.green.shade50 : Colors.grey.shade100,
                                );
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Tab 2: Routes Info (General Details, Stops List, Delete) ──────────────────
  Widget _buildRoutesInfoTab() {
    return StreamBuilder<List<TransportRoute>>(
      stream: _transportService.watchAllRoutes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final routes = snapshot.data ?? [];
        if (routes.isEmpty) {
          return _buildEmptyState('No routes defined.');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: routes.length,
          itemBuilder: (context, index) {
            final route = routes[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            route.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _showDeleteConfirmation(route),
                        ),
                      ],
                    ),
                    Text('Driver: ${route.driverName} | Contact: ${route.driverPhone}'),
                    const SizedBox(height: 12),
                    const Text(
                      'Stops Sequence:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 6),
                    ...route.stops.map((stop) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: AppTheme.primary.withOpacity(0.1),
                                child: Text(
                                  '${stop.sequence}',
                                  style: const TextStyle(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  stop.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                stop.expectedTime,
                                style: const TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Tab 3: Student Roster (Assign routes to students) ────────────────────────
  Widget _buildRosterTab() {
    return StreamBuilder<List<TransportRoute>>(
      stream: _transportService.watchAllRoutes(),
      builder: (context, routeSnap) {
        if (routeSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final routes = routeSnap.data ?? [];

        return StreamBuilder<List<Student>>(
          stream: _studentService.watchStudents(),
          builder: (context, studentSnap) {
            if (studentSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final students = studentSnap.data ?? [];
            if (students.isEmpty) {
              return _buildEmptyState('No students registered in this school.');
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                // Try matching student routeId to list of routes
                final assignedRoute = routes.firstWhere(
                  (r) => r.id == student.transportRouteId,
                  orElse: () => TransportRoute(
                    id: '',
                    schoolId: '',
                    name: 'None Assigned',
                    driverName: '',
                    driverPhone: '',
                    isActive: false,
                    currentStopIndex: -1,
                    lastUpdated: DateTime(2000),
                    stops: [],
                  ),
                );

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppTheme.primary.withOpacity(0.1),
                          child: Text(
                            student.name.isNotEmpty ? student.name[0].toUpperCase() : 'S',
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                student.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                'Class: ${student.className} | Roll: ${student.roll}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              if (student.transportMode != null && student.transportMode!.isNotEmpty)
                                Text(
                                  'Mode: ${student.transportMode}',
                                  style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                ),
                            ],
                          ),
                        ),
                        DropdownButton<String>(
                          value: assignedRoute.id.isEmpty ? null : assignedRoute.id,
                          hint: const Text('Assign Route', style: TextStyle(fontSize: 12)),
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Unassigned', style: TextStyle(fontSize: 12)),
                            ),
                            ...routes.map((r) => DropdownMenuItem<String>(
                                  value: r.id,
                                  child: Text(r.name, style: const TextStyle(fontSize: 12)),
                                )),
                          ],
                          onChanged: (newRouteId) async {
                            final updated = student.copyWith(
                              transportRouteId: newRouteId ?? '',
                            );
                            await _studentService.updateStudent(updated: updated);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Assigned ${student.name} to route!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_bus_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _generateMockRoutes,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Generate Mock Routes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(TransportRoute route) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text('Are you sure you want to delete "${route.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _transportService.deleteRoute(route.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
