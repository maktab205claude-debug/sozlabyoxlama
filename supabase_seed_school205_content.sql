-- ════════════════════════════════════════════════════════════════
-- SözLab — "205 Smart School" üçün REAL MƏZMUN (ilk doldurma)
-- ÖNCƏ supabase_update_school205.sql skriptini run edin, SONRA bunu.
-- Şəkillər school205/ qovluğundan (index.html ilə eyni qovluqda) istifadə edir —
-- deploy edərkən bu qovluğun da serverə yükləndiyinə əmin olun.
-- ════════════════════════════════════════════════════════════════

-- 1) MƏKTƏB HAQQINDA
update public.school_info set
  school_name = 'Bakı şəhəri R.İmanov adına 205 nömrəli tam orta məktəb',
  address     = 'Mətbuat 107, Binəqədi, Bakı, AZ1053',
  phone       = '(+994 12) 411-19-98',
  email       = '205mekteb@bakuedu.gov.az',
  cover_image_url = 'school205/ilk-zeng-2.jpg',
  about_text  = $$FƏXRİMİZ

Rövşən İmanov 1969-cu il iyunun 27-də Bakı şəhərində anadan olub. Hələ uşaqlıq illərindən vətənpərvər ruhda böyümüş və daim Vətəni qorumaq, onun keşiyində durmaq arzusu ilə yaşayıb. O, 1976-cı ildə 205 nömrəli orta məktəbin birinci sinfinə daxil olub. 1984-cü ildə səkkizillik orta təhsilini başa vurduqdan sonra 68 nömrəli texniki-peşə məktəbində ixtisas təhsili alıb. 1987-1989-cu illərdə ordu sıralarında hərbi xidməti uğurla başa vurub.

1991-ci ildə Xüsusi Polis Dəstəsinə daxil olan Rövşən Daşaltı, Kərkicahan, Şuşa, Goranboy və digər yaşayış məntəqələri ətrafında baş verən qanlı döyüşlərdə qəhrəmanlıq göstərib.

1992-ci il iyulun 22-də Ağdərədə düşmənin hücumunu dəf edərkən qəhrəmancasına şəhid olub.

Elə həmin il Rövşən Nadir oğlu İmanovun adı 205 nömrəli tam orta məktəbə verilib.

BU GÜN MƏKTƏBİMİZ

2025/2026-cı tədris ilində 45 sinifdə (2A–11D) 1270 şagird təhsil alır. Məktəb üzrə müvəffəqiyyət 98,5%, keyfiyyət göstəricisi isə 66,3%-dir. Həmin tədris ilində 139 məzunumuzdan 63 nəfəri ali təhsil müəssisələrinə qəbul olub, onlardan 4 nəfəri 600-dən yüksək bal toplayıb.$$
where id = 1;

-- ─────────────────────────────────────────────
-- 2) MÜƏLLİMLƏR / RƏHBƏRLİK
-- ─────────────────────────────────────────────
insert into public.school_teachers (full_name, subject, bio, sort_order) values
('Əliheydər Əlifli Elman', 'Direktor', '', 1),
('Aynur Ələsgərova Cavid', 'Təlim-tərbiyə işləri üzrə direktor müavini', '', 2),
('Vüsalə Rəcəbova Fərhad', 'Məktəbdənkənar və sinifdənxaric tərbiyə işi üzrə təşkilatçı', '', 3),
('Zilfi Zilfiyev Baxış', 'Direktorun təsərrüfat işləri üzrə müavini', '', 4),
('Emin Əliyev Telman', 'Çağırışaqədərki hazırlıq rəhbəri', '', 5),
('Zülfiyyə Məsimova Qənbər', 'Məktəb psixoloqu', '', 6),
('Aytən Məmmədova Səadət', 'Məktəb psixoloqu', '', 7),
('İlahə Babayeva Səadətdin', 'Kitabxana müdiri', '', 8),
('Rüxsarə Qocayeva Qahir', 'Uşaq birliyi rəhbəri', '', 9),
('Billurə Əliyeva', 'Tarix müəllimi', '', 10),
('Səbinə Əkbərova', 'Rus dili müəllimi', '', 11),
('Aydan Məlikova', 'İngilis dili müəllimi', '', 12)
on conflict do nothing;

-- ─────────────────────────────────────────────
-- 3) XƏBƏRLƏR
-- ─────────────────────────────────────────────
insert into public.school_news (title, body, image_url, created_at) values
(
  'Yeni tədris ilinə birlikdə və məqsədyönlü şəkildə!',
  $$Məktəb rəhbərliyi tərəfindən valideyn komitələrinin iştirakı ilə yeni tədris ilinə hazırlıqla bağlı görüş keçirilib. Görüşdə məktəbli formaları, davamiyyət və punktuallıq, nizam-intizam, eləcə də tədris prosesinin səmərəli təşkili ilə bağlı mühüm məsələlər müzakirə olunub.

Direktor Əliheydər Əlifli çıxışında məktəb-valideyn əməkdaşlığının şagird uğurundakı rolunu vurğulayıb, sağlam və nizamlı təhsil mühitinin yaradılmasının prioritet olduğunu qeyd edib.

Təlim-tərbiyə işləri üzrə direktor müavini Aynur Ələsgərova isə tədrisin keyfiyyətinin yüksəldilməsi, şagird nailiyyətlərinin artırılması və təhsil nəticələrinin yaxşılaşdırılması istiqamətində vacib məsələlərə toxunub.$$,
  'school205/valideyn-yiginciagi.jpg', now() - interval '2 days'
),
(
  'Məktəbə ilk addım – sevgi, anlayış və dəstək!',
  $$Məktəbimizin psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideyn iclasında iştirak edərək psixoprofilaktik söhbət aparıb.

Şagirdlərin məktəbə uğurlu adaptasiyasını dəstəkləmək məqsədilə valideynlərə tövsiyələr verilib: uşağa qarşı səbirli və anlayışlı olmaq, məktəb və müəllim haqqında pozitiv fikir formalaşdırmaq, uşağı digər şagirdlərlə müqayisə etməmək, onun narahatlıqlarını dinləmək, dərs-istirahət rejiminə diqqət yetirmək və kiçik uğurlarını belə təqdir etmək.$$,
  'school205/ilk-zeng-1.jpg', now() - interval '3 days'
),
(
  'Məktəbin uğurlu nəticələri',
  $$2025/2026-cı tədris ilində 139 məzunumuz qəbul imtahanında iştirak edib. Onlardan 63 nəfəri ali təhsil müəssisələrinə qəbul olub. 4 məzunumuz 600-dən yüksək bal toplayıb! Ümumi qəbul göstəricisi — 45,3%.

Məzunlarımızı və müəllimlərimizi bu uğur münasibətilə təbrik edirik!$$,
  'school205/qebul-hesabati.jpg', now() - interval '5 days'
),
(
  'Paytaxt təhsil işçilərinin sentyabr konfransına start verilib',
  $$Bakı şəhərindəki ümumi təhsil və məktəbdənkənar təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən konfrans Dövlət Himninin səsləndirilməsi və şəhidlərimizin xatirəsinin bir dəqiqəlik sükutla yad edilməsi ilə başlayıb.

Konfransda yeni tədris ilində ümumi təhsilin keyfiyyətinin yüksəldilməsi, qabaqcıl pedaqoji təcrübələrin yayılması, rəqəmsal və innovativ yanaşmaların tətbiqinin genişləndirilməsi, istedadlı şagirdlərin dəstəklənməsi və məktəb-valideyn əməkdaşlığının möhkəmləndirilməsi əsas prioritetlər kimi vurğulanıb.$$,
  'school205/muellim-konfransi.jpg', now() - interval '10 days'
),
(
  'IX sinif buraxılış imtahanı nəticələrinin təhlili',
  $$IX sinif buraxılış imtahanının nəticələri təhlil olunub. Son üç ilin müqayisəsi göstərir ki, məktəbimiz 2024-cü illə müqayisədə irəliləyiş əldə etsə də, 2025-ci ilin nəticələri ilə müqayisədə geriləmə müşahidə olunub. Növbəti tədris ilində təkmilləşdirilmiş iş prinsipi və komanda əməkdaşlığı ilə nəticələrimizi daha da yaxşılaşdırmaq üçün əzmlə çalışacağıq.$$,
  'school205/mutda-hesabat.jpg', now() - interval '14 days'
),
(
  '2025/2026-cı tədris ilinin təlim nəticələrinin illik hesabatı təqdim olundu',
  $$2025/2026-cı tədris ili üzrə 2A–11D siniflərinin təlim nəticələrinin geniş təhlili başa çatdırılmışdır. Hesabatda məktəb üzrə müvəffəqiyyət və keyfiyyət göstəriciləri, fənlər üzrə orta bal nəticələri, əla/yaxşı/kafi/qeyri-kafi qiymətlərin sayı əks olunub.

Təhlil göstərir ki, buraxılış fənləri arasında ən yüksək nəticə Azərbaycan dili, ən aşağı nəticə isə riyaziyyat fənni üzrə qeydə alınmışdır. 2026/2027-ci tədris ili üzrə Fəaliyyət Planı hazırlanacaq.$$,
  'school205/hesabat-2025-2026.jpg', now() - interval '16 days'
),
(
  'Əməyə verilən yüksək qiymət!',
  $$Məktəbimizin bir qrup kişi müəllimi və əməkdaşı 26 İyun – Azərbaycan Respublikasının Silahlı Qüvvələri Günü münasibətilə, digər bir qrup müəllimi isə "50 illik yubiley"ləri münasibətilə Elm və Təhsil İşçiləri Həmkarlar İttifaqı Binəqədi Rayon Komitəsi tərəfindən təltif olunublar.

Təltif olunan bütün əməkdaşlarımızı ürəkdən təbrik edir, onlara gələcək fəaliyyətlərində yeni-yeni uğurlar arzulayırıq!$$,
  'school205/teltif-merasimi-a.jpg', now() - interval '20 days'
),
(
  'Aprel Şəhidlərinin Xatirəsinə həsr olunmuş görüş',
  $$Məktəbin tarix müəllimi Billurə Əliyeva və "Kiçik Akademiya" üzvlərinin birgə təşkilatçılığı ilə "Aprel faciəsi" mövzusuna həsr olunmuş görüş keçirilib. Görüşdə Dövlət Himni səsləndirilib, şəhidlərimizin əziz xatirəsi bir dəqiqəlik sükutla yad edilib, şagirdlərin hazırladığı videoçarxlar nümayiş olunub.$$,
  'school205/tarix-ders-aprel.jpg', now() - interval '25 days'
)
on conflict do nothing;

-- ─────────────────────────────────────────────
-- 4) NAİLİYYƏTLƏR
-- ─────────────────────────────────────────────
insert into public.school_achievements (title, description, image_url, achieved_on) values
(
  'Olimpiada qalibləri',
  $$Məhəmməd Teymurlu (Riyaziyyat), İbrahim Məmmədov (Riyaziyyat), Rəvan Ağayev (Coğrafiya), Ceyhun Qarayev (Riyaziyyat), Şövqü Hüseynov (Azərbaycan dili), Emilya Əhmədzadə (Riyaziyyat), Raul Məmmədov (Riyaziyyat) və Nigar Hüseynli (Azərbaycan dili) müxtəlif fənn olimpiadalarında məktəbimizi uğurla təmsil ediblər.$$,
  'school205/olimpiada-qalibleri.png', '2026-01-15'
),
(
  '4 məzunumuz 600-dən yüksək bal topladı',
  $$Əzimova Çınara Vüqar — 624,5 bal, Bakı Dövlət Universiteti Hüquq fakültəsi. Hüseynli Sadiq Elşən — 602 bal, Bakı Dövlət Universiteti İctimai münasibətlər. Sadıxzada Arzu Sadıx — 602 bal, Qarabağ Universiteti Hüquq fakültəsi. Hümbətova Fidan Mərdan — 600 bal, Azərbaycan Tibb Universiteti Müalicə işi.$$,
  'school205/qebul-hesabati.jpg', '2026-07-01'
),
(
  '"Birlik" Uşaq Musiqi və Rəqs Festivalı',
  $$VD sinif şagirdi Babayeva Səma Azərbaycan Uşaq Fondu tərəfindən təşkil olunan "Birlik" Uşaq Musiqi və Rəqs Festivalı layihəsinin seçim turunda uğurla çıxış edərək yüksək nəticə əldə etmişdir və fəxri fərmanla təltif olunmuşdur.$$,
  '', '2026-02-01'
),
(
  'KİNQS Beynəlxalq məktəb olimpiadası — qızıl medal',
  $$4Ç sinif şagirdi Səyavuş Bağırzadə KİNQS Beynəlxalq məktəb olimpiadasının payız liqasında iştirak edərək qızıl medal qazanıb.$$,
  '', '2025-11-01'
),
(
  'Pifaqor Riyaziyyat Olimpiadası — gümüş medal',
  $$IV sinif şagirdləri Bağırzadə Səyavuş və Məsimov Rizvan Beyin Olimpiada Mərkəzi tərəfindən 27.12.2025-ci il tarixində keçirilən Pifaqor Riyaziyyat Olimpiadasında gümüş medal qazanıblar.$$,
  '', '2025-12-27'
),
(
  'Kunq-Fu sanda Azərbaycan birinciliyi — I yer',
  $$VI sinif şagirdi Seyidzadə Sahib "Kunq-Fu" sanda üzrə Azərbaycan birinciliyi 42 kq çəki dərəcəsində I yerə layiq görülüb.$$,
  '', '2026-03-01'
),
(
  '"Legion Döyüş Liqası" — I yer',
  $$IX sinif şagirdi Əlistanova Nəzrin MMA və Grappling idman növləri üzrə Ümummilli Lider Heydər Əliyevin xatirəsinə həsr olunmuş "Legion Döyüş Liqası" turnirində I yerə layiq görülüb.$$,
  '', '2026-03-15'
),
(
  'SASMO Olimpiadası — gümüş medal',
  $$5D sinif şagirdi Məmmədzadə Fatimə SASMO olimpiadasından 2-ci yer, gümüş medal qazanmışdır.$$,
  '', '2026-02-15'
)
on conflict do nothing;

-- ─────────────────────────────────────────────
-- 5) TƏDBİRLƏR
-- ─────────────────────────────────────────────
insert into public.school_events (title, description, event_date, image_url) values
(
  'Yeni tədris ilinə hazırlıq görüşü',
  'Valideyn komitələri ilə birgə keçirilən görüşdə məktəbli formaları, davamiyyət, nizam-intizam və tədris prosesinin təşkili müzakirə olunub.',
  current_date - 2, 'school205/valideyn-yiginciagi.jpg'
),
(
  'I sinif valideyn iclası — psixoprofilaktik söhbət',
  'Məktəb psixoloqu Aytən Məmmədova I sinif şagirdlərinin valideynləri ilə uşağın məktəbə uğurlu adaptasiyası mövzusunda görüş keçirib.',
  current_date - 3, 'school205/ilk-zeng-1.jpg'
),
(
  'Paytaxt təhsil işçilərinin sentyabr konfransı',
  'Bakı üzrə ümumi təhsil müəssisələri rəhbərlərinin iştirakı ilə keçirilən illik konfrans.',
  current_date - 10, 'school205/muellim-konfransi.jpg'
),
(
  'Əməyə verilən yüksək qiymət — təltif mərasimi',
  'Silahlı Qüvvələr Günü və 50 illik yubiley münasibətilə əməkdaşların təltifi.',
  current_date - 20, 'school205/teltif-merasimi-a.jpg'
),
(
  'Aprel faciəsinə həsr olunmuş anım tədbiri',
  '"Kiçik Akademiya" üzvlərinin təşkilatçılığı ilə keçirilən tarix dərsi və video nümayişi.',
  current_date - 25, 'school205/tarix-ders-aprel.jpg'
)
on conflict do nothing;
