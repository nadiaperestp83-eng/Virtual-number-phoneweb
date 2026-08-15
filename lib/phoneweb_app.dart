import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sip_ua/sip_ua.dart';

import 'src/account/webrtc_account.dart';
import 'src/audio/keypad_tone_player.dart';
import 'src/chat/presentation/conversations_list_view.dart';
import 'src/contacts/native_contacts_repository.dart';
import 'src/contacts/phone_contact.dart';
import 'src/storage/standalone_phoneweb_store.dart';
import 'src/version/runtime_version.dart';
import 'src/voip/phoneweb_voip_controller.dart';

const double _desktopSideFooterHeight = 260;

class PhoneWebApp extends StatelessWidget {
  const PhoneWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MNSCloud PhoneWeb',
      debugShowCheckedModeBanner: false,
      theme: _phoneWebTheme(Brightness.light),
      darkTheme: _phoneWebTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const PhoneWebHomePage(),
    );
  }
}

ThemeData _phoneWebTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F766E),
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF151515)
        : const Color(0xFFF7F8F5),
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: dark ? const Color(0xFF252525) : Colors.white,
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1F1F1F) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
  );
}

class PhoneWebHomePage extends StatefulWidget {
  const PhoneWebHomePage({super.key});

  @override
  State<PhoneWebHomePage> createState() => _PhoneWebHomePageState();
}

class _PhoneWebHomePageState extends State<PhoneWebHomePage> {
  final List<WebRtcAccount> _accounts = [];
  final List<PhoneContact> _contacts = [];
  final List<PhoneCallHistoryEntry> _callHistory = [];
  final StandalonePhoneWebStore _store = StandalonePhoneWebStore();
  final NativeContactsRepository _contactsRepository =
      NativeContactsRepository();
  final KeypadTonePlayer _keypadTonePlayer = KeypadTonePlayer();
  late final PhoneWebVoipController _voip;
  String? _selectedAccountId;
  String _dialNumber = '';
  String _lastEvent = 'Ready';
  int _mobileTabIndex = 0;
  bool _contactsSyncing = false;
  String _contactsStatus = 'Agenda local';
  RuntimeVersionInfo _runtimeVersion = currentRuntimeVersionInfo();
  bool _standaloneDirty = false;
  bool _hadActiveCall = false;
  bool _trackedCallEstablished = false;
  bool _trackedCallIncoming = false;
  String _trackedCallRemote = '';
  String _trackedCallAccountName = '';
  String _trackedCallDiagnostic = '';
  DateTime? _trackedCallStartedAt;

  @override
  void initState() {
    super.initState();
    _voip = PhoneWebVoipController();
    _voip.addListener(_syncVoipState);
    _loadStandaloneState();
    _refreshRuntimeVersion();
  }

  @override
  void dispose() {
    _voip.removeListener(_syncVoipState);
    _voip.dispose();
    _keypadTonePlayer.dispose();
    super.dispose();
  }

  WebRtcAccount? get _selectedAccount {
    for (final account in _accounts) {
      if (account.id == _selectedAccountId) {
        return account;
      }
    }
    return _accounts.isEmpty ? null : _accounts.first;
  }

  Future<void> _refreshRuntimeVersion() async {
    final versionInfo = await loadRuntimeVersionInfo();
    if (!mounted) return;
    setState(() {
      _runtimeVersion = versionInfo;
    });
  }

  Future<void> _loadStandaloneState() async {
    final state = await _store.load();
    if (!mounted) return;
    if (_standaloneDirty) {
      return;
    }
    setState(() {
      _accounts
        ..clear()
        ..addAll(state.accounts.where((account) => account.id.isNotEmpty));
      _contacts
        ..clear()
        ..addAll(state.contacts.where((contact) => contact.id.isNotEmpty));
      _callHistory
        ..clear()
        ..addAll(
          state.callHistory.where((entry) => entry.id.isNotEmpty).take(250),
        );
      _selectedAccountId =
          state.selectedAccountId != null &&
              _accounts.any((account) => account.id == state.selectedAccountId)
          ? state.selectedAccountId
          : (_accounts.isEmpty ? null : _accounts.first.id);
      _contactsStatus = _contacts.isEmpty
          ? 'Agenda local'
          : '${_contacts.length} contato(s) local(is) salvo(s)';
    });

    final account = _selectedAccount;
    if (account != null && account.enabled && account.autoRegister) {
      await _voip.register(account);
    }
  }

  Future<void> _saveStandaloneAccounts() {
    _standaloneDirty = true;
    return _store.saveAccounts(
      _accounts,
      selectedAccountId: _selectedAccountId,
    );
  }

  Future<void> _saveStandaloneContacts() {
    _standaloneDirty = true;
    return _store.saveContacts(_contacts);
  }

  Future<void> _saveStandaloneHistory() {
    _standaloneDirty = true;
    return _store.saveCallHistory(_callHistory);
  }

  Future<void> _openAccountDialog({WebRtcAccount? account}) async {
    final result = await showDialog<WebRtcAccount>(
      context: context,
      builder: (context) => AccountDialog(account: account),
    );

    if (result == null) {
      return;
    }

    setState(() {
      final index = _accounts.indexWhere((item) => item.id == result.id);
      if (index >= 0) {
        _accounts[index] = result;
        _lastEvent = '${result.name} updated';
      } else {
        _accounts.add(result);
        _selectedAccountId = result.id;
        _lastEvent = '${result.name} added';
      }
    });
    await _saveStandaloneAccounts();

    if (result.autoRegister && result.enabled) {
      await _voip.register(result);
    }
  }

  Future<void> _removeAccount(WebRtcAccount account) async {
    setState(() {
      _accounts.removeWhere((item) => item.id == account.id);
      if (_selectedAccountId == account.id) {
        _selectedAccountId = _accounts.isEmpty ? null : _accounts.first.id;
      }
      _lastEvent = '${account.name} removed';
    });
    await _saveStandaloneAccounts();
  }

  Future<void> _toggleRegistration(WebRtcAccount account) async {
    if (account.status == RegistrationStatus.registered ||
        account.status == RegistrationStatus.registering) {
      await _voip.unregister();
      return;
    }

    await _voip.register(account);
  }

  void _syncVoipState() {
    setState(() {
      _trackCallState();
      final activeAccount = _voip.account;
      if (activeAccount != null) {
        final index = _accounts.indexWhere(
          (item) => item.id == activeAccount.id,
        );
        if (index >= 0) {
          _accounts[index] = _accounts[index].copyWith(
            status: _voip.registrationStatus,
            diagnostic: _voip.registrationDiagnostic,
          );
        }
      }
      _lastEvent = _voip.lastEvent;
    });
    _saveStandaloneAccounts();
    _saveStandaloneHistory();
  }

  void _trackCallState() {
    if (_voip.hasActiveCall) {
      if (!_hadActiveCall) {
        _trackedCallStartedAt = DateTime.now();
        _trackedCallRemote = _voip.remoteIdentity;
        _trackedCallIncoming = _voip.activeCallDirection == Direction.incoming;
        _trackedCallAccountName = _selectedAccount?.name ?? '';
        _trackedCallDiagnostic = '';
        _trackedCallEstablished = false;
      }
      if (_voip.lastCallDiagnostic.isNotEmpty) {
        _trackedCallDiagnostic = _voip.lastCallDiagnostic;
      }
      if (_voip.hasEstablishedCall) {
        _trackedCallEstablished = true;
      }
      _hadActiveCall = true;
      return;
    }

    if (!_hadActiveCall) return;

    final startedAt = _trackedCallStartedAt ?? DateTime.now();
    final duration = DateTime.now().difference(startedAt).inSeconds;
    final status = _trackedCallEstablished
        ? PhoneCallStatus.completed
        : (_trackedCallIncoming
              ? PhoneCallStatus.missed
              : PhoneCallStatus.failed);
    _callHistory.insert(
      0,
      PhoneCallHistoryEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        remoteIdentity: _trackedCallRemote.isEmpty
            ? 'Unknown'
            : _trackedCallRemote,
        direction: _trackedCallIncoming
            ? PhoneCallDirection.incoming
            : PhoneCallDirection.outgoing,
        status: status,
        startedAt: startedAt,
        durationSeconds: duration < 0 ? 0 : duration,
        accountName: _trackedCallAccountName,
        diagnostic: _trackedCallDiagnostic,
      ),
    );
    if (_callHistory.length > 250) {
      _callHistory.removeRange(250, _callHistory.length);
    }
    _hadActiveCall = false;
    _trackedCallEstablished = false;
    _trackedCallIncoming = false;
    _trackedCallRemote = '';
    _trackedCallAccountName = '';
    _trackedCallDiagnostic = '';
    _trackedCallStartedAt = null;
  }

  void _appendDial(String value) {
    _keypadTonePlayer.play(value);

    if (_voip.hasActiveCall) {
      _voip.sendDtmf(value);
    }

    setState(() {
      _dialNumber = '$_dialNumber$value';
    });
  }

  void _backspaceDial() {
    if (_dialNumber.isEmpty) {
      return;
    }

    setState(() {
      _dialNumber = _dialNumber.substring(0, _dialNumber.length - 1);
    });
  }

  void _clearDial() {
    setState(() {
      _dialNumber = '';
    });
  }

  Future<void> _makeCall() async {
    final account = _selectedAccount;
    if (account == null || _dialNumber.trim().isEmpty) {
      return;
    }

    await _voip.makeCall(_dialNumber);
  }

  Future<void> _openContactDialog({PhoneContact? contact}) async {
    final result = await showDialog<PhoneContact>(
      context: context,
      builder: (context) => ContactDialog(contact: contact),
    );
    if (result == null) return;

    setState(() {
      final index = _contacts.indexWhere((item) => item.id == result.id);
      if (index >= 0) {
        _contacts[index] = result;
      } else {
        _contacts.add(result);
      }
      _lastEvent = '${result.name} saved';
    });
    await _saveStandaloneContacts();
  }

  void _dialContact(PhoneContact contact) {
    setState(() {
      _dialNumber = contact.number;
      _mobileTabIndex = 0;
    });
  }

  void _dialHistoryEntry(PhoneCallHistoryEntry entry) {
    setState(() {
      _dialNumber = _dialableHistoryIdentity(entry.remoteIdentity);
      _mobileTabIndex = 0;
    });
  }

  Future<void> _syncNativeContacts() async {
    if (_contactsSyncing) return;

    setState(() {
      _contactsSyncing = true;
      _contactsStatus = 'Sincronizando agenda...';
    });

    final result = await _contactsRepository.loadContacts();
    if (!mounted) return;

    setState(() {
      _contactsSyncing = false;
      _contactsStatus = result.message;
      _lastEvent = result.message;

      final shouldSaveContacts = result.status == NativeContactsStatus.loaded;
      if (shouldSaveContacts) {
        final manualContacts = _contacts
            .where((contact) => contact.source == PhoneContactSource.manual)
            .toList();
        _contacts
          ..clear()
          ..addAll(manualContacts)
          ..addAll(result.contacts);
      }
    });
    if (result.status == NativeContactsStatus.loaded) {
      await _saveStandaloneContacts();
    }
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 640) {
      return MobilePhoneShell(
        accounts: _accounts,
        contacts: _contacts,
        callHistory: _callHistory,
        selectedAccount: _selectedAccount,
        dialNumber: _dialNumber,
        voip: _voip,
        currentIndex: _mobileTabIndex,
        lastEvent: _lastEvent,
        runtimeVersion: _runtimeVersion,
        onTabChanged: (index) => setState(() => _mobileTabIndex = index),
        onAppend: _appendDial,
        onBackspace: _backspaceDial,
        onClear: _clearDial,
        onCall: _makeCall,
        onAddAccount: () => _openAccountDialog(),
        onEditAccount: (account) => _openAccountDialog(account: account),
        onRemoveAccount: _removeAccount,
        onSelectAccount: (account) {
          setState(() {
            _selectedAccountId = account.id;
          });
          _saveStandaloneAccounts();
        },
        onToggleRegistration: _toggleRegistration,
        onAddContact: () => _openContactDialog(),
        onEditContact: (contact) => _openContactDialog(contact: contact),
        onDialContact: _dialContact,
        onDialHistoryEntry: _dialHistoryEntry,
        onSyncContacts: _syncNativeContacts,
        contactsSyncing: _contactsSyncing,
        contactsStatus: _contactsStatus,
      );
    }

    final compact = width < 920;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppHeader(
                accountCount: _accounts.length,
                runtimeVersion: _runtimeVersion,
                onRefreshVersion: _refreshRuntimeVersion,
                onAddAccount: () => _openAccountDialog(),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: compact
                    ? ListView(children: _buildPanels(compact: true))
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 360,
                            child: Column(
                              children: [
                                Expanded(
                                  child: AccountPanel(
                                    accounts: _accounts,
                                    selectedAccountId: _selectedAccount?.id,
                                    onAddAccount: () => _openAccountDialog(),
                                    onEditAccount: (account) =>
                                        _openAccountDialog(account: account),
                                    onRemoveAccount: _removeAccount,
                                    onSelectAccount: (account) {
                                      setState(() {
                                        _selectedAccountId = account.id;
                                      });
                                      _saveStandaloneAccounts();
                                    },
                                    onToggleRegistration: _toggleRegistration,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: _desktopSideFooterHeight,
                                  child: ContactsSummaryPanel(
                                    contacts: _contacts,
                                    contactsSyncing: _contactsSyncing,
                                    contactsStatus: _contactsStatus,
                                    onAddContact: () => _openContactDialog(),
                                    onSyncContacts: _syncNativeContacts,
                                    onEditContact: (contact) =>
                                        _openContactDialog(contact: contact),
                                    onDialContact: _dialContact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: WorkspacePanels(
                              selectedAccount: _selectedAccount,
                              dialNumber: _dialNumber,
                              voip: _voip,
                              onAppend: _appendDial,
                              onBackspace: _backspaceDial,
                              onClear: _clearDial,
                              onCall: _makeCall,
                              callHistory: _callHistory,
                              onDialHistoryEntry: _dialHistoryEntry,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPanels({required bool compact}) {
    return [
      AccountPanel(
        accounts: _accounts,
        selectedAccountId: _selectedAccount?.id,
        onAddAccount: () => _openAccountDialog(),
        onEditAccount: (account) => _openAccountDialog(account: account),
        onRemoveAccount: _removeAccount,
        onSelectAccount: (account) {
          setState(() {
            _selectedAccountId = account.id;
          });
          _saveStandaloneAccounts();
        },
        onToggleRegistration: _toggleRegistration,
      ),
      const SizedBox(height: 16),
      ContactsSummaryPanel(
        contacts: _contacts,
        contactsSyncing: _contactsSyncing,
        contactsStatus: _contactsStatus,
        onAddContact: () => _openContactDialog(),
        onSyncContacts: _syncNativeContacts,
        onEditContact: (contact) => _openContactDialog(contact: contact),
        onDialContact: _dialContact,
      ),
      const SizedBox(height: 16),
      DialerPanel(
        selectedAccount: _selectedAccount,
        dialNumber: _dialNumber,
        voip: _voip,
        onAppend: _appendDial,
        onBackspace: _backspaceDial,
        onClear: _clearDial,
        onCall: _makeCall,
      ),
      const SizedBox(height: 16),
      CallHistoryPanel(entries: _callHistory, onDial: _dialHistoryEntry),
      const SizedBox(height: 16),
      const MessagesPanel(),
    ];
  }
}

class WorkspacePanels extends StatelessWidget {
  const WorkspacePanels({
    required this.selectedAccount,
    required this.dialNumber,
    required this.voip,
    required this.onAppend,
    required this.onBackspace,
    required this.onClear,
    required this.onCall,
    required this.callHistory,
    required this.onDialHistoryEntry,
    super.key,
  });

  final WebRtcAccount? selectedAccount;
  final String dialNumber;
  final PhoneWebVoipController voip;
  final List<PhoneCallHistoryEntry> callHistory;
  final ValueChanged<String> onAppend;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;
  final ValueChanged<PhoneCallHistoryEntry> onDialHistoryEntry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1080) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DialerPanel(
                  selectedAccount: selectedAccount,
                  dialNumber: dialNumber,
                  voip: voip,
                  onAppend: onAppend,
                  onBackspace: onBackspace,
                  onClear: onClear,
                  onCall: onCall,
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 360,
                child: Column(
                  children: [
                    Expanded(
                      child: CallHistoryPanel(
                        entries: callHistory,
                        onDial: onDialHistoryEntry,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: _desktopSideFooterHeight,
                      child: MessagesPanel(),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return ListView(
          children: [
            DialerPanel(
              selectedAccount: selectedAccount,
              dialNumber: dialNumber,
              voip: voip,
              onAppend: onAppend,
              onBackspace: onBackspace,
              onClear: onClear,
              onCall: onCall,
            ),
            const SizedBox(height: 16),
            CallHistoryPanel(entries: callHistory, onDial: onDialHistoryEntry),
            const SizedBox(height: 16),
            MessagesPanel(),
          ],
        );
      },
    );
  }
}

class MobilePhoneShell extends StatelessWidget {
  const MobilePhoneShell({
    required this.accounts,
    required this.contacts,
    required this.callHistory,
    required this.selectedAccount,
    required this.dialNumber,
    required this.voip,
    required this.currentIndex,
    required this.lastEvent,
    required this.runtimeVersion,
    required this.onTabChanged,
    required this.onAppend,
    required this.onBackspace,
    required this.onClear,
    required this.onCall,
    required this.onAddAccount,
    required this.onEditAccount,
    required this.onRemoveAccount,
    required this.onSelectAccount,
    required this.onToggleRegistration,
    required this.onAddContact,
    required this.onEditContact,
    required this.onDialContact,
    required this.onDialHistoryEntry,
    required this.onSyncContacts,
    required this.contactsSyncing,
    required this.contactsStatus,
    super.key,
  });

  final List<WebRtcAccount> accounts;
  final List<PhoneContact> contacts;
  final List<PhoneCallHistoryEntry> callHistory;
  final WebRtcAccount? selectedAccount;
  final String dialNumber;
  final PhoneWebVoipController voip;
  final int currentIndex;
  final String lastEvent;
  final RuntimeVersionInfo runtimeVersion;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<String> onAppend;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;
  final VoidCallback onAddAccount;
  final ValueChanged<WebRtcAccount> onEditAccount;
  final ValueChanged<WebRtcAccount> onRemoveAccount;
  final ValueChanged<WebRtcAccount> onSelectAccount;
  final ValueChanged<WebRtcAccount> onToggleRegistration;
  final VoidCallback onAddContact;
  final ValueChanged<PhoneContact> onEditContact;
  final ValueChanged<PhoneContact> onDialContact;
  final ValueChanged<PhoneCallHistoryEntry> onDialHistoryEntry;
  final VoidCallback onSyncContacts;
  final bool contactsSyncing;
  final String contactsStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primary;
    final unselectedColor = colorScheme.onSurfaceVariant;
    final pages = [
      MobileDialerView(
        dialNumber: dialNumber,
        voip: voip,
        selectedAccount: selectedAccount,
        onAppend: onAppend,
        onBackspace: onBackspace,
        onClear: onClear,
        onCall: onCall,
      ),
      MobileContactsView(
        contacts: contacts,
        onAddContact: onAddContact,
        onEditContact: onEditContact,
        onDialContact: onDialContact,
        onSyncContacts: onSyncContacts,
        contactsSyncing: contactsSyncing,
        contactsStatus: contactsStatus,
      ),
      MobileHistoryView(entries: callHistory, onDial: onDialHistoryEntry),
      MobileMessagesView(),
    ];

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopBar(
              account: selectedAccount,
              accountCount: accounts.length,
              runtimeVersion: runtimeVersion,
              onAccounts: () => _showAccountsSheet(context),
            ),
            Expanded(child: pages[currentIndex]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: states.contains(WidgetState.selected)
                  ? selectedColor
                  : unselectedColor,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? selectedColor
                  : unselectedColor,
            ),
          ),
        ),
        child: NavigationBar(
          height: 78,
          backgroundColor: colorScheme.surfaceContainerHighest,
          selectedIndex: currentIndex,
          onDestinationSelected: onTabChanged,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dialpad), label: 'Telefone'),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              label: 'Contatos',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Historico',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Mensagens',
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return AccountsBottomSheet(
          accounts: accounts,
          selectedAccount: selectedAccount,
          onAddAccount: () {
            Navigator.pop(context);
            onAddAccount();
          },
          onEditAccount: (account) {
            Navigator.pop(context);
            onEditAccount(account);
          },
          onSelectAccount: (account) {
            onSelectAccount(account);
            Navigator.pop(context);
          },
          onToggleRegistration: onToggleRegistration,
        );
      },
    );
  }
}

class AccountsBottomSheet extends StatefulWidget {
  const AccountsBottomSheet({
    required this.accounts,
    required this.selectedAccount,
    required this.onAddAccount,
    required this.onEditAccount,
    required this.onSelectAccount,
    required this.onToggleRegistration,
    super.key,
  });

  final List<WebRtcAccount> accounts;
  final WebRtcAccount? selectedAccount;
  final VoidCallback onAddAccount;
  final ValueChanged<WebRtcAccount> onEditAccount;
  final ValueChanged<WebRtcAccount> onSelectAccount;
  final ValueChanged<WebRtcAccount> onToggleRegistration;

  @override
  State<AccountsBottomSheet> createState() => _AccountsBottomSheetState();
}

class _AccountsBottomSheetState extends State<AccountsBottomSheet> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredAccounts = widget.accounts
        .where((account) => _matchesAccount(account, _searchController.text))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Accounts',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onAddAccount,
                    tooltip: 'Add account',
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SearchBox(
                controller: _searchController,
                hintText: 'Search accounts',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (widget.accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('No WebRTC accounts')),
                )
              else if (filteredAccounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('No accounts match your search.')),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: filteredAccounts
                        .map(
                          (account) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(account.name),
                            subtitle: Text(
                              account.diagnostic == null
                                  ? '${account.username}@${account.domain}'
                                  : '${account.username}@${account.domain}\n${account.diagnostic!.summary}',
                            ),
                            isThreeLine: account.diagnostic != null,
                            leading: Icon(
                              widget.selectedAccount?.id == account.id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                            ),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  onPressed: () =>
                                      widget.onToggleRegistration(account),
                                  tooltip:
                                      account.status ==
                                          RegistrationStatus.registered
                                      ? 'Disconnect account'
                                      : 'Register account',
                                  icon: Icon(
                                    account.status ==
                                            RegistrationStatus.registered
                                        ? Icons.logout
                                        : Icons.login,
                                  ),
                                ),
                                if (account.diagnostic != null)
                                  IconButton(
                                    onPressed: () =>
                                        _showRegistrationDiagnosticDialog(
                                          context,
                                          account,
                                        ),
                                    tooltip: 'Registration details',
                                    icon: const Icon(Icons.info_outline),
                                  ),
                                IconButton(
                                  onPressed: () =>
                                      widget.onEditAccount(account),
                                  tooltip: 'Edit account',
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                            ),
                            onTap: () => widget.onSelectAccount(account),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class MobileTopBar extends StatelessWidget {
  const MobileTopBar({
    required this.account,
    required this.accountCount,
    required this.runtimeVersion,
    required this.onAccounts,
    super.key,
  });

  final WebRtcAccount? account;
  final int accountCount;
  final RuntimeVersionInfo runtimeVersion;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) {
    final currentAccount = account;
    final statusLabel = switch (currentAccount?.status) {
      RegistrationStatus.registered => 'Registrado',
      RegistrationStatus.registering => 'Registrando',
      RegistrationStatus.failed => 'Falha',
      RegistrationStatus.offline => 'Sem Serviço',
      null => 'Sem Serviço',
    };
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 82,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: onAccounts,
                icon: const Icon(Icons.menu, size: 32),
              ),
              if (accountCount == 0)
                const Positioned(
                  right: 7,
                  top: 8,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text('!', style: TextStyle(fontSize: 11)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  currentAccount == null
                      ? 'Nenhuma conta'
                      : currentAccount.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 82,
            child: Align(
              alignment: Alignment.centerRight,
              child: VersionBadge(versionInfo: runtimeVersion, compact: true),
            ),
          ),
        ],
      ),
    );
  }
}

class MobileDialerView extends StatelessWidget {
  const MobileDialerView({
    required this.dialNumber,
    required this.voip,
    required this.selectedAccount,
    required this.onAppend,
    required this.onBackspace,
    required this.onClear,
    required this.onCall,
    super.key,
  });

  final String dialNumber;
  final PhoneWebVoipController voip;
  final WebRtcAccount? selectedAccount;
  final ValueChanged<String> onAppend;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canCall =
        selectedAccount != null &&
        voip.registrationStatus == RegistrationStatus.registered &&
        dialNumber.trim().isNotEmpty &&
        !voip.hasActiveCall;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final tightHeight = availableHeight < 520;
        final compactHeight = availableHeight < 640;
        final callButtonSize = tightHeight
            ? 48.0
            : compactHeight
            ? 56.0
            : 66.0;
        final brandIconSize = tightHeight
            ? 34.0
            : compactHeight
            ? 50.0
            : 76.0;
        final brandFontSize = tightHeight
            ? 22.0
            : compactHeight
            ? 28.0
            : 36.0;
        final numberFontSize = tightHeight
            ? 28.0
            : compactHeight
            ? 34.0
            : 42.0;
        final contentPadding = tightHeight
            ? 4.0
            : compactHeight
            ? 8.0
            : 16.0;
        final preferredDialKeyHeight = tightHeight
            ? 48.0
            : compactHeight
            ? 58.0
            : 74.0;
        final topAreaHeight = tightHeight
            ? 76.0
            : compactHeight
            ? 112.0
            : 154.0;
        final controlsHeight =
            callButtonSize +
            (voip.hasActiveCall ? 78.0 : 0.0) +
            (tightHeight
                ? 14.0
                : compactHeight
                ? 18.0
                : 26.0);
        final dialPadChrome = tightHeight
            ? 14.0
            : compactHeight
            ? 20.0
            : 34.0;
        final maxDialKeyHeight =
            ((availableHeight -
                        topAreaHeight -
                        controlsHeight -
                        dialPadChrome) /
                    4)
                .clamp(42.0, 78.0)
                .toDouble();
        final dialKeyHeight = preferredDialKeyHeight > maxDialKeyHeight
            ? maxDialKeyHeight
            : preferredDialKeyHeight;

        return Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(contentPadding),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: dialNumber.isEmpty
                        ? Column(
                            key: const ValueKey('brand'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_calling_3_outlined,
                                size: brandIconSize,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              SizedBox(
                                height: tightHeight
                                    ? 4
                                    : compactHeight
                                    ? 6
                                    : 12,
                              ),
                              Text(
                                'MNSCloud',
                                style: TextStyle(
                                  fontSize: brandFontSize,
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            key: const ValueKey('number'),
                            dialNumber,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: numberFontSize,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 0,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                tightHeight
                    ? 2
                    : compactHeight
                    ? 6
                    : 16,
                8,
                2,
              ),
              child: MobileDialPad(
                keyHeight: dialKeyHeight,
                onAppend: onAppend,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                0,
                8,
                tightHeight
                    ? 4
                    : compactHeight
                    ? 6
                    : 14,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: MobileUtilityButton(
                        icon: Icons.voicemail,
                        label: '',
                        compact: compactHeight,
                        onPressed: () => onAppend('*97'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: callButtonSize,
                        height: callButtonSize,
                        child: FilledButton(
                          onPressed: canCall ? onCall : null,
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            backgroundColor: colorScheme.secondary,
                            disabledBackgroundColor:
                                colorScheme.surfaceContainerHighest,
                            padding: EdgeInsets.zero,
                          ),
                          child: Icon(
                            Icons.call,
                            size: compactHeight ? 26 : 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: MobileUtilityButton(
                        icon: Icons.backspace_outlined,
                        label: '',
                        compact: compactHeight,
                        onPressed: dialNumber.isEmpty ? null : onBackspace,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (voip.hasActiveCall)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: ActiveCallControls(voip: voip),
              ),
          ],
        );
      },
    );
  }
}

class MobileDialPad extends StatelessWidget {
  const MobileDialPad({required this.onAppend, this.keyHeight = 86, super.key});

  final ValueChanged<String> onAppend;
  final double keyHeight;

  static const keys = [
    ('1', ''),
    ('2', 'ABC'),
    ('3', 'DEF'),
    ('4', 'GHI'),
    ('5', 'JKL'),
    ('6', 'MNO'),
    ('7', 'PQRS'),
    ('8', 'TUV'),
    ('9', 'WXYZ'),
    ('*', ''),
    ('0', '+'),
    ('#', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: keyHeight,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        return TextButton(
          onPressed: () => onAppend(key.$1),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurface,
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const RoundedRectangleBorder(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                key.$1,
                style: TextStyle(
                  fontSize: keyHeight < 46
                      ? 26
                      : keyHeight < 52
                      ? 30
                      : keyHeight < 68
                      ? 34
                      : 40,
                  fontWeight: FontWeight.w300,
                  height: 1,
                ),
              ),
              SizedBox(
                height: keyHeight < 46
                    ? 12
                    : keyHeight < 52
                    ? 16
                    : 20,
                child: Text(
                  key.$2,
                  style: TextStyle(
                    fontSize: keyHeight < 46
                        ? 10
                        : keyHeight < 52
                        ? 11
                        : 13,
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MobileUtilityButton extends StatelessWidget {
  const MobileUtilityButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(
          alpha: 0.52,
        ),
        minimumSize: Size(compact ? 64 : 78, compact ? 54 : 64),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 28 : 34,
            color: enabled
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.52),
          ),
          Text(
            label.isEmpty ? ' ' : label,
            style: TextStyle(
              color: enabled
                  ? colorScheme.onSurfaceVariant
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.52),
            ),
          ),
        ],
      ),
    );
  }
}

class MobileContactsView extends StatefulWidget {
  const MobileContactsView({
    required this.contacts,
    required this.onAddContact,
    required this.onEditContact,
    required this.onDialContact,
    required this.onSyncContacts,
    required this.contactsSyncing,
    required this.contactsStatus,
    super.key,
  });

  final List<PhoneContact> contacts;
  final VoidCallback onAddContact;
  final ValueChanged<PhoneContact> onEditContact;
  final ValueChanged<PhoneContact> onDialContact;
  final VoidCallback onSyncContacts;
  final bool contactsSyncing;
  final String contactsStatus;

  @override
  State<MobileContactsView> createState() => _MobileContactsViewState();
}

class _MobileContactsViewState extends State<MobileContactsView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredContacts = widget.contacts
        .where((contact) => _matchesContact(contact, _searchController.text))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Contatos',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: widget.contactsSyncing
                    ? null
                    : widget.onSyncContacts,
                tooltip: 'Sincronizar agenda do dispositivo',
                icon: widget.contactsSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_outlined),
              ),
              IconButton(
                onPressed: widget.onAddContact,
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchBox(
            controller: _searchController,
            hintText: 'Buscar contato',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.contactsStatus,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: widget.contacts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.contacts_outlined,
                          size: 72,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        const Text('Nenhum contato'),
                        const SizedBox(height: 4),
                        Text(
                          'Adicione contatos para discar mais rápido.',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: widget.contactsSyncing
                              ? null
                              : widget.onSyncContacts,
                          icon: widget.contactsSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync_outlined),
                          label: const Text('Sincronizar agenda'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: widget.onAddContact,
                          icon: const Icon(Icons.add),
                          label: const Text('Adicionar contato'),
                        ),
                      ],
                    ),
                  )
                : filteredContacts.isEmpty
                ? const MobileEmptyTab(
                    icon: Icons.search_off_outlined,
                    title: 'Nenhum contato encontrado',
                    message: 'Tente buscar por nome, empresa ou número.',
                  )
                : ListView.separated(
                    itemCount: filteredContacts.length,
                    separatorBuilder: (context, index) =>
                        Divider(color: colorScheme.outlineVariant),
                    itemBuilder: (context, index) {
                      final contact = filteredContacts[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          foregroundColor: colorScheme.onPrimaryContainer,
                          child: Text(
                            contact.name.isEmpty ? '?' : contact.name[0],
                          ),
                        ),
                        title: Text(contact.name),
                        subtitle: Text(
                          contact.company.isEmpty
                              ? contact.number
                              : '${contact.company} · ${contact.number}',
                        ),
                        isThreeLine:
                            contact.source == PhoneContactSource.native,
                        trailing: Wrap(
                          children: [
                            if (contact.source == PhoneContactSource.native)
                              const Tooltip(
                                message: 'Contato sincronizado do dispositivo',
                                child: Icon(Icons.contacts_outlined, size: 20),
                              ),
                            IconButton(
                              onPressed: () => widget.onEditContact(contact),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () => widget.onDialContact(contact),
                              icon: const Icon(Icons.call_outlined),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class MobileHistoryView extends StatefulWidget {
  const MobileHistoryView({
    required this.entries,
    required this.onDial,
    super.key,
  });

  final List<PhoneCallHistoryEntry> entries;
  final ValueChanged<PhoneCallHistoryEntry> onDial;

  @override
  State<MobileHistoryView> createState() => _MobileHistoryViewState();
}

class _MobileHistoryViewState extends State<MobileHistoryView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = widget.entries
        .where(
          (entry) => _matchesCallHistoryEntry(entry, _searchController.text),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        children: [
          SearchBox(
            controller: _searchController,
            hintText: 'Buscar histórico',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: widget.entries.isEmpty
                ? const MobileEmptyTab(
                    icon: Icons.history,
                    title: 'Histórico vazio',
                    message:
                        'As chamadas realizadas e recebidas aparecerão aqui.',
                  )
                : filteredEntries.isEmpty
                ? const MobileEmptyTab(
                    icon: Icons.search_off_outlined,
                    title: 'Nenhuma chamada encontrada',
                    message: 'Tente buscar por número, conta, status ou SIP.',
                  )
                : ListView.separated(
                    itemCount: filteredEntries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      return CallHistoryTile(
                        entry: entry,
                        onDial: () => widget.onDial(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class MobileMessagesView extends StatelessWidget {
  const MobileMessagesView({super.key});

  @override
  Widget build(BuildContext context) {
    // VNumero (Fase 2): troca o `MessagesPanel` vazio pela lista de
    // conversas real, estilo iMessage, ligada ao Supabase Realtime +
    // cache local (Isar). `MessagesPanel` continua existindo e é usado
    // sem alteração na barra lateral do layout desktop
    // (ver `WorkspacePanels`).
    return const ConversationsListView();
  }
}

class MobileEmptyTab extends StatelessWidget {
  const MobileEmptyTab({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 76, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    required this.accountCount,
    required this.runtimeVersion,
    required this.onRefreshVersion,
    required this.onAddAccount,
    super.key,
  });

  final int accountCount;
  final RuntimeVersionInfo runtimeVersion;
  final VoidCallback onRefreshVersion;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;

    return Flex(
      direction: compact ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MNSCloud PhoneWeb',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '$accountCount WebRTC account${accountCount == 1 ? '' : 's'} configured',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SizedBox(
          height: compact ? 14 : 0,
          width: compact ? double.infinity : 0,
        ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: compact ? WrapAlignment.start : WrapAlignment.end,
          children: [
            VersionBadge(
              versionInfo: runtimeVersion,
              onRefresh: onRefreshVersion,
            ),
            FilledButton.icon(
              onPressed: onAddAccount,
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ],
        ),
      ],
    );
  }
}

class VersionBadge extends StatelessWidget {
  const VersionBadge({
    required this.versionInfo,
    this.compact = false,
    this.onRefresh,
    super.key,
  });

  final RuntimeVersionInfo versionInfo;
  final bool compact;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final updateAvailable = versionInfo.updateAvailable;
    final foreground = updateAvailable
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSurfaceVariant;
    final background = updateAvailable
        ? colorScheme.tertiaryContainer
        : colorScheme.surfaceContainerHighest;
    final borderColor = updateAvailable
        ? colorScheme.tertiary
        : colorScheme.outlineVariant;
    final current = versionInfo.displayVersion;
    final latest = versionInfo.latestVersion;
    final tooltip = updateAvailable
        ? 'Current $current · New version v$latest available'
        : latest == null
        ? 'Current $current'
        : 'Current $current · Latest v$latest';

    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            updateAvailable ? Icons.system_update_alt : Icons.verified_outlined,
            size: compact ? 14 : 16,
            color: foreground,
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            compact
                ? current
                : updateAvailable
                ? '$current → v$latest'
                : current,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      child: onRefresh == null
          ? badge
          : InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onRefresh,
              child: badge,
            ),
    );
  }
}

class AccountPanel extends StatefulWidget {
  const AccountPanel({
    required this.accounts,
    required this.selectedAccountId,
    required this.onAddAccount,
    required this.onEditAccount,
    required this.onRemoveAccount,
    required this.onSelectAccount,
    required this.onToggleRegistration,
    super.key,
  });

  final List<WebRtcAccount> accounts;
  final String? selectedAccountId;
  final VoidCallback onAddAccount;
  final ValueChanged<WebRtcAccount> onEditAccount;
  final ValueChanged<WebRtcAccount> onRemoveAccount;
  final ValueChanged<WebRtcAccount> onSelectAccount;
  final ValueChanged<WebRtcAccount> onToggleRegistration;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredAccounts = widget.accounts
        .where((account) => _matchesAccount(account, _searchController.text))
        .toList();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(
            icon: Icons.account_circle_outlined,
            title: 'Accounts',
            action: IconButton(
              tooltip: 'Add account',
              onPressed: widget.onAddAccount,
              icon: const Icon(Icons.add),
            ),
          ),
          const SizedBox(height: 12),
          SearchBox(
            controller: _searchController,
            hintText: 'Search accounts',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (widget.accounts.isEmpty)
            EmptyState(
              icon: Icons.wifi_calling_3_outlined,
              title: 'No WebRTC accounts',
              message: 'Add a WSS provider account to start configuring calls.',
              actionLabel: 'Add account',
              onAction: widget.onAddAccount,
            )
          else if (filteredAccounts.isEmpty)
            const EmptyState(
              icon: Icons.search_off_outlined,
              title: 'No accounts found',
              message:
                  'Search by account name, SIP user, domain, WSS or status.',
            )
          else
            ...filteredAccounts.map(
              (account) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AccountTile(
                  account: account,
                  selected: widget.selectedAccountId == account.id,
                  onSelect: () => widget.onSelectAccount(account),
                  onEdit: () => widget.onEditAccount(account),
                  onRemove: () => widget.onRemoveAccount(account),
                  onToggle: () => widget.onToggleRegistration(account),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
              ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
    );
  }
}

class AccountTile extends StatelessWidget {
  const AccountTile({
    required this.account,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onRemove,
    required this.onToggle,
    super.key,
  });

  final WebRtcAccount account;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${account.username}@${account.domain}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                account.wssServer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (account.diagnostic != null) ...[
                const SizedBox(height: 10),
                RegistrationDiagnosticBanner(diagnostic: account.diagnostic!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onToggle,
                    icon: Icon(
                      account.status == RegistrationStatus.registered
                          ? Icons.logout
                          : Icons.login,
                    ),
                    label: Text(
                      account.status == RegistrationStatus.registered
                          ? 'Disable'
                          : 'Enable',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Edit account',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (account.diagnostic != null)
                    IconButton(
                      tooltip: 'Registration details',
                      onPressed: () =>
                          _showRegistrationDiagnosticDialog(context, account),
                      icon: const Icon(Icons.info_outline),
                    ),
                  IconButton(
                    tooltip: 'Remove account',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RegistrationDiagnosticBanner extends StatelessWidget {
  const RegistrationDiagnosticBanner({required this.diagnostic, super.key});

  final RegistrationDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final color = switch (diagnostic.severity) {
      RegistrationDiagnosticSeverity.info => Theme.of(
        context,
      ).colorScheme.primary,
      RegistrationDiagnosticSeverity.warning => const Color(0xFFB45309),
      RegistrationDiagnosticSeverity.error => const Color(0xFFB91C1C),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              diagnostic.retrying
                  ? Icons.sync_problem_outlined
                  : Icons.info_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                diagnostic.retrying
                    ? '${diagnostic.summary} · retrying'
                    : diagnostic.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showRegistrationDiagnosticDialog(
  BuildContext context,
  WebRtcAccount account,
) async {
  final diagnostic = account.diagnostic;
  if (diagnostic == null) return;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Registration diagnostic'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(label: 'Account', value: account.name),
              InfoRow(label: 'SIP user', value: account.username),
              InfoRow(label: 'Domain', value: account.domain),
              InfoRow(label: 'WSS', value: account.wssServer),
              InfoRow(label: 'Status', value: account.status.label),
              InfoRow(label: 'Diagnostic', value: diagnostic.summary),
              InfoRow(label: 'Code', value: diagnostic.code),
              if (diagnostic.reasonPhrase != null)
                InfoRow(label: 'Reason', value: diagnostic.reasonPhrase!),
              InfoRow(
                label: 'Retrying',
                value: diagnostic.retrying ? 'Yes' : 'No',
              ),
              InfoRow(
                label: 'Observed',
                value: diagnostic.observedAt.toLocal().toString(),
              ),
              const SizedBox(height: 12),
              Text(
                diagnostic.detail,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: diagnostic.copyText));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostic copied')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class DialerPanel extends StatelessWidget {
  const DialerPanel({
    required this.selectedAccount,
    required this.dialNumber,
    required this.voip,
    required this.onAppend,
    required this.onBackspace,
    required this.onClear,
    required this.onCall,
    super.key,
  });

  final WebRtcAccount? selectedAccount;
  final String dialNumber;
  final PhoneWebVoipController voip;
  final ValueChanged<String> onAppend;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final canCall =
        selectedAccount != null &&
        voip.registrationStatus == RegistrationStatus.registered &&
        dialNumber.trim().isNotEmpty &&
        !voip.hasActiveCall;
    final colorScheme = Theme.of(context).colorScheme;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(icon: Icons.dialpad_outlined, title: 'Dialer'),
          const SizedBox(height: 16),
          AccountContextBanner(account: selectedAccount),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              dialNumber.isEmpty ? 'Enter number' : dialNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: dialNumber.isEmpty
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Backspace',
                            onPressed: dialNumber.isEmpty ? null : onBackspace,
                            icon: const Icon(Icons.backspace_outlined),
                          ),
                          IconButton(
                            tooltip: 'Clear',
                            onPressed: dialNumber.isEmpty ? null : onClear,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DialPad(onAppend: onAppend),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => onAppend('*97'),
                          child: const Icon(Icons.voicemail),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: canCall ? onCall : null,
                            icon: const Icon(Icons.call),
                            label: const Text('Call'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (voip.hasActiveCall) ...[
                    const SizedBox(height: 14),
                    ActiveCallControls(voip: voip),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountContextBanner extends StatelessWidget {
  const AccountContextBanner({required this.account, super.key});

  final WebRtcAccount? account;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentAccount = account;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            account == null ? Icons.info_outline : Icons.router_outlined,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              currentAccount == null
                  ? 'Select or add an account before placing calls.'
                  : '${currentAccount.name} · ${currentAccount.status.label}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class DialPad extends StatelessWidget {
  const DialPad({required this.onAppend, super.key});

  final ValueChanged<String> onAppend;

  @override
  Widget build(BuildContext context) {
    const values = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 58,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final value = values[index];

        return OutlinedButton(
          onPressed: () => onAppend(value),
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}

class ActiveCallControls extends StatelessWidget {
  const ActiveCallControls({required this.voip, super.key});

  final PhoneWebVoipController voip;

  @override
  Widget build(BuildContext context) {
    final remote = voip.remoteIdentity.isEmpty
        ? 'Unknown'
        : voip.remoteIdentity;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.call_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$remote · ${voip.callState.name}',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (voip.hasEstablishedCall) ...[
                const SizedBox(width: 10),
                Text(
                  voip.formattedCallDuration,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (voip.hasIncomingCall) ...[
                FilledButton.icon(
                  onPressed: voip.answer,
                  icon: const Icon(Icons.call),
                  label: const Text('Answer'),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: voip.toggleMute,
                  icon: Icon(voip.muted ? Icons.mic_off : Icons.mic),
                  label: Text(voip.muted ? 'Unmute' : 'Mute'),
                ),
                FilledButton.tonalIcon(
                  onPressed: voip.toggleHold,
                  icon: Icon(voip.onHold ? Icons.play_arrow : Icons.pause),
                  label: Text(voip.onHold ? 'Resume' : 'Hold'),
                ),
              ],
              FilledButton.icon(
                onPressed: voip.rejectOrHangup,
                icon: const Icon(Icons.call_end),
                label: Text(voip.hasIncomingCall ? 'Decline' : 'Hang up'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB91C1C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CallHistoryPanel extends StatefulWidget {
  const CallHistoryPanel({required this.entries, this.onDial, super.key});

  final List<PhoneCallHistoryEntry> entries;
  final ValueChanged<PhoneCallHistoryEntry>? onDial;

  @override
  State<CallHistoryPanel> createState() => _CallHistoryPanelState();
}

class _CallHistoryPanelState extends State<CallHistoryPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = widget.entries
        .where(
          (entry) => _matchesCallHistoryEntry(entry, _searchController.text),
        )
        .toList();
    final previewEntries = filteredEntries.take(8).toList();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(icon: Icons.history, title: 'Call history'),
          const SizedBox(height: 12),
          SearchBox(
            controller: _searchController,
            hintText: 'Search call history',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (widget.entries.isEmpty)
            const EmptyState(
              icon: Icons.call_outlined,
              title: 'No calls yet',
              message: 'Completed calls will appear here.',
            )
          else if (previewEntries.isEmpty)
            const EmptyState(
              icon: Icons.search_off_outlined,
              title: 'No calls found',
              message: 'Search by number, account, status or SIP diagnostic.',
            )
          else
            ...previewEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CallHistoryTile(
                  entry: entry,
                  onDial: widget.onDial == null
                      ? null
                      : () => widget.onDial!(entry),
                ),
              ),
            ),
          if (filteredEntries.length > previewEntries.length)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${filteredEntries.length - previewEntries.length} more matching call(s).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CallHistoryTile extends StatelessWidget {
  const CallHistoryTile({required this.entry, this.onDial, super.key});

  final PhoneCallHistoryEntry entry;
  final VoidCallback? onDial;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (entry.direction) {
      PhoneCallDirection.incoming => Icons.call_received,
      PhoneCallDirection.outgoing => Icons.call_made,
    };
    final statusColor = switch (entry.status) {
      PhoneCallStatus.completed => colorScheme.primary,
      PhoneCallStatus.missed => Colors.orange,
      PhoneCallStatus.failed => colorScheme.error,
    };
    final statusLabel = switch (entry.status) {
      PhoneCallStatus.completed => 'Completed',
      PhoneCallStatus.missed => 'Missed',
      PhoneCallStatus.failed => 'Failed',
    };

    final summary =
        '$statusLabel · ${_formatCallDurationSeconds(entry.durationSeconds)}';
    final diagnostic = entry.diagnostic.trim();

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: statusColor.withValues(alpha: 0.18),
              foregroundColor: statusColor,
              child: Icon(icon, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.remoteIdentity,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatShortTime(entry.startedAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (diagnostic.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      diagnostic,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Retornar ligação',
              onPressed: onDial,
              icon: const Icon(Icons.call_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class MessagesPanel extends StatefulWidget {
  const MessagesPanel({super.key});

  @override
  State<MessagesPanel> createState() => _MessagesPanelState();
}

class _MessagesPanelState extends State<MessagesPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle(icon: Icons.chat_bubble_outline, title: 'Mensagens'),
          const SizedBox(height: 12),
          SearchBox(
            controller: _searchController,
            hintText: 'Pesquisar mensagens',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          EmptyState(
            icon: query.isEmpty
                ? Icons.chat_bubble_outline
                : Icons.search_off_outlined,
            title: query.isEmpty
                ? 'Nenhuma mensagem ainda'
                : 'Nenhuma mensagem encontrada',
            message: query.isEmpty
                ? 'Correio de voz e mensagens ficarão disponíveis aqui.'
                : 'Quando mensagens forem sincronizadas, a busca localizará por contato, número, assunto e conteúdo.',
          ),
        ],
      ),
    );
  }
}

String _formatCallDurationSeconds(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final minutes = safeSeconds ~/ 60;
  final remainingSeconds = safeSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}

String _formatShortTime(DateTime value) {
  final now = DateTime.now();
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return time;
  }
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} $time';
}

String _dialableHistoryIdentity(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('sip:')) {
    final withoutScheme = trimmed.substring(4);
    return withoutScheme.split('@').first;
  }
  return trimmed.split('@').first;
}

bool _matchesAccount(WebRtcAccount account, String query) {
  final normalizedQuery = _normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;

  return _searchableText([
    account.name,
    account.displayName,
    account.username,
    account.domain,
    account.wssServer,
    account.stunServer,
    account.turnServer,
    account.status.label,
    account.diagnostic?.summary,
    account.diagnostic?.detail,
    account.diagnostic?.code,
    account.diagnostic?.reasonPhrase,
  ]).contains(normalizedQuery);
}

bool _matchesContact(PhoneContact contact, String query) {
  final normalizedQuery = _normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;

  return _searchableText([
    contact.name,
    contact.number,
    contact.company,
    contact.source.name,
  ]).contains(normalizedQuery);
}

bool _matchesCallHistoryEntry(PhoneCallHistoryEntry entry, String query) {
  final normalizedQuery = _normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;

  final statusLabel = switch (entry.status) {
    PhoneCallStatus.completed => 'Completed',
    PhoneCallStatus.missed => 'Missed',
    PhoneCallStatus.failed => 'Failed',
  };
  final directionLabel = switch (entry.direction) {
    PhoneCallDirection.incoming => 'Incoming',
    PhoneCallDirection.outgoing => 'Outgoing',
  };

  return _searchableText([
    entry.remoteIdentity,
    _dialableHistoryIdentity(entry.remoteIdentity),
    entry.accountName,
    entry.diagnostic,
    statusLabel,
    directionLabel,
    _formatShortTime(entry.startedAt),
  ]).contains(normalizedQuery);
}

String _searchableText(Iterable<String?> values) {
  return values
      .whereType<String>()
      .map(_normalizeSearchText)
      .where((value) => value.isNotEmpty)
      .join(' ');
}

String _normalizeSearchText(String value) {
  return value.trim().toLowerCase();
}

class ContactsSummaryPanel extends StatefulWidget {
  const ContactsSummaryPanel({
    required this.contacts,
    required this.contactsSyncing,
    required this.contactsStatus,
    required this.onAddContact,
    required this.onSyncContacts,
    required this.onEditContact,
    required this.onDialContact,
    super.key,
  });

  final List<PhoneContact> contacts;
  final bool contactsSyncing;
  final String contactsStatus;
  final VoidCallback onAddContact;
  final VoidCallback onSyncContacts;
  final ValueChanged<PhoneContact> onEditContact;
  final ValueChanged<PhoneContact> onDialContact;

  @override
  State<ContactsSummaryPanel> createState() => _ContactsSummaryPanelState();
}

class _ContactsSummaryPanelState extends State<ContactsSummaryPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredContacts = widget.contacts
        .where((contact) => _matchesContact(contact, _searchController.text))
        .toList();
    final previewContacts = filteredContacts.take(4).toList();

    return SectionCard(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: PanelTitle(
                    icon: Icons.contacts_outlined,
                    title: 'Contacts',
                  ),
                ),
                IconButton(
                  onPressed: widget.contactsSyncing
                      ? null
                      : widget.onSyncContacts,
                  tooltip: 'Sync device contacts',
                  icon: widget.contactsSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_outlined),
                ),
                IconButton(
                  onPressed: widget.onAddContact,
                  tooltip: 'Add contact',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SearchBox(
              controller: _searchController,
              hintText: 'Search contacts',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Text(
              widget.contactsStatus,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.contacts.isEmpty)
              EmptyState(
                icon: Icons.contacts_outlined,
                title: 'No contacts yet',
                message: 'Sync the device address book or add a local contact.',
                actionLabel: 'Sync contacts',
                onAction: widget.contactsSyncing ? null : widget.onSyncContacts,
              )
            else if (previewContacts.isEmpty)
              const EmptyState(
                icon: Icons.search_off_outlined,
                title: 'No contacts found',
                message: 'Search by name, company or number.',
              )
            else
              ...previewContacts.map(
                (contact) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: Text(contact.name.isEmpty ? '?' : contact.name[0]),
                  ),
                  title: Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    contact.number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        onPressed: () => widget.onEditContact(contact),
                        tooltip: 'Edit contact',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        onPressed: () => widget.onDialContact(contact),
                        tooltip: 'Call contact',
                        icon: const Icon(Icons.call_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            if (filteredContacts.length > previewContacts.length)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${filteredContacts.length - previewContacts.length} more matching contact(s).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ContactDialog extends StatefulWidget {
  const ContactDialog({this.contact, super.key});

  final PhoneContact? contact;

  @override
  State<ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _numberController;
  late final TextEditingController _companyController;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _nameController = TextEditingController(text: contact?.name ?? '');
    _numberController = TextEditingController(text: contact?.number ?? '');
    _companyController = TextEditingController(text: contact?.company ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.contact == null ? 'Add contact' : 'Edit contact',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _numberController,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  keyboardType: TextInputType.phone,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _companyController,
                  decoration: const InputDecoration(labelText: 'Company'),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _save, child: const Text('Save')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required field' : null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final existing = widget.contact;
    Navigator.pop(
      context,
      PhoneContact(
        id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        number: _numberController.text.trim(),
        company: _companyController.text.trim(),
        source: existing?.source ?? PhoneContactSource.manual,
      ),
    );
  }
}

class AccountDialog extends StatefulWidget {
  const AccountDialog({this.account, super.key});

  final WebRtcAccount? account;

  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _domainController;
  late final TextEditingController _wssController;
  late final TextEditingController _stunController;
  late final TextEditingController _turnController;
  late final TextEditingController _passwordController;
  WebRtcCodecPolicy _codecPolicy = WebRtcCodecPolicy.automaticRecommended;
  bool _enabled = true;
  bool _autoRegister = true;
  bool _allowInsecureTransport = false;

  @override
  void initState() {
    super.initState();
    final account = widget.account;

    _nameController = TextEditingController(text: account?.name ?? '');
    _displayNameController = TextEditingController(
      text: account?.displayName ?? '',
    );
    _usernameController = TextEditingController(text: account?.username ?? '');
    _domainController = TextEditingController(text: account?.domain ?? '');
    _wssController = TextEditingController(text: account?.wssServer ?? '');
    _stunController = TextEditingController(text: account?.stunServer ?? '');
    _turnController = TextEditingController(text: account?.turnServer ?? '');
    _passwordController = TextEditingController(text: account?.password ?? '');
    _codecPolicy =
        account?.codecPolicy ?? WebRtcCodecPolicy.automaticRecommended;
    _enabled = account?.enabled ?? true;
    _autoRegister = account?.autoRegister ?? true;
    _allowInsecureTransport = account?.allowInsecureTransport ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    _usernameController.dispose();
    _domainController.dispose();
    _wssController.dispose();
    _stunController.dispose();
    _turnController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 16 : 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.account == null
                        ? 'Add WebRTC account'
                        : 'Edit WebRTC account',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Account name',
                          ),
                          validator: _required,
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'SIP user',
                          ),
                          validator: _required,
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'SIP Password',
                          ),
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _domainController,
                          decoration: const InputDecoration(
                            labelText: 'SIP Domain',
                          ),
                          validator: _required,
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _wssController,
                          decoration: const InputDecoration(
                            labelText: 'WSS server',
                            hintText: 'wss://pbx.example.com/ws',
                          ),
                          validator: _wss,
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _stunController,
                          decoration: const InputDecoration(
                            labelText: 'STUN server',
                            hintText: 'stun:stun.example.com:3478',
                          ),
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: TextFormField(
                          controller: _turnController,
                          decoration: const InputDecoration(
                            labelText: 'TURN server',
                            hintText: 'turn:turn.example.com:3478',
                          ),
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 224,
                        child: DropdownButtonFormField<WebRtcCodecPolicy>(
                          initialValue: _codecPolicy,
                          decoration: const InputDecoration(
                            labelText: 'Codec policy',
                          ),
                          items: WebRtcCodecPolicy.values
                              .map(
                                (policy) => DropdownMenuItem<WebRtcCodecPolicy>(
                                  value: policy,
                                  child: Text(policy.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _codecPolicy = value;
                            });
                          },
                        ),
                      ),
                      DialogField(
                        width: compact ? double.infinity : 464,
                        child: Text(
                          _codecPolicy.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        selected: _enabled,
                        label: const Text('Enabled'),
                        avatar: Icon(_enabled ? Icons.check : Icons.close),
                        onSelected: (value) {
                          setState(() {
                            _enabled = value;
                          });
                        },
                      ),
                      FilterChip(
                        selected: _autoRegister,
                        label: const Text('Auto register'),
                        avatar: Icon(
                          _autoRegister ? Icons.sync : Icons.sync_disabled,
                        ),
                        onSelected: (value) {
                          setState(() {
                            _autoRegister = value;
                          });
                        },
                      ),
                      FilterChip(
                        selected: _allowInsecureTransport,
                        label: const Text('Allow WS dev'),
                        avatar: Icon(
                          _allowInsecureTransport
                              ? Icons.lock_open
                              : Icons.lock_outline,
                        ),
                        onSelected: (value) {
                          setState(() {
                            _allowInsecureTransport = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  String? _wss(String? value) {
    final required = _required(value);
    if (required != null) {
      return required;
    }
    final trimmed = value!.trim();
    if (!trimmed.startsWith('wss://') && !trimmed.startsWith('ws://')) {
      return 'Use a WSS URL';
    }
    if (trimmed.startsWith('ws://') && !_allowInsecureTransport) {
      return 'Enable WS dev for insecure transport';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final existing = widget.account;
    final account = WebRtcAccount(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      displayName: _displayNameController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      domain: _domainController.text.trim(),
      wssServer: _wssController.text.trim(),
      stunServer: _stunController.text.trim(),
      turnServer: _turnController.text.trim(),
      hasPassword:
          _passwordController.text.isNotEmpty ||
          (existing?.hasPassword ?? false),
      allowInsecureTransport: _allowInsecureTransport,
      codecPolicy: _codecPolicy,
      enabled: _enabled,
      autoRegister: _autoRegister,
      status: existing?.status ?? RegistrationStatus.offline,
      diagnostic: existing?.diagnostic,
    );

    Navigator.of(context).pop(account);
  }
}

class DialogField extends StatelessWidget {
  const DialogField({required this.width, required this.child, super.key});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

class PanelTitle extends StatelessWidget {
  const PanelTitle({
    required this.icon,
    required this.title,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (action != null) action,
      
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});

  final RegistrationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RegistrationStatus.registered => const Color(0xFF047857),
      RegistrationStatus.registering => const Color(0xFFB45309),
      RegistrationStatus.failed => const Color(0xFFB91C1C),
      RegistrationStatus.offline => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };

    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      label: Text(status.label),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
