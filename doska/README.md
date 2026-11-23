# MADAN — запуск
1. Supabase: SQL Editor -> выполнить supabase.sql, supabase_web.sql, supabase_v2.sql. Authentication -> Email -> выключить "Confirm email".
2. Вставить URL и anon key в src/lib/main.dart и в madan-site/index.html.
3. Загрузить папку на GitHub (с папкой .github). Actions -> Build APK -> Run workflow.
4. После сборки APK лежит в Releases -> "MADAN (последняя версия)" -> madan.apk. Ссылка постоянная:
   https://github.com/ЛОГИН/РЕПОЗИТОРИЙ/releases/download/latest/madan.apk
5. В madan-site/index.html в строке APK_URL вставить эту ссылку (или положить madan.apk рядом с index.html).
6. Сайт: перетащить папку madan-site на netlify.com.
7. Админ: зарегистрироваться по номеру, затем в SQL Editor:
   update public.profiles set role='admin' where phone='+7ВАШ_НОМЕР';
