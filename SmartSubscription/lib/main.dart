import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

class DatabaseHelper {
  static final _databaseName = "SubscriptionsDatabase.db";
  static final _databaseVersion = 1;
  static final table = 'subscriptions';

  static final columnId = '_id';
  static final columnName = 'productName';
  static final columnCost = 'cost';
  static final columnBillingCycle = 'billingCycle';
  static final columnSubscriptionDate = 'subscriptionDate';

  // 单例模式
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE $table (
            $columnId INTEGER PRIMARY KEY,
            $columnName TEXT NOT NULL,
            $columnCost REAL NOT NULL,
            $columnBillingCycle TEXT NOT NULL,
            $columnSubscriptionDate TEXT NOT NULL
          )
          ''');
  }

  Future<int> insert(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAllRows() async {
    Database db = await instance.database;
    return await db.query(table);
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class Subscription {
  final String productName;
  final double cost;
  final String billingCycle; // 'Monthly', 'Quarterly', 'Half Yearly', 'Yearly'
  final DateTime subscriptionDate;

  DateTime get nextBillingDate {
    switch (billingCycle.toLowerCase()) {
      case 'monthly':
        return DateTime(subscriptionDate.year, subscriptionDate.month + 1,
            subscriptionDate.day);
      case 'quarterly':
        return DateTime(subscriptionDate.year, subscriptionDate.month + 3,
            subscriptionDate.day);
      case 'half yearly':
        return DateTime(subscriptionDate.year, subscriptionDate.month + 6,
            subscriptionDate.day);
      case 'yearly':
        return DateTime(subscriptionDate.year + 1, subscriptionDate.month,
            subscriptionDate.day);
      default:
        return subscriptionDate; // 默认返回订阅日期
    }
  }

  Subscription({
    required this.productName,
    required this.cost,
    required this.billingCycle,
    required this.subscriptionDate,
  });
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  List<Subscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _loadSubscriptionsFromDatabase();
  }

  void _loadSubscriptionsFromDatabase() async {
    final allRows = await DatabaseHelper.instance.queryAllRows();
    List<Subscription> loadedSubscriptions = allRows
        .map((row) => Subscription(
              productName: row[DatabaseHelper.columnName],
              cost: row[DatabaseHelper.columnCost],
              billingCycle: row[DatabaseHelper.columnBillingCycle],
              subscriptionDate:
                  DateTime.parse(row[DatabaseHelper.columnSubscriptionDate]),
            ))
        .toList();

    setState(() {
      _subscriptions = loadedSubscriptions;
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _navigateAndDisplaySubscriptionForm(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddSubscriptionPage()),
    );

    if (result is Subscription) {
      setState(() {
        _subscriptions.add(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 动态构建 _widgetOptions
    final List<Widget> _widgetOptions = <Widget>[
      PersonalCenter(),
      SubscriptionList(
          subscriptions: _subscriptions), // 这里传入最新的 _subscriptions 列表
      CommunityNews(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Subscriptions'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.add),
            onPressed: () {
              _navigateAndDisplaySubscriptionForm(context);
            },
          ),
        ],
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Personal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home), // 这里也更正为 Icon 类型，而不是 Image.asset
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

class AddSubscriptionPage extends StatefulWidget {
  @override
  _AddSubscriptionPageState createState() => _AddSubscriptionPageState();
}

class _AddSubscriptionPageState extends State<AddSubscriptionPage> {
  final _formKey = GlobalKey<FormState>();
  String productName = '';
  double cost = 0;
  // 将 billingCycle 的初始值设置为 'Monthly' 或其他有效值
  String billingCycle = 'Monthly'; // 这里设置初始值
  DateTime subscriptionDate = DateTime.now();
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: subscriptionDate, // 初始选定日期
      firstDate: DateTime(2000), // 可选日期范围的开始
      lastDate: DateTime(2025), // 可选日期范围的结束
    );
    if (picked != null && picked != subscriptionDate) {
      setState(() {
        subscriptionDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add Subscription')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: <Widget>[
            TextFormField(
              decoration: InputDecoration(labelText: 'Product Name'),
              onSaved: (value) => productName = value ?? '',
            ),
            TextFormField(
              decoration: InputDecoration(labelText: 'Cost (£)'),
              keyboardType: TextInputType.number,
              onSaved: (value) => cost = double.tryParse(value ?? '') ?? 0,
            ),
            // TextFormField(
            //   decoration: InputDecoration(labelText: 'Billing Cycle'),
            //   onSaved: (value) => billingCycle = value ?? '',
            // ),
            DropdownButtonFormField<String>(
              value: billingCycle, // 确保你有一个变量来存储当前选中的值
              onChanged: (String? newValue) {
                setState(() {
                  billingCycle = newValue!;
                });
              },
              items: <String>['Monthly', 'Quarterly', 'Half Yearly', 'Yearly']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              decoration: InputDecoration(
                labelText: 'Billing Cycle',
              ),
            ),
            ElevatedButton(
              child: Text('Add Subscription'),
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _formKey.currentState?.save();
                  // 创建 Subscription 对象
                  Subscription newSubscription = Subscription(
                    productName: productName,
                    cost: cost,
                    billingCycle: billingCycle,
                    subscriptionDate: subscriptionDate,
                  );
                  // 调用方法将订阅信息保存到数据库
                  DatabaseHelper.instance.insert({
                    DatabaseHelper.columnName: newSubscription.productName,
                    DatabaseHelper.columnCost: newSubscription.cost,
                    DatabaseHelper.columnBillingCycle:
                        newSubscription.billingCycle,
                    DatabaseHelper.columnSubscriptionDate:
                        newSubscription.subscriptionDate.toIso8601String(),
                  });
                  Navigator.pop(context, newSubscription);
                }
              },
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: Text('Select Subscription Start Date'),
            )
          ],
        ),
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
  final List<Subscription> subscriptions;

  SubscriptionList({required this.subscriptions});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: subscriptions.length,
      itemBuilder: (context, index) {
        final subscription = subscriptions[index];
        return ListTile(
          title: Text(subscription.productName),
          subtitle: Text(
              'Cost: £${subscription.cost}, Next Billing Date: ${DateFormat('yyyy-MM-dd').format(subscription.nextBillingDate)}'), // 使用 DateFormat 格式化日期
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
