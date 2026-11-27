import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ВСТАВЬТЕ из Supabase: Project Settings -> API
const supabaseUrl = 'https://ulzdafxczbaqhoowupxs.supabase.co';
const supabaseKey = 'sb_publishable_o_GIeF178TGSBZaUlH_22g_vLn0badN';

const categories = ['Транспорт', 'Недвижимость', 'Электроника', 'Одежда', 'Дом и сад', 'Услуги', 'Детям', 'Другое'];

SupabaseClient get sb => Supabase.instance.client;
void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
String money(num p) => p > 0 ? '${p.toStringAsFixed(0)} ₽' : 'Бесплатно';
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

// ---- Цвета как у Авито: белый, синий, зелёная кнопка «Позвонить» ----
const kBlue = Color(0xFF0099F7);
const kGreen = Color(0xFF04C55A);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final card = dark ? const Color(0xFF1C1C1E) : Colors.white;
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: kBlue, brightness: b).copyWith(primary: kBlue, onPrimary: Colors.white, surface: card),
    scaffoldBackgroundColor: dark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
    appBarTheme: AppBarTheme(
      backgroundColor: card,
      foregroundColor: dark ? Colors.white : const Color(0xFF1A1A1A),
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kBlue),
    ),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: card, indicatorColor: kBlue.withOpacity(.15)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

// телефон -> служебный email (тот же вход, что и на сайте; SMS не нужны)
String? normPhone(String p) {
  var d = p.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && d.startsWith('8')) d = '7${d.substring(1)}';
  if (d.length == 10) d = '7$d';
  return d.length >= 11 && d.length <= 15 ? d : null;
}

bool get loggedIn => sb.auth.currentSession != null;

Future<bool> requireLogin(BuildContext c) async {
  if (loggedIn) return true;
  await Navigator.push(c, MaterialPageRoute(builder: (_) => const AuthPage()));
  return loggedIn;
}

final favIds = ValueNotifier<Set<String>>({});

Future<void> loadFavs() async {
  if (!loggedIn) {
    favIds.value = {};
    return;
  }
  try {
    final r = await sb.from('favorites').select('ad_id').eq('user_id', sb.auth.currentUser!.id);
    favIds.value = {for (final x in r) x['ad_id'] as String};
  } catch (_) {}
}

Future<void> toggleFav(BuildContext c, String adId) async {
  if (!await requireLogin(c)) return;
  final uid = sb.auth.currentUser!.id;
  final s = {...favIds.value};
  try {
    if (s.contains(adId)) {
      await sb.from('favorites').delete().eq('user_id', uid).eq('ad_id', adId);
      s.remove(adId);
    } else {
      await sb.from('favorites').insert({'user_id': uid, 'ad_id': adId});
      s.add(adId);
    }
    favIds.value = s;
  } catch (e) {
    if (c.mounted) toast(c, 'Ошибка: $e');
  }
}

InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder());

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  final prefs = await SharedPreferences.getInstance();
  themeMode.value = ThemeMode.values[prefs.getInt('theme') ?? 0];
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, m, __) => MaterialApp(
          title: 'MADAN',
          debugShowCheckedModeBanner: false,
          themeMode: m,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          home: const Gate(),
        ),
      );
}

class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<AuthState>(
        stream: sb.auth.onAuthStateChange,
        builder: (_, __) => Shell(key: ValueKey(sb.auth.currentUser?.id ?? 'guest')),
      );
}

// ---------- Вход и регистрация ----------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final name = TextEditingController(), phone = TextEditingController(), pass = TextEditingController();
  bool reg = false, busy = false;

  Future<void> submit() async {
    final d = normPhone(phone.text);
    if (d == null) {
      toast(context, 'Введите номер телефона, например +7 900 000-00-00');
      return;
    }
    setState(() => busy = true);
    try {
      final email = '$d@phone.madan.app';
      if (reg) {
        await sb.auth.signUp(email: email, password: pass.text, data: {'name': name.text.trim(), 'phone': '+$d'});
      } else {
        await sb.auth.signInWithPassword(email: email, password: pass.text);
      }
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Ошибка: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: Navigator.canPop(c) ? AppBar() : null,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Text('MADAN', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                if (reg) ...[TextField(controller: name, decoration: deco('Имя')), const SizedBox(height: 12)],
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: deco('Номер телефона')),
                const SizedBox(height: 12),
                TextField(controller: pass, obscureText: true, decoration: deco('Пароль (от 6 символов)')),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: busy ? null : submit, child: Text(reg ? 'Зарегистрироваться' : 'Войти')),
                ),
                TextButton(
                  onPressed: () => setState(() => reg = !reg),
                  child: Text(reg ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Регистрация'),
                ),
              ]),
            ),
          ),
        ),
      );
}

// ---------- Каркас с вкладками ----------
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Map<String, dynamic>? me;
  bool loaded = false;
  int tab = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    Map<String, dynamic>? r;
    if (loggedIn) {
      try {
        r = await sb.from('profiles').select().eq('id', sb.auth.currentUser!.id).single();
      } catch (_) {}
      loadFavs();
    }
    if (mounted) setState(() {
      me = r;
      loaded = true;
    });
  }

  @override
  Widget build(BuildContext c) {
    if (!loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (me != null && me!['is_banned'] == true) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.block, size: 64, color: Colors.red),
              const SizedBox(height: 12),
              const Text('Ваш аккаунт заблокирован администратором', textAlign: TextAlign.center),
              TextButton(onPressed: () => sb.auth.signOut(), child: const Text('Выйти')),
            ]),
          ),
        ),
      );
    }
    final admin = me?['role'] == 'admin';
    final pages = <Widget>[
      FeedPage(admin: admin),
      loggedIn ? FeedPage(admin: admin, fav: true) : const GuestPage(title: 'Избранное', text: 'Войдите, чтобы сохранять понравившиеся объявления'),
      loggedIn ? AddPage(onDone: () => setState(() => tab = 0)) : const GuestPage(title: 'Подать объявление', text: 'Чтобы опубликовать объявление, войдите или зарегистрируйтесь'),
      (loggedIn && me != null) ? ProfilePage(me: me!, onChanged: load) : const GuestPage(title: 'Профиль', text: 'Войдите или зарегистрируйтесь, чтобы пользоваться всеми возможностями MADAN', settings: true),
      if (admin) const AdminPage(),
    ];
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home), label: 'Лента'),
          const NavigationDestination(icon: Icon(Icons.favorite_border), label: 'Избранное'),
          const NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Подать'),
          const NavigationDestination(icon: Icon(Icons.person), label: 'Профиль'),
          if (admin) const NavigationDestination(icon: Icon(Icons.shield), label: 'Админ'),
        ],
      ),
    );
  }
}

// ---------- Лента ----------
class FeedPage extends StatefulWidget {
  final bool admin, mine, fav;
  const FeedPage({super.key, required this.admin, this.mine = false, this.fav = false});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  List<Map<String, dynamic>> ads = [];
  bool loading = true;
  String q = '';
  String? cat;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      if (widget.fav && favIds.value.isEmpty) await loadFavs();
      var qb = sb.from('ads').select(loggedIn ? '*, profiles(name, phone)' : '*, profiles(name)');
      if (widget.fav) qb = qb.inFilter('id', favIds.value.toList());
      if (widget.mine) qb = qb.eq('user_id', sb.auth.currentUser!.id);
      if (cat != null) qb = qb.eq('category', cat!);
      if (q.isNotEmpty) qb = qb.ilike('title', '%$q%');
      final r = await qb.order('created_at', ascending: false).limit(100);
      if (mounted) setState(() => ads = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (mounted) toast(context, 'Не удалось загрузить: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  Widget card(Map<String, dynamic> a) => InkWell(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => AdPage(ad: a, admin: widget.admin)));
          if (mounted) load();
        },
        child: Card(
          color: Theme.of(context).colorScheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                a['image_url'] != null
                    ? Image.network(a['image_url'], fit: BoxFit.cover, width: double.infinity)
                    : const Center(child: Icon(Icons.image, size: 48, color: Colors.grey)),
                Positioned(
                  right: 6,
                  top: 6,
                  child: ValueListenableBuilder<Set<String>>(
                    valueListenable: favIds,
                    builder: (ctx, f, _) {
                      final on = f.contains(a['id']);
                      return InkWell(
                        onTap: () => toggleFav(ctx, a['id'] as String),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white,
                          child: Icon(on ? Icons.favorite : Icons.favorite_border, size: 18, color: on ? Colors.red : Colors.grey.shade700),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(money(a['price'] as num), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(a['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(a['city'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(widget.fav ? 'Избранное' : widget.mine ? 'Мои объявления' : 'MADAN')),
        body: Column(children: [
          if (!widget.mine && !widget.fav)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: deco('Поиск').copyWith(prefixIcon: const Icon(Icons.search)),
                    onSubmitted: (v) {
                      q = v.trim();
                      load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: cat,
                  hint: const Text('Все'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Все')),
                    ...categories.map((e) => DropdownMenuItem<String?>(value: e, child: Text(e))),
                  ],
                  onChanged: (v) {
                    cat = v;
                    load();
                  },
                ),
              ]),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ads.isEmpty
                    ? const Center(child: Text('Пока ничего нет'))
                    : RefreshIndicator(
                        onRefresh: load,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.78),
                          itemCount: ads.length,
                          itemBuilder: (_, i) => card(ads[i]),
                        ),
                      ),
          ),
        ]),
      );
}

// ---------- Страница объявления ----------
class AdPage extends StatelessWidget {
  final Map<String, dynamic> ad;
  final bool admin;
  const AdPage({super.key, required this.ad, required this.admin});

  @override
  Widget build(BuildContext c) {
    final seller = ad['profiles'] as Map<String, dynamic>?;
    final own = ad['user_id'] == sb.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(children: [
        if (ad['image_url'] != null) Image.network(ad['image_url'], height: 280, fit: BoxFit.cover),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(money(ad['price'] as num), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(ad['title'], style: const TextStyle(fontSize: 18)),
            Text('${ad['category']} · ${ad['city']}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Text(ad['description'] ?? ''),
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(seller?['name'] ?? 'Продавец'),
              subtitle: SelectableText(loggedIn ? (seller?['phone'] ?? 'Телефон не указан') : 'Войдите, чтобы увидеть контакт'),
            ),
            ValueListenableBuilder<Set<String>>(
              valueListenable: favIds,
              builder: (ctx, f, _) {
                final on = f.contains(ad['id']);
                return OutlinedButton.icon(
                  onPressed: () => toggleFav(ctx, ad['id'] as String),
                  icon: Icon(on ? Icons.favorite : Icons.favorite_border, color: on ? Colors.red : null),
                  label: Text(on ? 'В избранном' : 'В избранное'),
                );
              },
            ),
            const SizedBox(height: 8),
            if (!loggedIn) ...[
              FilledButton(onPressed: () => requireLogin(c), child: const Text('Войти, чтобы позвонить')),
              const SizedBox(height: 8),
            ],
            if ((seller?['phone'] ?? '').toString().isNotEmpty) ...[
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kGreen),
                onPressed: () async {
                  try {
                    await launchUrl(Uri.parse('tel:${seller!['phone']}'));
                  } catch (_) {
                    if (c.mounted) toast(c, 'Не удалось открыть звонилку');
                  }
                },
                icon: const Icon(Icons.call),
                label: const Text('Позвонить'),
              ),
              const SizedBox(height: 8),
            ],
            if (own || admin)
              FilledButton.tonal(
                onPressed: () async {
                  await sb.from('ads').delete().eq('id', ad['id']);
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Text('Удалить объявление'),
              ),
            if (admin && !own)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  await sb.rpc('set_ban', params: {'target': ad['user_id'], 'banned': true});
                  if (c.mounted) {
                    toast(c, 'Пользователь заблокирован');
                    Navigator.pop(c);
                  }
                },
                child: const Text('Заблокировать продавца'),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------- Подача объявления ----------
class AddPage extends StatefulWidget {
  final VoidCallback onDone;
  const AddPage({super.key, required this.onDone});
  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final title = TextEditingController(), desc = TextEditingController(), price = TextEditingController(), city = TextEditingController();
  String cat = categories.first;
  XFile? img;
  bool busy = false;

  Future<void> pick() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 80);
    if (f != null) setState(() => img = f);
  }

  Future<void> publish() async {
    if (title.text.trim().length < 3 || city.text.trim().isEmpty) {
      toast(context, 'Укажите название (от 3 символов) и город');
      return;
    }
    setState(() => busy = true);
    try {
      final uid = sb.auth.currentUser!.id;
      String? url;
      if (img != null) {
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await sb.storage.from('ads').uploadBinary(path, await img!.readAsBytes(),
            fileOptions: const FileOptions(contentType: 'image/jpeg'));
        url = sb.storage.from('ads').getPublicUrl(path);
      }
      await sb.from('ads').insert({
        'user_id': uid,
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'price': num.tryParse(price.text) ?? 0,
        'category': cat,
        'city': city.text.trim(),
        'image_url': url,
      });
      if (mounted) {
        toast(context, 'Опубликовано');
        widget.onDone();
      }
    } catch (e) {
      if (mounted) toast(context, 'Ошибка: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Новое объявление')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          OutlinedButton.icon(
            onPressed: pick,
            icon: const Icon(Icons.photo),
            label: Text(img == null ? 'Добавить фото' : 'Фото выбрано: ${img!.name}'),
          ),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: deco('Название')),
          const SizedBox(height: 12),
          TextField(controller: price, keyboardType: TextInputType.number, decoration: deco('Цена, ₽ (0 — бесплатно)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: cat,
            decoration: deco('Категория'),
            items: categories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => cat = v!),
          ),
          const SizedBox(height: 12),
          TextField(controller: city, decoration: deco('Город')),
          const SizedBox(height: 12),
          TextField(controller: desc, maxLines: 4, decoration: deco('Описание')),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : publish, child: const Text('Опубликовать')),
        ]),
      );
}

// ---------- Профиль ----------
class ProfilePage extends StatelessWidget {
  final Map<String, dynamic> me;
  final VoidCallback onChanged;
  const ProfilePage({super.key, required this.me, required this.onChanged});

  Future<void> edit(BuildContext c) async {
    final n = TextEditingController(text: me['name']);
    final p = TextEditingController(text: me['phone'] ?? '');
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Профиль'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: deco('Имя')),
          const SizedBox(height: 12),
          TextField(controller: p, keyboardType: TextInputType.phone, decoration: deco('Телефон для связи')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true) {
      await sb.from('profiles').update({'name': n.text.trim(), 'phone': p.text.trim()}).eq('id', me['id']);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: ListView(children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(me['name']),
            subtitle: Text('${me['phone'] ?? 'телефон не указан'}${me['role'] == 'admin' ? ' · администратор' : ''}'),
          ),
          ListTile(leading: const Icon(Icons.edit), title: const Text('Изменить имя и телефон'), onTap: () => edit(c)),
          ListTile(
            leading: const Icon(Icons.list),
            title: const Text('Мои объявления'),
            onTap: () => Navigator.push(
                c, MaterialPageRoute(builder: (_) => FeedPage(admin: me['role'] == 'admin', mine: true))),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Настройки'),
            onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Выйти'), onTap: () => sb.auth.signOut()),
        ]),
      );
}

// ---------- Админ-панель ----------
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> users = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await sb.from('profiles').select().order('created_at', ascending: false).limit(300);
      if (mounted) setState(() => users = List<Map<String, dynamic>>.from(r));
    } catch (e) {
      if (mounted) toast(context, 'Ошибка: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text('Админ: пользователи (${users.length})')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  children: users.map((u) {
                    final isAdmin = u['role'] == 'admin';
                    final banned = u['is_banned'] == true;
                    return ListTile(
                      leading: Icon(banned ? Icons.block : Icons.person, color: banned ? Colors.red : null),
                      title: Text(u['name']),
                      subtitle: Text(isAdmin ? 'администратор' : (u['phone'] ?? 'без телефона')),
                      trailing: isAdmin
                          ? null
                          : TextButton(
                              onPressed: () async {
                                await sb.rpc('set_ban', params: {'target': u['id'], 'banned': !banned});
                                load();
                              },
                              child: Text(banned ? 'Разбанить' : 'Забанить'),
                            ),
                    );
                  }).toList(),
                ),
              ),
      );
}

// ---------- Настройки ----------
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> setTheme(ThemeMode v) async {
    themeMode.value = v;
    (await SharedPreferences.getInstance()).setInt('theme', v.index);
  }

  Future<void> deleteAccount(BuildContext c) async {
    if (!loggedIn) {
      toast(c, 'Вы не вошли в аккаунт');
      return;
    }
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text('Аккаунт и все ваши объявления будут удалены навсегда.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.rpc('delete_me');
      await sb.auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      if (c.mounted) toast(c, 'Ошибка: $e');
    }
    if (c.mounted) Navigator.popUntil(c, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (_, m, __) => ListView(children: [
            const ListTile(title: Text('Тема оформления', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final t in [
              (ThemeMode.system, 'Как в системе', Icons.brightness_auto),
              (ThemeMode.light, 'Светлая', Icons.light_mode),
              (ThemeMode.dark, 'Тёмная', Icons.dark_mode),
            ])
              ListTile(
                leading: Icon(t.$3),
                title: Text(t.$2),
                trailing: m == t.$1 ? const Icon(Icons.check_circle, color: kBlue) : null,
                onTap: () => setTheme(t.$1),
              ),
            const Divider(),
            const ListTile(leading: Icon(Icons.support_agent), title: Text('Поддержка'), subtitle: Text('support@madan.app')),
            const ListTile(leading: Icon(Icons.info_outline), title: Text('О приложении'), subtitle: Text('MADAN 1.0.0')),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Удалить аккаунт', style: TextStyle(color: Colors.red)),
              onTap: () => deleteAccount(c),
            ),
          ]),
        ),
      );
}

// ---------- Заглушка для гостей ----------
class GuestPage extends StatelessWidget {
  final String title, text;
  final bool settings;
  const GuestPage({super.key, required this.title, required this.text, this.settings = false});

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 56, color: kBlue),
              const SizedBox(height: 14),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const AuthPage())),
                  child: const Text('Войти или зарегистрироваться'),
                ),
              ),
              if (settings)
                TextButton(
                  onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SettingsPage())),
                  child: const Text('Настройки'),
                ),
            ]),
          ),
        ),
      );
}
