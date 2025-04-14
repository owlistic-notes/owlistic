import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ThinkStack - Home'),
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
        child: Text('Welcome to ThinkStack!'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            final notes = await ApiService.fetchNotes();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Fetched ${notes.length} notes')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to fetch notes: $e')),
            );
          }
        },
        child: Icon(Icons.cloud_download),
      ),
    );
  }
}
