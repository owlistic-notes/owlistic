import 'package:flutter/material.dart';

class TasksScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ThinkStack - Todo'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'ThinkStack Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: Icon(Icons.home),
              title: Text('Home'),
              onTap: () {
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
            ListTile(
              leading: Icon(Icons.task),
              title: Text('Todo'),
              onTap: () {
                Navigator.pushReplacementNamed(context, '/tasks');
              },
            ),
            ListTile(
              leading: Icon(Icons.note),
              title: Text('Notes'),
              onTap: () {
                Navigator.pushReplacementNamed(context, '/notes');
              },
            ),
          ],
        ),
      ),
      body: Center(
        child: Text('This is the Todo screen.'),
      ),
    );
  }
}
