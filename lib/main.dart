import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_webservice/places.dart';

void onBackgroundNotification(NotificationResponse notificationResponse) {}

Future<void> requestIOSPermissions() async {
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/London'));
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

Future<User?> signInWithGoogle() async {
  final GoogleSignIn googleSignIn = GoogleSignIn();
  final GoogleSignInAccount? googleSignInAccount = await googleSignIn.signIn();

  if (googleSignInAccount != null) {
    final GoogleSignInAuthentication googleSignInAuthentication =
        await googleSignInAccount.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleSignInAuthentication.accessToken,
      idToken: googleSignInAuthentication.idToken,
    );

    final UserCredential authResult =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final User? user = authResult.user;

    if (user != null) {
      return user;
    }
  }
  return null;
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class Subscription {
  final String id;
  final String productName;
  final double cost;
  final String billingCycle;
  DateTime subscriptionDate;
  bool isReminded;
  bool isActive;
  DateTime? lastBillingDate;
  String category;

  DateTime get nextBillingDate {
    DateTime baseDate = lastBillingDate ?? subscriptionDate;
    switch (billingCycle.toLowerCase()) {
      case 'monthly':
        return DateTime(baseDate.year, baseDate.month + 1, baseDate.day);
      case 'quarterly':
        return DateTime(baseDate.year, baseDate.month + 3, baseDate.day);
      case 'half yearly':
        return DateTime(baseDate.year, baseDate.month + 6, baseDate.day);
      case 'yearly':
        return DateTime(baseDate.year + 1, baseDate.month, baseDate.day);
      default:
        return baseDate;
    }
  }

  Subscription({
    this.id = '',
    required this.productName,
    required this.cost,
    required this.billingCycle,
    required this.subscriptionDate,
    this.isReminded = false,
    this.isActive = true,
    DateTime? lastBillingDate,
    this.category = '',
  }) : lastBillingDate = lastBillingDate ?? subscriptionDate;

  factory Subscription.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    print("Converting document: ${doc.id} with data: $data");
    return Subscription(
      id: doc.id,
      productName: data['productName'],
      cost: data['cost'],
      billingCycle: data['billingCycle'],
      subscriptionDate: (data['subscriptionDate'] as Timestamp).toDate(),
      isReminded: data['isReminded'] ?? false,
      isActive: data['isActive'] ?? true,
      lastBillingDate: (data['lastBillingDate'] as Timestamp?)?.toDate(),
      category: data['category'] ?? '',
    );
  }

  bool updateBillingDates() {
    final now = DateTime.now();
    if (!isActive) {
      return false;
    }

    DateTime nextBillingDate = calculateNextBillingDate(lastBillingDate!);
    if (now.isAfter(nextBillingDate) || now.isAtSameMomentAs(nextBillingDate)) {
      lastBillingDate = nextBillingDate;
      nextBillingDate = calculateNextBillingDate(lastBillingDate!);
      return true;
    }
    return false;
  }

  DateTime calculateNextBillingDate(DateTime startDate) {
    switch (billingCycle.toLowerCase()) {
      case 'monthly':
        return DateTime(startDate.year, startDate.month + 1, startDate.day);
      case 'quarterly':
        return DateTime(startDate.year, startDate.month + 3, startDate.day);
      case 'half yearly':
        return DateTime(startDate.year, startDate.month + 6, startDate.day);
      case 'yearly':
        return DateTime(startDate.year + 1, startDate.month, startDate.day);
      default:
        return startDate;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'productName': productName,
      'cost': cost,
      'billingCycle': billingCycle,
      'subscriptionDate': Timestamp.fromDate(subscriptionDate),
      'isReminded': isReminded,
      'isActive': isActive,
      'lastBillingDate':
          lastBillingDate != null ? Timestamp.fromDate(lastBillingDate!) : null,
      'category': category,
    };
  }
}

Future<void> addSubscriptionToFirestore(
    Subscription subscription, String userId) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('subscriptions')
      .add(subscription.toFirestore());
}

Future<List<Subscription>> loadSubscriptionsFromFirestore(String userId) async {
  if (userId.isEmpty) {
    print("Error: User ID is empty.");
    return [];
  }
  try {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('subscriptions')
        .get();
    print("Firestore query completed with data count: ${snapshot.docs.length}");
    return snapshot.docs.map((doc) => Subscription.fromFirestore(doc)).toList();
  } catch (e) {
    print("Error loading subscriptions for user $userId: $e");
    return [];
  }
}

Future<void> updateSubscriptionInFirestore(
    Subscription subscription, String userId) async {
  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('subscriptions')
      .doc(subscription.id)
      .update(subscription.toFirestore());
}

enum SortType { startDate, cost, dueDate }

enum SortDirection { ascending, descending }

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  List<Subscription> _subscriptions = [];
  User? _currentUser;
  SortType? currentSortType;
  SortDirection currentSortDirection = SortDirection.ascending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initializeCategories();
      _signInOnStartup();
      _updateAllSubscriptions();
    });
  }

  void _signInOnStartup() async {
    User? user = await signInWithGoogle();
    if (user != null) {
      print("Signed in as: ${user.uid}");
      setState(() {
        _currentUser = user;
      });
      await loadSubscriptions();
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(
          content: Text('Welcome, ${user.displayName}'),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      print("Failed to sign in with Google.");
    }
  }

  Future<void> loadSubscriptions() async {
    if (_currentUser != null) {
      print("Loading subscriptions for user ID: ${_currentUser!.uid}");
      final userId = _currentUser!.uid;
      final List<Subscription> subs =
          await loadSubscriptionsFromFirestore(userId);
      print("Loaded subscriptions count: ${subs.length}");
      setState(() {
        _subscriptions = subs;
        // 如果 PersonalCenter 是 MainScreen 的子组件，并且通过构造器传递 _subscriptions，此处无需其他操作
      });
    } else {
      print("No user signed in.");
    }
  }

  Future<void> initializeCategories() async {
    var customCategories = await loadCustomCategories();
    setState(() {
      categories.addAll(customCategories.where((c) => !categories.contains(c)));
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 1) {
        _updateAllSubscriptions();
      }
    });
  }

  Future<void> _saveSubscriptionUpdates(Subscription subscription) async {
    if (_currentUser != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('subscriptions')
            .doc(subscription.id)
            .update(subscription.toFirestore());
      } catch (e) {}
    }
  }

  void _updateAllSubscriptions() async {
    print("Current user: ${FirebaseAuth.instance.currentUser?.uid}");
    if (_currentUser == null) {
      print("No user signed in.");
      return;
    }
    if (_subscriptions.isEmpty) {
      return;
    }
    bool needUpdate = false;
    for (var subscription in _subscriptions) {
      if (subscription.updateBillingDates()) {
        await updateSubscriptionInFirestore(subscription, _currentUser!.uid);
        needUpdate = true;
      }
    }
    if (needUpdate) {
      await loadSubscriptions();
    }
  }

  void _editSubscription(
      BuildContext context, Subscription subscription) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSubscriptionPage(
            subscription: subscription, currentUser: _currentUser),
      ),
    );
    if (result != null) {
      await loadSubscriptions();
    }
  }

  void _toggleReminder(Subscription subscription) async {
    final newState = !subscription.isReminded;
    subscription.isReminded = newState;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('subscriptions')
        .doc(subscription.id)
        .update({'isReminded': newState});

    if (newState) {
      await scheduleNotification(subscription);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notification status has been changed')),
    );

    loadSubscriptions();
  }

  void _navigateAndDisplaySubscriptionForm(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddSubscriptionPage(currentUser: _currentUser),
      ),
    );
    if (result == true) {
      await loadSubscriptions();
    }
  }

  void sortSubscriptions(SortType type) {
    setState(() {
      if (currentSortType == type) {
        currentSortDirection = currentSortDirection == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending;
      } else {
        currentSortType = type;
        currentSortDirection = type == SortType.cost
            ? SortDirection.descending
            : SortDirection.ascending;
      }

      _subscriptions.sort((a, b) {
        int order = currentSortDirection == SortDirection.ascending ? 1 : -1;
        switch (type) {
          case SortType.startDate:
            return a.subscriptionDate.compareTo(b.subscriptionDate) * order;
          case SortType.cost:
            return a.cost.compareTo(b.cost) * order;
          case SortType.dueDate:
            return a.nextBillingDate.compareTo(b.nextBillingDate) * order;
          default:
            return 0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> actions = [];
    Widget titleWidget = Text("");

    switch (_selectedIndex) {
      case 0: // Personal Tab
        titleWidget = Text("Statistics");
        actions.add(IconButton(
          icon: Icon(Icons.analytics),
          onPressed: () {
            // Navigate to analytics screen
          },
          tooltip: 'Analytics',
        ));
        break;
      case 1: // Home Tab
        titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Smart Subscriptions'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(Icons.date_range),
                  onPressed: () => sortSubscriptions(SortType.startDate),
                  tooltip: 'Sort by Start Date',
                ),
                IconButton(
                  icon: Icon(Icons.monetization_on_outlined),
                  onPressed: () => sortSubscriptions(SortType.cost),
                  tooltip: 'Sort by Cost',
                ),
                IconButton(
                  icon: Icon(Icons.timer),
                  onPressed: () => sortSubscriptions(SortType.dueDate),
                  tooltip: 'Sort by Due Date',
                ),
              ],
            ),
          ],
        );
        actions.add(IconButton(
          icon: Icon(Icons.add),
          onPressed: () => _navigateAndDisplaySubscriptionForm(context),
          tooltip: 'Add Subscriptions',
        ));
        break;
      case 2: // Community Tab
        titleWidget = Text("");
        actions.addAll([
          IconButton(
            icon: Icon(Icons.newspaper),
            onPressed: () {
              // Navigate to news page
            },
            tooltip: 'News',
          ),
          IconButton(
            icon: Icon(Icons.group),
            onPressed: () {
              // This is already the community page
            },
            tooltip: 'Community',
          ),
        ]);
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        actions: actions,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              child: Text('Settings'),
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
            ),
            ListTile(
              leading: Icon(Icons.notifications),
              title: Text('Notification Settings'),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => NotificationSettingsPage(),
                ));
              },
            ),
            ListTile(
              leading: Icon(_currentUser != null ? Icons.logout : Icons.login),
              title: Text(_currentUser != null ? 'Logout' : 'Login'),
              onTap: () async {
                if (_currentUser != null) {
                  await FirebaseAuth.instance.signOut();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Logout successfully')),
                  );
                } else {
                  await signInWithGoogle().then((user) {
                    if (user != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Login successfully')),
                      );
                    }
                  });
                }
                Navigator.of(context).pop();
                setState(() {
                  _currentUser = FirebaseAuth.instance.currentUser;
                });
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: <Widget>[
          PersonalCenter(
              currentUser: _currentUser, subscriptions: _subscriptions),
          SubscriptionList(
            subscriptions: _subscriptions,
            onEdit: _editSubscription,
            onToggleReminder: _toggleReminder,
          ),
          CommunityNews(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Personal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
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
  final User? currentUser;

  const AddSubscriptionPage({Key? key, this.currentUser}) : super(key: key);

  @override
  _AddSubscriptionPageState createState() => _AddSubscriptionPageState();
}

class _AddSubscriptionPageState extends State<AddSubscriptionPage> {
  final _formKey = GlobalKey<FormState>();
  String productName = '';
  double cost = 0;
  String billingCycle = 'Monthly';
  String _category = '';
  bool isActive = true;
  DateTime subscriptionDate = DateTime.now();

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: subscriptionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != subscriptionDate) {
      setState(() {
        subscriptionDate = picked;
      });
    }
  }

  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState?.save();
      Subscription newSubscription = Subscription(
        productName: productName,
        cost: cost,
        billingCycle: billingCycle,
        subscriptionDate: subscriptionDate,
        isActive: isActive,
        category: _category,
      );
      if (widget.currentUser != null) {
        addSubscriptionToFirestore(newSubscription, widget.currentUser!.uid)
            .then((value) => Navigator.pop(context, true))
            .catchError((error) => print("Failed to add subscription: $error"));
      } else {
        print("User not logged in.");
      }
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
            categoryDropdown(_category, context, (newValue) {
              if (newValue == "Custom") {
                promptForCustomCategory(context, (newCategory) {
                  setState(() {
                    _category = newCategory;
                  });
                });
              } else {
                setState(() {
                  _category = newValue!;
                });
              }
            }),
            DropdownButtonFormField<String>(
              value: billingCycle,
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
            SwitchListTile(
              title: Text('Continous Subscription'),
              value: isActive,
              onChanged: (bool value) {
                setState(() {
                  isActive = value;
                });
              },
            ),
            ElevatedButton(
              onPressed: _saveForm,
              child: Text('Add Subscription'),
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: Text('Select Subscription Start Date'),
            ),
          ],
        ),
      ),
    );
  }
}

class EditSubscriptionPage extends StatefulWidget {
  final Subscription subscription;
  final User? currentUser;

  const EditSubscriptionPage({
    Key? key,
    required this.subscription,
    this.currentUser,
  }) : super(key: key);

  @override
  _EditSubscriptionPageState createState() => _EditSubscriptionPageState();
}

class _EditSubscriptionPageState extends State<EditSubscriptionPage> {
  final _formKey = GlobalKey<FormState>();
  late String _productName;
  late double _cost;
  late String _billingCycle;
  late DateTime _subscriptionDate;
  late bool isActive;
  late String _category;

  @override
  void initState() {
    super.initState();
    _productName = widget.subscription.productName;
    _cost = widget.subscription.cost;
    _billingCycle = widget.subscription.billingCycle;
    _subscriptionDate = widget.subscription.subscriptionDate;
    isActive = widget.subscription.isActive;
    _category = widget.subscription.category;
  }

  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      Subscription updatedSubscription = Subscription(
        id: widget.subscription.id,
        productName: _productName,
        cost: _cost,
        billingCycle: _billingCycle,
        subscriptionDate: _subscriptionDate,
        isActive: isActive,
        isReminded: widget.subscription.isReminded,
        category: _category,
      );
      if (widget.currentUser != null) {
        updateSubscriptionInFirestore(
            updatedSubscription, widget.currentUser!.uid);
        Navigator.pop(context, updatedSubscription);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("User not logged in.")),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _subscriptionDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _subscriptionDate) {
      setState(() {
        _subscriptionDate = picked;
      });
    }
  }

  Future<void> _deleteSubscription() async {
    if (widget.currentUser != null && widget.subscription.id.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUser!.uid)
            .collection('subscriptions')
            .doc(widget.subscription.id)
            .delete();
        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete subscription: $e')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("User not logged in or invalid subscription")));
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirm Delete'),
          content: Text('Are you sure you want to delete this subscription?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Delete'),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteSubscription();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Subscription'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: <Widget>[
            TextFormField(
              initialValue: _productName,
              decoration: InputDecoration(labelText: 'Product Name'),
              onSaved: (value) {
                _productName = value ?? '';
              },
            ),
            TextFormField(
              initialValue: _cost.toString(),
              decoration: InputDecoration(labelText: 'Cost (£)'),
              keyboardType: TextInputType.number,
              onSaved: (value) {
                _cost = double.tryParse(value ?? '') ?? 0;
              },
            ),
            categoryDropdown(_category, context, (newValue) {
              if (newValue == "Custom") {
                promptForCustomCategory(context, (newCategory) {
                  setState(() {
                    _category = newCategory;
                  });
                });
              } else {
                setState(() {
                  _category = newValue!;
                });
              }
            }),
            DropdownButtonFormField<String>(
              value: _billingCycle,
              onChanged: (String? newValue) {
                setState(() {
                  _billingCycle = newValue!;
                });
              },
              items: <String>['Monthly', 'Quarterly', 'Half Yearly', 'Yearly']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              decoration: InputDecoration(labelText: 'Billing Cycle'),
            ),
            SwitchListTile(
              title: Text('Continous Subscription'),
              value: isActive,
              onChanged: (bool value) {
                setState(() {
                  isActive = value;
                });
              },
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: Text('Select Subscription Start Date'),
            ),
            ElevatedButton(
              onPressed: _saveForm,
              child: Text('Save Subscription'),
            ),
            ElevatedButton(
              onPressed: _showDeleteDialog,
              child: Text('Delete Subscription'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> categories = [
  'Social Media',
  'Food and Drinks',
  'Entertainment',
  'Lifestyle',
  'Life Services',
  'Education',
  'Work',
  'Finance',
  'Custom'
];

Widget categoryDropdown(String currentValue, BuildContext context,
    ValueChanged<String?> onChanged) {
  return DropdownButtonFormField<String>(
    decoration: InputDecoration(labelText: 'Category'),
    value: categories.contains(currentValue) ? currentValue : null,
    onChanged: (value) {
      if (value == "Custom") {
        promptForCustomCategory(context, (newCategory) {
          if (!categories.contains(newCategory)) {
            categories.add(newCategory);
            addCustomCategory(newCategory);
          }
          onChanged(newCategory);
        });
      } else {
        onChanged(value);
      }
    },
    items: categories.map<DropdownMenuItem<String>>((String category) {
      return DropdownMenuItem<String>(
        value: category,
        child: Text(category),
      );
    }).toList(),
  );
}

void promptForCustomCategory(
    BuildContext context, Function(String) onCategorySelected) {
  TextEditingController customController = TextEditingController();
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text("Enter Custom Category"),
        content: TextField(
          controller: customController,
          autofocus: true,
          decoration: InputDecoration(hintText: "Custom Category Name"),
        ),
        actions: <Widget>[
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            child: Text('OK'),
            onPressed: () {
              String newCategory = customController.text.trim();
              if (newCategory.isNotEmpty) {
                if (!categories.contains(newCategory)) {
                  categories.add(newCategory);
                }
                onCategorySelected(newCategory);
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      );
    },
  );
}

Future<void> addCustomCategory(String category) async {
  var categoriesCollection =
      FirebaseFirestore.instance.collection('custom_categories');
  await categoriesCollection.doc(category).set({'name': category});
}

Future<List<String>> loadCustomCategories() async {
  try {
    var categoriesCollection =
        FirebaseFirestore.instance.collection('custom_categories');
    var snapshot = await categoriesCollection.get();
    List<String> categories =
        snapshot.docs.map((doc) => doc.data()['name'].toString()).toList();
    return categories;
  } catch (e) {
    print("Failed to load custom categories: $e");
    return [];
  }
}

class SubscriptionList extends StatelessWidget {
  final List<Subscription> subscriptions;
  final void Function(BuildContext, Subscription) onEdit;
  final Function(Subscription) onToggleReminder;

  SubscriptionList(
      {required this.subscriptions,
      required this.onEdit,
      required this.onToggleReminder});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: subscriptions.length,
      itemBuilder: (context, index) {
        final subscription = subscriptions[index];
        return GestureDetector(
          onDoubleTap: () => onToggleReminder(subscription),
          child: ListTile(
            title: Text(subscription.productName),
            subtitle: Text(
              'Cost: £${subscription.cost}, Next Billing Date: ${DateFormat('yyyy-MM-dd').format(subscription.nextBillingDate)}',
            ),
            trailing: Icon(
              subscription.isReminded
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              color: subscription.isReminded ? Colors.green : null,
            ),
            onLongPress: () => onEdit(context, subscription),
          ),
        );
      },
    );
  }
}

class NotificationSettingsPage extends StatefulWidget {
  @override
  _NotificationSettingsPageState createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  int _days = 0;
  int _hours = 0;
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _days = prefs.getInt('reminder_days') ?? 0;
      _hours = prefs.getInt('reminder_hours') ?? 0;
      _minutes = prefs.getInt('reminder_minutes') ?? 0;
    });
  }

  Future<void> _saveNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminder_days', _days);
    await prefs.setInt('reminder_hours', _hours);
    await prefs.setInt('reminder_minutes', _minutes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Notification Settings')),
      body: Column(
        children: <Widget>[
          ListTile(
            title: Text('Days before'),
            trailing: DropdownButton<int>(
              value: _days,
              onChanged: (int? newValue) {
                setState(() {
                  _days = newValue!;
                });
                _saveNotificationSettings();
              },
              items: List.generate(31, (index) => index)
                  .map<DropdownMenuItem<int>>((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text(value.toString()),
                );
              }).toList(),
            ),
          ),
          ListTile(
            title: Text('Hours before'),
            trailing: DropdownButton<int>(
              value: _hours,
              onChanged: (int? newValue) {
                setState(() {
                  _hours = newValue!;
                });
                _saveNotificationSettings();
              },
              items: List.generate(24, (index) => index)
                  .map<DropdownMenuItem<int>>((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text(value.toString()),
                );
              }).toList(),
            ),
          ),
          ListTile(
            title: Text('Minutes before'),
            trailing: DropdownButton<int>(
              value: _minutes,
              onChanged: (int? newValue) {
                setState(() {
                  _minutes = newValue!;
                });
                _saveNotificationSettings();
              },
              items: List.generate(60, (index) => index)
                  .map<DropdownMenuItem<int>>((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text(value.toString()),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _saveReminderTime(String time) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('reminderTime', time);
}

Future<String> _loadReminderTime() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('reminderTime') ?? '1.75 hour';
}

Future<void> _initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) async {},
    onDidReceiveBackgroundNotificationResponse: onBackgroundNotification,
  );
}

Future<void> scheduleNotification(Subscription subscription) async {
  final prefs = await SharedPreferences.getInstance();
  int days = prefs.getInt('reminder_days') ?? 0;
  int hours = prefs.getInt('reminder_hours') ?? 0;
  int minutes = prefs.getInt('reminder_minutes') ?? 0;

  final notificationTime =
      tz.TZDateTime.from(subscription.nextBillingDate, tz.local)
          .subtract(Duration(days: days, hours: hours, minutes: minutes));

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'subscription_reminder_channel',
    'Subscription Reminders',
    channelDescription: 'Reminder for upcoming subscription payments',
    importance: Importance.high,
    priority: Priority.high,
  );

  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Reminder: ${subscription.productName}',
      'Your ${subscription.productName} subscription will be charged on ${DateFormat('yyyy-MM-dd').format(subscription.nextBillingDate)}',
      notificationTime,
      platformDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime);
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class PersonalCenter extends StatefulWidget {
  final User? currentUser;
  final List<Subscription> subscriptions;

  PersonalCenter({Key? key, this.currentUser, required this.subscriptions})
      : super(key: key);

  @override
  _PersonalCenterState createState() => _PersonalCenterState();
}

class _PersonalCenterState extends State<PersonalCenter> {
  late Future<Map<String, double>> _categoryData;
  late Future<Map<String, double>> _monthlyAverageData;
  late Future<double> _totalMonthlyCost;

  @override
  void initState() {
    super.initState();
    _categoryData = _fetchCategoryData();
    _monthlyAverageData = _fetchMonthlyAverageCost();
    _totalMonthlyCost = _fetchTotalMonthlyCost();
  }

  void didUpdateWidget(PersonalCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subscriptions != oldWidget.subscriptions) {
      _categoryData = _fetchCategoryData(); // 重新计算类别数据
      _monthlyAverageData = _fetchMonthlyAverageCost(); // 重新计算月均费用
      _totalMonthlyCost = _fetchTotalMonthlyCost(); // 重新计算总月费用
    }
  }

  Future<Map<String, double>> _fetchCategoryData() async {
    print("Subscriptions: ${widget.subscriptions}");
    print("Total subscriptions: ${widget.subscriptions.length}"); // 打印总订阅数
    Map<String, int> categoryCounts = {};

    for (var subscription in widget.subscriptions) {
      categoryCounts[subscription.category] =
          (categoryCounts[subscription.category] ?? 0) + 1;
    }

    int total = widget.subscriptions.length;
    Map<String, double> categoryPercentages = {};
    if (total > 0) {
      categoryCounts.forEach((key, value) {
        categoryPercentages[key] = (value / total) * 100;
        print(
            "Category: $key, Percentage: ${categoryPercentages[key]}"); // 打印每个类别的百分比
      });
    } else {
      print("No data to display"); // 如果没有订阅数据
    }

    return categoryPercentages;
  }

  Future<Map<String, double>> _fetchMonthlyAverageCost() async {
    Map<String, double> categoryMonthlyCosts = {};

    for (var subscription in widget.subscriptions) {
      String category = subscription.category;
      double monthlyCost =
          subscription.cost / _getMonthlyDivisor(subscription.billingCycle);
      categoryMonthlyCosts[category] =
          (categoryMonthlyCosts[category] ?? 0) + monthlyCost;
    }

    return categoryMonthlyCosts;
  }

  int _getMonthlyDivisor(String billingCycle) {
    switch (billingCycle.toLowerCase()) {
      case 'monthly':
        return 1;
      case 'quarterly':
        return 3;
      case 'half yearly':
        return 6;
      case 'yearly':
        return 12;
      default:
        return 1; // Default to monthly if unrecognized
    }
  }

  Future<double> _fetchTotalMonthlyCost() async {
    double totalMonthlyCost = 0;
    Map<String, double> monthlyCosts = await _fetchMonthlyAverageCost();
    monthlyCosts.forEach((key, value) {
      totalMonthlyCost += value;
    });
    return totalMonthlyCost;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Container(
              height: 700, // 分配足够的空间给饼图，避免截断
              padding: const EdgeInsets.all(10.0), // 留出边距
              child: FutureBuilder<Map<String, double>>(
                future: _categoryData,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      return PieChartPage(data: snapshot.data!);
                    } else {
                      return Text("No data available");
                    }
                  }
                  return CircularProgressIndicator();
                },
              ),
            ),
            ListTile(
              title: Text('Monthly Average Costs by Category'),
              subtitle: FutureBuilder<Map<String, double>>(
                future: _monthlyAverageData,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: snapshot.data!.entries
                          .map((entry) => Text(
                              '${entry.key}: £${entry.value.toStringAsFixed(2)}'))
                          .toList(),
                    );
                  }
                  return CircularProgressIndicator();
                },
              ),
            ),
            FutureBuilder<double>(
              future: _totalMonthlyCost,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  return ListTile(
                    title: Text(
                      'Total Monthly Cost',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '£${snapshot.data!.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                }
                return CircularProgressIndicator();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PieChartWidget extends StatelessWidget {
  final Map<String, double> data;

  PieChartWidget({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    List<PieChartSectionData> sections = data.entries.map((entry) {
      return PieChartSectionData(
        color: Colors.primaries[
            data.keys.toList().indexOf(entry.key) % Colors.primaries.length],
        value: entry.value,
        title: '${entry.key}',
        radius: 75,
        titleStyle: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        titlePositionPercentageOffset: 0.55,
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 35,
        sectionsSpace: 2,
        // pieTouchData: PieTouchData(touchCallback: (pieTouchResponse) {
        // }),
      ),
    );
  }
}

class PieChartPage extends StatelessWidget {
  final Map<String, double> data;

  PieChartPage({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PieChartWidget(data: data),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: data.entries.map((entry) {
              return ListTile(
                leading: Icon(Icons.circle,
                    color: Colors.primaries[
                        data.keys.toList().indexOf(entry.key) %
                            Colors.primaries.length]),
                title: Text('${entry.key}'),
                trailing: Text('${entry.value.toStringAsFixed(1)}%'),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class CommunityNews extends StatefulWidget {
  @override
  _CommunityNewsState createState() => _CommunityNewsState();
}

class _CommunityNewsState extends State<CommunityNews> {
  // ignore: unused_field
  GoogleMapController? _controller;
  Set<Marker> _markers = {};
  final _places =
      GoogleMapsPlaces(apiKey: "AIzaSyCeEOjxJg1NYtJX5iK0Cy8hfaRJ-q2XzWU");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: LatLng(51.5082543, -0.0091798),
          zoom: 14.0,
        ),
        markers: _markers,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _searchNearby,
        tooltip: 'Search Nearby',
        child: Icon(Icons.search),
      ),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
  }

  void _searchNearby() async {
    final location = Location(lat: 51.5082543, lng: -0.0091798);
    final result = await _places.searchNearbyWithRadius(location, 10000);

    setState(() {
      _markers.clear();
      if (result.status == "OK") {
        for (var place in result.results) {
          final lat = place.geometry?.location.lat;
          final lng = place.geometry?.location.lng;
          final types = place.types;
          if (lat != null && lng != null) {
            if (types.contains('gym') ||
                types.contains('movie_theater') ||
                types.contains('theater') ||
                types.contains('art_gallery') ||
                types.contains('museum') ||
                types.contains('spa') ||
                types.contains('golf_course') ||
                types.contains('amusement_park')) {
              _markers.add(
                Marker(
                  markerId: MarkerId(place.placeId),
                  position: LatLng(lat, lng),
                  infoWindow:
                      InfoWindow(title: place.name, snippet: place.vicinity),
                ),
              );
            }
          }
        }
      } else {
        print("Failed to fetch places: ${result.errorMessage}");
      }
    });
  }
}
