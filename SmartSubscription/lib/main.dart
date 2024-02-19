import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Subscriptions',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;

  static final List<Widget> _widgetOptions = <Widget>[
    PersonalCenter(),
    SubscriptionList(),
    CommunityNews(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Subscriptions'),
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Personal',
          ),
          BottomNavigationBarItem(
            icon: Image.asset(
                'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png',
                width: 24,
                height: 24),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum),
            label: 'Community',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueAccent,
        onTap: _onItemTapped,
      ),
    );
  }
}

class PersonalCenter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('Personal Center');
  }
}

class SubscriptionList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final List<Widget> apps = [
      Text('Apple Music                                          £5.99🔔'),
      Text('Amazon                                               £47.49✅'),
      Text('Google Drive                                         £8.99✅'),
      Text('iCloud                                                    £5.99✅'),
      Text('Netflix                                                  £17.99🔔'),
    ];

    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: apps[index],
        );
      },
    );
  }
}

class CommunityNews extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('Community News');
  }
}
