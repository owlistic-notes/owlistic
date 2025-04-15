import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'ThinkStack',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(Icons.home),
            title: Text('Home'),
            onTap: () {
              Navigator.pop(context); // Close drawer
              context.go('/');
            },
          ),
          ListTile(
            leading: Icon(Icons.note),
            title: Text('Notes'),
            onTap: () {
              Navigator.pop(context); // Close drawer
              context.go('/notes');
            },
          ),
          ListTile(
            leading: Icon(Icons.task),
            title: Text('Tasks'),
            onTap: () {
              Navigator.pop(context); // Close drawer
              context.go('/tasks');
            },
          ),
          ListTile(
            leading: Icon(Icons.book),
            title: Text('Notebooks'),
            onTap: () {
              Navigator.pop(context);
              context.go('/notebooks');
            },
          ),
        ],
      ),
    );
  }
}
