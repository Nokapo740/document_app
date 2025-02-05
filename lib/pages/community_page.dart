import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../models/message.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui';
import 'package:share/share.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import 'package:flutter/services.dart';

class CommunityPage extends StatefulWidget {
  final String? initialMessageId;
  
  const CommunityPage({
    this.initialMessageId,
    super.key,
  });

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _messages = [];
  PlatformFile? _selectedImage;
  User? _currentUser;
  late DatabaseReference _messagesRef;
  StreamSubscription? _messagesSubscription;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedDateFilter = 'все'; // 'все', 'сегодня', 'неделя', 'месяц'
  Message? _replyToMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _initializeFirebase();
    
    // Добавляем прокрутку к сообщению, если есть ID
    if (widget.initialMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToMessage(widget.initialMessageId!);
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _currentUser = user;
    });
  }

  void _initializeFirebase() {
    _messagesRef = FirebaseDatabase.instance.ref().child('messages');
    
    // Обновляем подписку на сообщения
    _messagesSubscription = _messagesRef
        .orderByChild('timestamp')
        .onChildAdded
        .listen((event) {
      if (event.snapshot.value != null) {
        final messageData = Map<String, dynamic>.from(event.snapshot.value as Map);
        messageData['id'] = event.snapshot.key;
        
        setState(() {
          final message = Message.fromJson(messageData);
          if (!_messages.any((m) => m.id == message.id)) {
            _messages.add(message);
            _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          }
        });
      }
    });

    // Добавляем подписку на обновления сообщений
    _messagesRef.onChildChanged.listen((event) {
      if (event.snapshot.value != null) {
        final messageData = Map<String, dynamic>.from(event.snapshot.value as Map);
        messageData['id'] = event.snapshot.key;
        
        setState(() {
          final updatedMessage = Message.fromJson(messageData);
          final index = _messages.indexWhere((m) => m.id == updatedMessage.id);
          if (index != -1) {
            _messages[index] = updatedMessage;
          }
        });
      }
    });

    // Добавляем подписку на удаление сообщений
    _messagesRef.onChildRemoved.listen((event) {
      setState(() {
        _messages.removeWhere((m) => m.id == event.snapshot.key);
      });
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null) {
      setState(() {
        _selectedImage = result.files.first;
      });
    }
  }

  void _setReplyMessage(Message message) {
    setState(() {
      _replyToMessage = message;
    });
  }

  Future<void> _sendMessage() async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Необходимо войти в систему')),
      );
      return;
    }

    final messageText = _messageController.text.trim();
    if (messageText.isEmpty && _selectedImage == null) {
      return;
    }

    try {
      String? imageUrl;
      if (_selectedImage != null) {
        final bytes = _selectedImage!.bytes;
        if (bytes != null) {
          final base64Image = base64Encode(bytes);
          imageUrl = 'data:image/${_selectedImage!.extension};base64,$base64Image';
        }
      }

      final newMessage = Message(
        id: const Uuid().v4(),
        text: messageText,
        imageUrl: imageUrl,
        authorId: _currentUser!.uid,
        authorName: _currentUser!.email ?? 'Аноним',
        timestamp: DateTime.now(),
        replyToId: _replyToMessage?.id,
        replyToText: _replyToMessage?.text,
      );

      // Очищаем поля ввода и ответ
      _messageController.clear();
      setState(() {
        _selectedImage = null;
        _replyToMessage = null;
      });

      // Отправляем сообщение без установки состояния загрузки
      await _messagesRef.child(newMessage.id).set(newMessage.toJson());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки сообщения: $e')),
      );
    }
  }

  // Обновляем виджет отображения изображения
  Widget _buildImage(String imageUrl) {
    if (imageUrl.startsWith('data:image')) {
      // Для base64 изображений
      final data = imageUrl.split(',')[1];
      return Image.memory(
        base64Decode(data),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.error, color: Colors.red),
          );
        },
      );
    } else {
      // Для обычных URL изображений
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.error, color: Colors.red),
          );
        },
      );
    }
  }

  List<Message> _getFilteredMessages() {
    List<Message> filteredMessages = List.from(_messages);
    
    // Фильтрация по дате
    final now = DateTime.now();
    switch (_selectedDateFilter) {
      case 'сегодня':
        filteredMessages = filteredMessages.where((message) {
          return message.timestamp.year == now.year &&
                 message.timestamp.month == now.month &&
                 message.timestamp.day == now.day;
        }).toList();
        break;
      case 'неделя':
        final weekAgo = now.subtract(const Duration(days: 7));
        filteredMessages = filteredMessages.where((message) {
          return message.timestamp.isAfter(weekAgo);
        }).toList();
        break;
      case 'месяц':
        final monthAgo = DateTime(now.year, now.month - 1, now.day);
        filteredMessages = filteredMessages.where((message) {
          return message.timestamp.isAfter(monthAgo);
        }).toList();
        break;
    }

    // Фильтрация по поисковому запросу
    if (_searchQuery.isNotEmpty) {
      filteredMessages = filteredMessages.where((message) {
        return message.text.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               message.authorName.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    return filteredMessages;
  }

  void _shareMessage(Message message) {
    if (kIsWeb) {
      // Создаем URL с ID сообщения
      final messageUrl = '${html.window.location.href}?message=${message.id}';
      
      showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.telegram),
                title: const Text('Telegram'),
                onTap: () {
                  final url = 'https://t.me/share/url?url=$messageUrl';
                  html.window.open(url, '_blank');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.whatshot),
                title: const Text('WhatsApp'),
                onTap: () {
                  final url = 'https://wa.me/?text=$messageUrl';
                  html.window.open(url, '_blank');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('Копировать ссылку'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: messageUrl)).then((_) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ссылка скопирована в буфер обмена')),
                    );
                  });
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final messageUrl = '${html.window.location.href}?message=${message.id}';
      Share.share(messageUrl);
    }
  }

  void _scrollToMessage(String messageId) {
    final index = _messages.indexWhere((msg) => msg.id == messageId);
    if (index != -1 && _scrollController.hasClients) {
      _scrollController.animateTo(
        index * 100.0, // Примерная высота сообщения
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Добавляем методы для лайков и дизлайков
  Future<void> _toggleLike(Message message) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Необходимо войти в систему')),
      );
      return;
    }
    
    final userId = _currentUser!.uid;
    final messageRef = _messagesRef.child(message.id);
    
    if (message.likes[userId] == true) {
      // Убираем лайк
      await messageRef.child('likes/$userId').remove();
    } else {
      // Ставим лайк и убираем дизлайк если есть
      await messageRef.child('likes/$userId').set(true);
      await messageRef.child('dislikes/$userId').remove();
    }
  }

  Future<void> _toggleDislike(Message message) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Необходимо войти в систему')),
      );
      return;
    }
    
    final userId = _currentUser!.uid;
    final messageRef = _messagesRef.child(message.id);
    
    if (message.dislikes[userId] == true) {
      // Убираем дизлайк
      await messageRef.child('dislikes/$userId').remove();
    } else {
      // Ставим дизлайк и убираем лайк если есть
      await messageRef.child('dislikes/$userId').set(true);
      await messageRef.child('likes/$userId').remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredMessages = _getFilteredMessages();
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withOpacity(0.3),
                    theme.colorScheme.secondary.withOpacity(0.2),
                  ],
                ),
              ),
            ),
          ),
        ),
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.forum_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Сообщество',
                  style: TextStyle(
                    color: Color(0xFF2C3E50),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Общение и обсуждения',
                  style: TextStyle(
                    color: const Color(0xFF2C3E50).withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              onPressed: () {
                // Показать информацию о странице
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('О странице'),
                    content: const Text('Это страница сообщества, где пользователи могут общаться и обмениваться сообщениями.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                );
              },
            ),
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
        child: Column(
          children: [
            const SizedBox(height: kToolbarHeight + 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Поиск сообщений...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in ['все', 'сегодня', 'неделя', 'месяц'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(filter),
                              selected: _selectedDateFilter == filter,
                              onSelected: (selected) {
                                setState(() {
                                  _selectedDateFilter = selected ? filter : 'все';
                                });
                              },
                              backgroundColor: Colors.white,
                              selectedColor: theme.colorScheme.primary.withOpacity(0.2),
                              checkmarkColor: theme.colorScheme.primary,
                              labelStyle: TextStyle(
                                color: _selectedDateFilter == filter
                                    ? theme.colorScheme.primary
                                    : Colors.black87,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredMessages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Сообщения не найдены',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filteredMessages.length,
                      itemBuilder: (context, index) {
                        final message = filteredMessages[index];
                        final isCurrentUser = message.authorId == _currentUser?.uid;

                        return Align(
                          alignment: isCurrentUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (context) => Container(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.reply),
                                        title: const Text('Ответить'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _setReplyMessage(message);
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.share),
                                        title: const Text('Поделиться'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _shareMessage(message);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              margin: EdgeInsets.only(
                                bottom: 16,
                                left: isCurrentUser ? 50 : 0,
                                right: isCurrentUser ? 0 : 50,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrentUser
                                    ? theme.colorScheme.primary.withOpacity(0.9)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: isCurrentUser
                                                  ? Colors.white.withOpacity(0.2)
                                                  : theme.colorScheme.primary.withOpacity(0.1),
                                              child: Text(
                                                message.authorName[0].toUpperCase(),
                                                style: TextStyle(
                                                  color: isCurrentUser
                                                      ? Colors.white
                                                      : theme.colorScheme.primary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  message.authorName,
                                                  style: TextStyle(
                                                    color: isCurrentUser
                                                        ? Colors.white.withOpacity(0.9)
                                                        : Colors.black87,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Text(
                                                  DateFormat('HH:mm').format(message.timestamp),
                                                  style: TextStyle(
                                                    color: isCurrentUser
                                                        ? Colors.white.withOpacity(0.6)
                                                        : Colors.black54,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (message.imageUrl != null) ...[
                                          const SizedBox(height: 12),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              constraints: BoxConstraints(
                                                maxHeight: MediaQuery.of(context).size.height * 0.3,
                                                maxWidth: MediaQuery.of(context).size.width * 0.6,
                                              ),
                                              child: _buildImage(message.imageUrl!),
                                            ),
                                          ),
                                        ],
                                        if (message.replyToText != null) ...[
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            margin: const EdgeInsets.only(bottom: 8),
                                            decoration: BoxDecoration(
                                              color: isCurrentUser 
                                                  ? Colors.white.withOpacity(0.2)
                                                  : theme.colorScheme.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Ответ на: ${message.replyToText}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isCurrentUser ? Colors.white70 : Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (message.text.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            message.text,
                                            style: TextStyle(
                                              color: isCurrentUser
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                message.likes[_currentUser?.uid] == true 
                                                    ? Icons.thumb_up 
                                                    : Icons.thumb_up_outlined,
                                                size: 20,
                                                color: message.likes[_currentUser?.uid] == true
                                                    ? Colors.green
                                                    : (isCurrentUser ? Colors.white : Colors.grey[600]),
                                              ),
                                              onPressed: () => _toggleLike(message),
                                            ),
                                            Text(
                                              message.likes.length.toString(),
                                              style: TextStyle(
                                                color: message.likes[_currentUser?.uid] == true
                                                    ? Colors.green
                                                    : (isCurrentUser ? Colors.white : Colors.grey[600]),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: Icon(
                                                message.dislikes[_currentUser?.uid] == true 
                                                    ? Icons.thumb_down 
                                                    : Icons.thumb_down_outlined,
                                                size: 20,
                                                color: message.dislikes[_currentUser?.uid] == true
                                                    ? Colors.red
                                                    : (isCurrentUser ? Colors.white : Colors.grey[600]),
                                              ),
                                              onPressed: () => _toggleDislike(message),
                                            ),
                                            Text(
                                              message.dislikes.length.toString(),
                                              style: TextStyle(
                                                color: message.dislikes[_currentUser?.uid] == true
                                                    ? Colors.red
                                                    : (isCurrentUser ? Colors.white : Colors.grey[600]),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (_selectedImage != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.image,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedImage!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedImage = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  if (_replyToMessage != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.reply,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ответ: ${_replyToMessage!.text}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _replyToMessage = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: Icon(
                              Icons.image,
                              color: theme.colorScheme.primary,
                            ),
                            onPressed: _pickImage,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Введите сообщение...',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                            ),
                            maxLines: null,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.send,
                              color: Colors.white,
                            ),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
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

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}