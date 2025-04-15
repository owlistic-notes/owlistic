import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/websocket_provider.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'ThinkStack',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
              context.go('/');
            },
          ),
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text('Notebooks'),
            onTap: () {
              Navigator.pop(context);
              context.go('/notebooks');
            },
          ),
          ListTile(
            leading: const Icon(Icons.note),
            title: const Text('Notes'),
            onTap: () {
              Navigator.pop(context);
              context.go('/notes');
            },
          ),
          ListTile(
            leading: const Icon(Icons.task_alt),
            title: const Text('Tasks'),
            onTap: () {
              Navigator.pop(context);
              context.go('/tasks');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reconnect WebSocket'),
            onTap: () async {
              Navigator.pop(context);
              final wsProvider = Provider.of<WebSocketProvider>(context, listen: false);
              await wsProvider.reconnect();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    wsProvider.isConnected 
                      ? 'WebSocket reconnected!' 
                      : 'WebSocket reconnection failed'
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
