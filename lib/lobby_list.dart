// lobby_list.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'dart:html' as html;
import 'package:intl/intl.dart';
import 'services/document_service.dart';
import 'pages/community_page.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async'; // Для StreamSubscription
import 'account_settings.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui'; // Для ImageFilter
import 'backend.dart';
import 'news.dart';
import 'package:audioplayers/audioplayers.dart';

// Removed the main() function from this file

// Enums for access levels
enum AccessLevel {
  read,
  full,
}

class Lobby {
  String name;
  final String password;
  AccessLevel accessLevel;
  final String creatorId;
  final String creatorName;
  Map<String, dynamic> content;

  Lobby({
    required this.name,
    required this.password,
    required this.accessLevel,
    required this.creatorId,
    required this.creatorName,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'password': password,
      'accessLevel': accessLevel.toString(),
      'creatorId': creatorId,
      'creatorName': creatorName,
      'content': content,
    };
  }

  factory Lobby.fromJson(Map<String, dynamic> json) {
    return Lobby(
      name: json['name'] as String,
      password: json['password'] as String,
      accessLevel: AccessLevel.values.firstWhere(
        (e) => e.toString() == json['accessLevel'],
        orElse: () => AccessLevel.read,
      ),
      creatorId: json['creatorId'] as String,
      creatorName: json['creatorName'] as String,
      content: json['content'] as Map<String, dynamic>? ?? {'documents': []},
    );
  }
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with TickerProviderStateMixin {
  List<Lobby> _lobbies = [];
  final TextEditingController _searchController = TextEditingController();
  List<Lobby> _filteredLobbies = [];
  bool _isLoading = true;
  User? _currentUser;
  late DatabaseReference _lobbiesRef;
  StreamSubscription<DatabaseEvent>? _lobbiesSubscription;
  
  // Добавляем контроллеры анимаций
  late AnimationController _fadeController;
  late AnimationController _listController;
  late Animation<double> _fadeAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _initializeFirebase();
    _searchController.addListener(_filterLobbies);
    
    // Инициализация анимаций
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _listController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _fadeController.forward();
    _listController.forward();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      if (kIsWeb) {
        await _audioPlayer.setSource(AssetSource('sounds/success.mp3'));
      } else {
        await _audioPlayer.setSource(AssetSource('assets/sounds/success.mp3'));
      }
      _isAudioInitialized = true;
    } catch (e) {
      debugPrint('Error initializing audio: $e');
    }
  }

  Future<void> _playSuccessSound() async {
    if (!_isAudioInitialized) {
      await _initAudio();
    }
    try {
      if (kIsWeb) {
        await _audioPlayer.play(AssetSource('sounds/success.mp3'));
      } else {
        await _audioPlayer.play(AssetSource('assets/sounds/success.mp3'));
      }
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  Future<void> _loadCurrentUser() async {
    FirebaseAuth auth = FirebaseAuth.instance;
    User? user = auth.currentUser;
    setState(() {
      _currentUser = user;
    });
  }

  void _initializeFirebase() {
    // Для веб-версии просто получаем ссылку на базу данных
    _lobbiesRef = FirebaseDatabase.instance.ref().child('lobbies');
    
    // Подписываемся на обновления
    _subscribeToLobbies();
  }

  void _subscribeToLobbies() {
    _lobbiesSubscription = _lobbiesRef
      .onValue.listen((event) {
        // Check if widget is mounted before proceeding
        if (!mounted) return;
        
        if (event.snapshot.value != null) {
          final dynamic lobbies = event.snapshot.value;
          if (lobbies is Map) {
            final List<Lobby> lobbiesList = [];
            lobbies.forEach((key, value) {
              if (value is Map) {
                try {
                  final lobby = Lobby.fromJson(Map<String, dynamic>.from(value));
                  lobbiesList.add(lobby);
                } catch (e) {
                  print('Error parsing lobby: $e');
                }
              }
            });
          
            // Check mounted again before setState
            if (mounted) {
              setState(() {
                _lobbies = lobbiesList;
                _filteredLobbies = List.from(lobbiesList);
                _isLoading = false;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() {
              _lobbies = [];
              _filteredLobbies = [];
              _isLoading = false;
            });
          }
        }
    }, onError: (error) {
      print('Ошибка при получении данных лобби: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _filterLobbies() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredLobbies = _lobbies.where((lobby) {
        return lobby.name.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _saveLobbies() async {
    final prefs = await SharedPreferences.getInstance();
    final lobbiesJson = jsonEncode(_lobbies.map((e) => e.toJson()).toList());
    await prefs.setString('lobbies', lobbiesJson);
  }

  void _showCreateLobbyDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    AccessLevel selectedAccess = AccessLevel.read;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создание нового лобби'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Название лобби',
                hintText: 'Введите название лобби',
                prefixIcon: const Icon(Icons.group),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Пароль',
                hintText: 'Введите пароль для лобби',
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Уровень доступа:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<AccessLevel>(
                          title: Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text('Только чтение'),
                            ],
                          ),
                          subtitle: const Text(
                            'Участники могут только просматривать документы',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: AccessLevel.read,
                          groupValue: selectedAccess,
                          onChanged: (AccessLevel? value) {
                            setState(() => selectedAccess = value!);
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<AccessLevel>(
                          title: Row(
                            children: [
                              Icon(
                                Icons.edit,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text('Полный доступ'),
                            ],
                          ),
                          subtitle: const Text(
                            'Участники могут добавлять и редактировать документы',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: AccessLevel.full,
                          groupValue: selectedAccess,
                          onChanged: (AccessLevel? value) {
                            setState(() => selectedAccess = value!);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Заполните все поля'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Проверка на уникальность имени
              final snapshot = await _lobbiesRef.get();
              if (snapshot.value != null && snapshot.value is Map) {
                final lobbies = snapshot.value as Map;
                if (lobbies.values.any((lobby) => 
                    lobby is Map && lobby['name'] == nameController.text)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Лобби с таким названием уже существует'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }
              }

              final newLobby = Lobby(
                name: nameController.text,
                password: passwordController.text,
                accessLevel: selectedAccess,
                creatorId: _currentUser?.uid ?? 'anonymous',
                creatorName: _currentUser?.displayName ?? 'Гость',
                content: {'documents': []},
              );

              try {
                await _lobbiesRef.push().set(newLobby.toJson());
                await _playSuccessSound(); // Используйте новый метод
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Лобби успешно создано'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка при создании лобби: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: theme.colorScheme.primary.withOpacity(0.2),
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.folder_shared, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Лобби',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _currentUser?.displayName ?? 'Гость',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _buildActionButton(
            icon: Icons.how_to_vote,
            label: 'Голосование',
            onTap: _openVotingSite,
          ),
          _buildActionButton(
            icon: Icons.forum,
            label: 'Сообщество',
            onTap: () => _navigateToPage('/community', const CommunityPage()),
          ),
          _buildActionButton(
            icon: Icons.newspaper,
            label: 'Новости',
            onTap: () => _navigateToPage('/news', const NewsPage()),
          ),
          
          _buildActionButton(
            icon: Icons.person,
            label: 'Профиль',
            onTap: () => _navigateToPage('/account', const AccountSettingsPage()),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withOpacity(0.1),
              Colors.white,
              theme.colorScheme.secondary.withOpacity(0.05),
            ],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: kToolbarHeight + 20),
              // Поисковая строка с анимацией
              SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _fadeController,
                  curve: const Interval(0.2, 0.8, curve: Curves.easeOutBack),
                )),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Поиск лобби...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                        ),
                        prefixIcon: Container(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.search_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Статистика лобби
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.groups,
                      title: 'All lobbies',
                      value: _filteredLobbies.length.toString(),
                      theme: theme,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.visibility,
                      title: 'Read',
                      value: _filteredLobbies.where((l) => l.accessLevel == AccessLevel.read).length.toString(),
                      theme: theme,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.edit,
                      title: 'Edited',
                      value: _filteredLobbies.where((l) => l.accessLevel == AccessLevel.full).length.toString(),
                      theme: theme,
                    ),
                  ],
                ),
              ),
              
              // Список лобби
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: LoadingIndicatorWidget(),
                      )
                    : _filteredLobbies.isEmpty
                        ? _buildEmptyState(theme)
                        : AnimatedList(
                            key: GlobalKey<AnimatedListState>(),
                            initialItemCount: _filteredLobbies.length,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              bottom: 100,
                            ),
                            itemBuilder: (context, index, animation) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: _buildLobbyCard(_filteredLobbies[index], theme),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(
          parent: _fadeController,
          curve: const Interval(0.6, 1.0, curve: Curves.elasticOut),
        ),
        child: FloatingActionButton.extended(
          onPressed: _showCreateLobbyDialog,
          elevation: 4,
          backgroundColor: theme.colorScheme.primary,
          icon: const Icon(Icons.add_circle_outline, size: 24),
          label: const Text(
            'Создать лобби',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required ThemeData theme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyCard(Lobby lobby, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _enterLobby(lobby),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildLobbyIcon(lobby, theme),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lobby.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  lobby.creatorName,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _buildAccessLevelBadge(lobby, theme),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildLobbyStats(lobby, theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyIcon(Lobby lobby, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Icon(
        lobby.accessLevel == AccessLevel.read
            ? Icons.visibility_rounded
            : Icons.edit_rounded,
        color: theme.colorScheme.primary,
        size: 24,
      ),
    );
  }

  Widget _buildAccessLevelBadge(Lobby lobby, ThemeData theme) {
    final isReadOnly = lobby.accessLevel == AccessLevel.read;
    final color = isReadOnly ? Colors.blue : Colors.green;
    
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReadOnly ? Icons.lock_outline : Icons.edit_outlined,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            isReadOnly ? 'Чтение' : 'Редактирование',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyStats(Lobby lobby, ThemeData theme) {
    return StreamBuilder<dynamic>(
      stream: Stream.periodic(const Duration(seconds: 5)).asyncMap((_) => 
        ApiService().getDataList('documents/', false)
      ),
      builder: (context, snapshot) {
        int docCount = 0;
        String lastUpdate = '0 документов';
        
        if (snapshot.hasData && snapshot.data != null) {
          final documents = snapshot.data.where((doc) => doc['lobby_name'] == lobby.name).toList();
          docCount = documents.length;
          if (documents.isNotEmpty) {
            lastUpdate = DateFormat('dd.MM.yy HH:mm').format(
              DateTime.parse(documents.last['upload_date']).toLocal()
            );
          }
        }

        return Row(
          children: [
            _buildStatItem(
              icon: Icons.description_outlined,
              value: '$docCount',
              label: 'Документов',
              theme: theme,
            ),
            const SizedBox(width: 16),
            _buildStatItem(
              icon: Icons.access_time_outlined,
              value: lastUpdate,
              label: 'Обновлено',
              theme: theme,
            ),
          ],
        );
      }
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.primary.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Лобби не найдены',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Попробуйте изменить параметры поиска\nили создайте новое лобби',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _showCreateLobbyDialog,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Создать лобби'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _enterLobby(Lobby lobby) {
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController newNameController = TextEditingController();
    AccessLevel selectedAccess = lobby.accessLevel;
    bool isEditingSettings = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Лобби "${lobby.name}"'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEditingSettings) ...[
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Введите пароль',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          lobby.accessLevel == AccessLevel.read
                              ? Icons.visibility
                              : Icons.edit,
                          color: lobby.accessLevel == AccessLevel.read
                              ? Colors.blue
                              : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Уровень доступа: ${lobby.accessLevel == AccessLevel.read ? "Только чтение" : "Полный доступ"}',
                            style: TextStyle(
                              color: lobby.accessLevel == AccessLevel.read
                                  ? Colors.blue
                                  : Colors.green,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Настройки лобби',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newNameController,
                    decoration: InputDecoration(
                      labelText: 'Новое название',
                      hintText: 'Оставьте пустым, чтобы не менять',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.edit),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Новый пароль',
                      hintText: 'Оставьте пустым, чтобы не менять',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.lock_reset),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<AccessLevel>(
                          title: Row(
                            children: const [
                              Icon(
                                Icons.visibility,
                                color: Colors.blue,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text('Только чтение'),
                            ],
                          ),
                          subtitle: const Text(
                            'Участники могут только просматривать документы',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: AccessLevel.read,
                          groupValue: selectedAccess,
                          onChanged: (AccessLevel? value) {
                            setDialogState(() => selectedAccess = value!);
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<AccessLevel>(
                          title: Row(
                            children: const [
                              Icon(
                                Icons.edit,
                                color: Colors.green,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text('Полный доступ'),
                            ],
                          ),
                          subtitle: const Text(
                            'Участники могут добавлять и редактировать документы',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: AccessLevel.full,
                          groupValue: selectedAccess,
                          onChanged: (AccessLevel? value) {
                            setDialogState(() => selectedAccess = value!);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (!isEditingSettings && lobby.creatorId == _currentUser?.uid)
              TextButton.icon(
                onPressed: () {
                  setDialogState(() => isEditingSettings = true);
                },
                icon: const Icon(Icons.settings),
                label: const Text('Настройки'),
              ),
            if (isEditingSettings) ...[
              TextButton.icon(
                onPressed: () async {
                  final TextEditingController confirmController = TextEditingController();
                  final bool? shouldDelete = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Удаление лобби'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Для подтверждения удаления введите слово "ПОДТВЕРДИТЬ"',
                            style: TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: confirmController,
                            decoration: InputDecoration(
                              hintText: 'ПОДТВЕРДИТЬ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Отмена'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            if (confirmController.text == 'ПОДТВЕРДИТЬ') {
                              Navigator.of(context).pop(true);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Неверное слово подтверждения'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
                  );

                  if (shouldDelete == true) {
                    try {
                      final snapshot = await _lobbiesRef.get();
                      String? lobbyKey;
                      if (snapshot.value != null && snapshot.value is Map) {
                        final lobbies = snapshot.value as Map;
                        lobbies.forEach((key, value) {
                          if (value['name'] == lobby.name) {
                            lobbyKey = key;
                          }
                        });
                      }

                      if (lobbyKey != null) {
                        // Сначала удаляем все документы этого лобби
                        try {
                          final docs = await ApiService().getDataList('documents/', false);
                          final lobbyDocs = docs.where((doc) => doc['lobby_name'] == lobby.name).toList();
                          
                          // Удаляем каждый документ
                          for (var doc in lobbyDocs) {
                            await ApiService().deleteData('documents/${doc['id']}/');
                          }
                        } catch (e) {
                          print('Ошибка при удалении документов: $e');
                        }

                        // Затем удаляем само лобби
                        await _lobbiesRef.child(lobbyKey!).remove();
                        
                        if (mounted) {
                          Navigator.of(context).pop(); // Закрываем диалог настроек
                          Navigator.of(context).pop(); // Возвращаемся к списку лобби
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Лобби и все его документы успешно удалены'),
                              backgroundColor: Colors.green,
                            ),
                          );

                          // Безопасное обновление страницы
                          if (mounted) {
                            Future.microtask(() {
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LobbyScreen(),
                                  ),
                                  (route) => false,
                                );
                              }
                            });
                          }
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ошибка при удалении лобби: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text('Удалить лобби', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () {
                  setDialogState(() => isEditingSettings = false);
                },
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    if (newNameController.text.isNotEmpty) {
                      print('Имя лобби изменено');
                      // Проверка на уникальность нового имени
                      final snapshot = await FirebaseDatabase.instance.ref().child('lobbies').get();
                      if (snapshot.value != null && snapshot.value is Map) {
                        final lobbies = snapshot.value as Map;
                        if (lobbies.values.any((l) => 
                            l is Map && 
                            l['name'] == newNameController.text && 
                            l['name'] != lobby.name)) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Лобби с таким названием уже существует'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          return;
                        }
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Ошибка при проверке имени: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  final updatedLobby = Lobby(
                    name: newNameController.text.isNotEmpty 
                        ? newNameController.text 
                        : lobby.name,
                    password: newPasswordController.text.isNotEmpty
                        ? newPasswordController.text
                        : lobby.password,
                    accessLevel: selectedAccess,
                    creatorId: lobby.creatorId,
                    creatorName: lobby.creatorName,
                    content: lobby.content,
                  );

                  final snapshot = await _lobbiesRef.get();
                  String? lobbyKey;
                  if (snapshot.value != null && snapshot.value is Map) {
                    final lobbies = snapshot.value as Map;
                    lobbies.forEach((key, value) {
                      if (value['name'] == lobby.name) {
                        lobbyKey = key;
                      }
                    });
                  }

                  if (lobbyKey != null) {
                    await _lobbiesRef.child(lobbyKey!).update(updatedLobby.toJson());
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Настройки лобби обновлены'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Сохранить'),
              ),
            ] else
              ElevatedButton(
                onPressed: () async {
                  if (passwordController.text == lobby.password) {
                    Navigator.of(context).pop();
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => LobbyDetailScreen(
                          lobby: lobby,
                          saveLobbies: _saveLobbies,
                          currentUser: _currentUser,
                        ),
                      ),
                    );
                    
                    if (result == true) {
                      await _loadLobbies();
                      setState(() {
                        _filterLobbies();
                      });
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Неверный пароль!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Войти'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _fadeController.dispose();
    _listController.dispose();
    _lobbiesSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLobbies() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _lobbiesRef.get();
      if (snapshot.value != null) {
        final dynamic lobbies = snapshot.value;
        if (lobbies is Map) {
          final List<Lobby> lobbiesList = [];
          lobbies.forEach((key, value) {
            if (value is Map) {
              try {
                final lobby = Lobby.fromJson(Map<String, dynamic>.from(value));
                lobbiesList.add(lobby);
              } catch (e) {
                print('Error parsing lobby: $e');
              }
            }
          });
          
          if (mounted) {
            setState(() {
              _lobbies = lobbiesList;
              _filteredLobbies = List.from(lobbiesList);
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      print('Ошибка при загрузке лобби: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToPage(String route, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => page,
        settings: RouteSettings(name: route),
      ),
    );
  }

  void _openVotingSite() async {
    const url = 'http://localhost:3000/'; // Замените на реальный URL сайта для голосования
    if (kIsWeb) {
      // Для веб-версии
      html.window.open(url, '_blank');
    } else {
      // Для мобильных устройств
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось открыть сайт для голосования'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class LoadingIndicatorWidget extends StatelessWidget {
  const LoadingIndicatorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Загрузка лобби...',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

// Rest of the code remains the same, just update LobbyDetailScreen to respect access levels
class LobbyDetailScreen extends StatefulWidget {
  final Lobby lobby;
  final Future<void> Function() saveLobbies;
   final User? currentUser;


  const LobbyDetailScreen({
    required this.lobby,
    required this.saveLobbies,
      this.currentUser,
    super.key,
  });

  @override
  _LobbyDetailScreenState createState() => _LobbyDetailScreenState();
}

class _LobbyDetailScreenState extends State<LobbyDetailScreen> {
  final DocumentService _documentService = DocumentService();
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  bool _isMultiSelectMode = false;
  Set<int> _selectedDocuments = {};

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    try {
      // Create a single timer and store its reference
      Timer? updateTimer;
      updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        // Check if widget is still mounted before proceeding
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        try {
          final docs = await _documentService.getDocumentsForLobby(widget.lobby.name);
          final filteredDocs = docs.where((doc) => 
            doc['lobby_name'] == widget.lobby.name
          ).toList();
          
          // Check mounted again before setState
          if (mounted) {
            setState(() {
              _documents = filteredDocs;
              _isLoading = false;
            });
          }
        } catch (e) {
          print('Error updating documents: $e');
          // Check mounted before showing error
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error updating documents: $e')),
            );
          }
        }
      });

      // Store the timer in a field so we can cancel it in dispose
      _updateTimer = updateTimer;

      // Initial load
      final docs = await _documentService.getDocumentsForLobby(widget.lobby.name);
      final filteredDocs = docs.where((doc) => 
        doc['lobby_name'] == widget.lobby.name
      ).toList();
      
      if (mounted) {
        setState(() {
          _documents = filteredDocs;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading documents: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading documents: $e')),
        );
      }
    }
  }

  // Add timer field and cancel it in dispose
  Timer? _updateTimer;

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickPdfFile() async {
    if (widget.currentUser == null || widget.lobby.creatorId != widget.currentUser!.uid) {
      if (widget.lobby.accessLevel == AccessLevel.read) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('У вас нет прав для загрузки файлов'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true, // Разрешаем выбор нескольких файлов
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() => _isLoading = true);
        
        // Загружаем каждый выбранный файл
        for (PlatformFile file in result.files) {
          print('Выбран файл: ${file.name}');
          print('Размер файла: ${file.size} bytes');
          
          await _documentService.uploadDocument(
            file: file,
            lobbyName: widget.lobby.name,
            uploader: widget.currentUser?.email ?? 'anonymous',
            context: context,
          );
        }

        // Обновляем список документов после загрузки всех файлов
        final docs = await _documentService.getDocumentsForLobby(widget.lobby.name);
        if (mounted) {
          setState(() {
            _documents = docs.where((doc) => 
              doc['lobby_name'] == widget.lobby.name
            ).toList();
            _isLoading = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Загружено ${result.files.length} документов'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Ошибка при выборе файлов: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при выборе файлов: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSelectedDocuments() async {
    if (_selectedDocuments.isEmpty) return;

    if (widget.currentUser == null || widget.lobby.creatorId != widget.currentUser!.uid) {
      if (widget.lobby.accessLevel == AccessLevel.read) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('У вас нет прав для удаления файлов'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: Text('Вы уверены, что хотите удалить ${_selectedDocuments.length} документов?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      setState(() => _isLoading = true);
      try {
        for (int documentId in _selectedDocuments) {
          await _documentService.deleteDocument(documentId);
        }
        
        // Обновляем список после удаления
        final docs = await _documentService.getDocumentsForLobby(widget.lobby.name);
        if (mounted) {
          setState(() {
            _documents = docs.where((doc) => 
              doc['lobby_name'] == widget.lobby.name
            ).toList();
            _selectedDocuments.clear();
            _isMultiSelectMode = false;
            _isLoading = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Выбранные документы успешно удалены'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка при удалении документов: $e'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _downloadDocument(String fileUrl) async {
    setState(() => _isLoading = true);
    try {
      await _documentService.downloadDocument(fileUrl, context);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showLobbySettings() {
    final TextEditingController newNameController = TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    AccessLevel selectedAccess = widget.lobby.accessLevel;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройки лобби'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newNameController,
              decoration: InputDecoration(
                labelText: 'Новое название',
                hintText: 'Оставьте пустым, чтобы не менять',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Новый пароль',
                hintText: 'Оставьте пустым, чтобы не менять',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.lock_reset),
              ),
            ),
            const SizedBox(height: 16),
            StatefulBuilder(
              builder: (context, setState) => Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    RadioListTile<AccessLevel>(
                      title: Row(
                        children: const [
                          Icon(Icons.visibility, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text('Только чтение'),
                        ],
                      ),
                      subtitle: const Text(
                        'Участники могут только просматривать документы',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: AccessLevel.read,
                      groupValue: selectedAccess,
                      onChanged: (AccessLevel? value) {
                        setState(() => selectedAccess = value!);
                      },
                    ),
                    const Divider(height: 1),
                    RadioListTile<AccessLevel>(
                      title: Row(
                        children: const [
                          Icon(Icons.edit, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Text('Полный доступ'),
                        ],
                      ),
                      subtitle: const Text(
                        'Участники могут добавлять и редактировать документы',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: AccessLevel.full,
                      groupValue: selectedAccess,
                      onChanged: (AccessLevel? value) {
                        setState(() => selectedAccess = value!);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                if (newNameController.text.isNotEmpty) {
                  print('Имя лобби изменено');
                  // Проверка на уникальность нового имени
                  final snapshot = await FirebaseDatabase.instance.ref().child('lobbies').get();
                  if (snapshot.value != null && snapshot.value is Map) {
                    final lobbies = snapshot.value as Map;
                    if (lobbies.values.any((l) => 
                        l is Map && 
                        l['name'] == newNameController.text && 
                        l['name'] != widget.lobby.name)) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Лобби с таким названием уже существует'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка при проверке имени: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }

              final updatedLobby = Lobby(
                name: newNameController.text.isNotEmpty 
                    ? newNameController.text 
                    : widget.lobby.name,
                password: newPasswordController.text.isNotEmpty
                    ? newPasswordController.text
                    : widget.lobby.password,
                accessLevel: selectedAccess,
                creatorId: widget.lobby.creatorId,
                creatorName: widget.lobby.creatorName,
                content: widget.lobby.content,
              );

              final lobbiesRef = FirebaseDatabase.instance.ref().child('lobbies');
              final snapshot = await lobbiesRef.get();
              String? lobbyKey;
              if (snapshot.value != null && snapshot.value is Map) {
                final lobbies = snapshot.value as Map;
                lobbies.forEach((key, value) {
                  if (value['name'] == widget.lobby.name) {
                    lobbyKey = key;
                  }
                });
              }

              if (lobbyKey != null) {
                await lobbiesRef.child(lobbyKey!).update(updatedLobby.toJson());
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Настройки лобби обновлены'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> document, ThemeData theme) {
    String fileName = document['filename'] ?? 'Без имени';
    try {
      if (fileName.contains('%')) {
        fileName = Uri.decodeComponent(fileName);
      }
      fileName = fileName.replaceAll(RegExp(r'[^\x20-\x7E\u0400-\u04FF]'), '_');
    } catch (e) {
      print('Ошибка обработки имени файла: $e');
      fileName = 'Документ без имени';
    }

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: _selectedDocuments.contains(document['id'])
            ? theme.colorScheme.primary.withOpacity(0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _isMultiSelectMode
              ? () {
                  setState(() {
                    if (_selectedDocuments.contains(document['id'])) {
                      _selectedDocuments.remove(document['id']);
                      if (_selectedDocuments.isEmpty) {
                        _isMultiSelectMode = false;
                      }
                    } else {
                      _selectedDocuments.add(document['id']);
                    }
                  });
                }
              : () => _openPdf(document['file']),
          onLongPress: () {
            setState(() {
              _isMultiSelectMode = true;
              _selectedDocuments.add(document['id']);
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (_isMultiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      _selectedDocuments.contains(document['id'])
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Загрузил: ${document['uploader']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isMultiSelectMode)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.download_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        onPressed: () => _downloadDocument(document['file']),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                      if (widget.lobby.accessLevel == AccessLevel.full)
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red[400],
                            size: 20,
                          ),
                          onPressed: () => _deleteDocument(document['id']),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentCardForLobby(Map<String, dynamic> document, ThemeData theme) {
    String fileName = document['filename'] ?? 'Без имени';
    try {
      if (fileName.contains('%')) {
        fileName = Uri.decodeComponent(fileName);
      }
      fileName = fileName.replaceAll(RegExp(r'[^\x20-\x7E\u0400-\u04FF]'), '_');
    } catch (e) {
      print('Ошибка обработки имени файла: $e');
      fileName = 'Документ без имени';
    }

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: _selectedDocuments.contains(document['id'])
            ? theme.colorScheme.primary.withOpacity(0.1)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _isMultiSelectMode
              ? () {
                  setState(() {
                    if (_selectedDocuments.contains(document['id'])) {
                      _selectedDocuments.remove(document['id']);
                      if (_selectedDocuments.isEmpty) {
                        _isMultiSelectMode = false;
                      }
                    } else {
                      _selectedDocuments.add(document['id']);
                    }
                  });
                }
              : () => _openPdf(document['file']),
          onLongPress: () {
            setState(() {
              _isMultiSelectMode = true;
              _selectedDocuments.add(document['id']);
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (_isMultiSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      _selectedDocuments.contains(document['id'])
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Загрузил: ${document['uploader']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isMultiSelectMode)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.download_outlined,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        onPressed: () => _downloadDocument(document['file']),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                      if (widget.lobby.accessLevel == AccessLevel.full)
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red[400],
                            size: 20,
                          ),
                          onPressed: () => _deleteDocument(document['id']),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDocument(int documentId) async {
    if (widget.currentUser == null || widget.lobby.creatorId != widget.currentUser!.uid) {
      if (widget.lobby.accessLevel == AccessLevel.read) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('У вас нет прав для удаления файлов'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: const Text('Вы уверены, что хотите удалить этот документ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      setState(() => _isLoading = true);
      try {
        await _documentService.deleteDocument(documentId);
        
        final docs = await _documentService.getDocumentsForLobby(widget.lobby.name);
        if (mounted) {
          setState(() {
            _documents = docs.where((doc) => 
              doc['lobby_name'] == widget.lobby.name
            ).toList();
            _isLoading = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Документ успешно удален'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка при удалении документа: $e'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return WillPopScope(
      onWillPop: () async {
        if (_isMultiSelectMode) {
          setState(() {
            _isMultiSelectMode = false;
            _selectedDocuments.clear();
          });
          return false;
        }
        Navigator.of(context).pop(true);
        return false;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.folder_shared, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.lobby.name,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${widget.lobby.creatorName}',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('last_route', '/community');
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CommunityPage(),
                      settings: const RouteSettings(name: '/community'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.forum, size: 28),
              tooltip: 'Сообщество',
            ),
            IconButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('last_route', '/news');
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NewsPage(),
                      settings: const RouteSettings(name: '/news'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.newspaper, size: 28),
              tooltip: 'Новости',
            ),
            IconButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('last_route', '/account');
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AccountSettingsPage(),
                      settings: const RouteSettings(name: '/account'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.person),
              tooltip: 'Настройки аккаунта',
            ),
            if (widget.currentUser?.uid == widget.lobby.creatorId)
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _showLobbySettings,
                tooltip: 'Настройки лобби',
              ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withOpacity(0.1),
                Colors.white,
                theme.colorScheme.secondary.withOpacity(0.05),
              ],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 100, 16, 0),
                        child: _buildLobbyHeader(theme),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildDocumentStats(theme),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: _buildDocumentCard(_documents[index], theme),
                        ),
                        childCount: _documents.length,
                      ),
                    ),
                  ],
                ),
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isMultiSelectMode && _selectedDocuments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FloatingActionButton.extended(
                  onPressed: _deleteSelectedDocuments,
                  backgroundColor: Colors.red,
                  label: Text('Удалить (${_selectedDocuments.length})'),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            if (widget.lobby.accessLevel == AccessLevel.full)
              FloatingActionButton.extended(
                onPressed: _pickPdfFile,
                elevation: 4,
                backgroundColor: theme.colorScheme.primary,
                label: Row(
                  children: [
                    const Icon(Icons.upload_file, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Загрузить PDF',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  widget.lobby.accessLevel == AccessLevel.read
                      ? Icons.visibility
                      : Icons.edit,
                  color: theme.colorScheme.primary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.lobby.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.lobby.creatorName}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: widget.lobby.accessLevel == AccessLevel.read
                  ? Colors.blue.withOpacity(0.1)
                  : Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.lobby.accessLevel == AccessLevel.read
                  ? 'Режим чтения'
                  : 'Полный доступ',
              style: TextStyle(
                color: widget.lobby.accessLevel == AccessLevel.read
                    ? Colors.blue
                    : Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentStats(ThemeData theme) {
    return Row(
      children: [
        _buildCompactStatCard(
          icon: Icons.description_outlined,
          value: _documents.length.toString(),
          label: 'Всего документов',
          theme: theme,
        ),
        const SizedBox(width: 8),
        _buildCompactStatCard(
          icon: Icons.update_outlined,
          value: _documents.isNotEmpty
              ? DateFormat('dd.MM.yy').format(
                  DateTime.parse(_documents.last['upload_date']).toLocal())
              : '-',
          label: 'Последнее обновление',
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildCompactStatCard({
    required IconData icon,
    required String value,
    required String label,
    required ThemeData theme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPdf(String fileUrl) async {
    if (kIsWeb) {
      html.window.open(fileUrl, '_blank');
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfViewerPage(filePath: fileUrl),
        ),
      );
    }
  }
}

// Define PdfViewerPage
class PdfViewerPage extends StatefulWidget {
  final String filePath;
  
  const PdfViewerPage({required this.filePath, super.key});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Просмотр PDF'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => Share.shareFiles([widget.filePath]),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              final status = await Permission.storage.request();
              if (status.isGranted) {
                final downloadDir = await getExternalStorageDirectory();
                final fileName = widget.filePath.split('/').last;
                final targetPath = '${downloadDir!.path}/$fileName';
                
                await File(widget.filePath).copy(targetPath);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Файл сохранен')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SfPdfViewer.file(File(widget.filePath)),
    );
  }
}