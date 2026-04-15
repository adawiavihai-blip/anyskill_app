// ═══════════════════════════════════════════════════════════════════════════
// World countries + cities dataset (v12.11.3)
//
// • [kWorldCountries] — ~250 countries with flag + Hebrew + English names +
//   ISO-3166 alpha-2 code. Used by the provider-registration country picker.
// • [kCitiesByCountryCode] — curated list of ~30 major cities per country,
//   for the cascading city dropdown. Countries NOT in this map fall back to
//   a free-text input.
// • Israel ships with 200+ cities. Other top source-markets ship with top
//   ~30 cities each (US, UK, France, Germany, Russia, Ukraine, Brazil,
//   India, UAE, Canada, Australia, Egypt, Jordan, Turkey, Spain, Italy).
// ═══════════════════════════════════════════════════════════════════════════

class CountryEntry {
  final String code;     // ISO-3166 alpha-2, e.g. 'IL', 'US'
  final String flag;     // emoji flag, e.g. '🇮🇱'
  final String nameHe;
  final String nameEn;
  const CountryEntry(this.code, this.flag, this.nameHe, this.nameEn);
}

const List<CountryEntry> kWorldCountries = [
  CountryEntry('IL', '🇮🇱', 'ישראל', 'Israel'),
  CountryEntry('US', '🇺🇸', 'ארצות הברית', 'United States'),
  CountryEntry('GB', '🇬🇧', 'בריטניה', 'United Kingdom'),
  CountryEntry('FR', '🇫🇷', 'צרפת', 'France'),
  CountryEntry('DE', '🇩🇪', 'גרמניה', 'Germany'),
  CountryEntry('ES', '🇪🇸', 'ספרד', 'Spain'),
  CountryEntry('IT', '🇮🇹', 'איטליה', 'Italy'),
  CountryEntry('CA', '🇨🇦', 'קנדה', 'Canada'),
  CountryEntry('AU', '🇦🇺', 'אוסטרליה', 'Australia'),
  CountryEntry('RU', '🇷🇺', 'רוסיה', 'Russia'),
  CountryEntry('UA', '🇺🇦', 'אוקראינה', 'Ukraine'),
  CountryEntry('BR', '🇧🇷', 'ברזיל', 'Brazil'),
  CountryEntry('AR', '🇦🇷', 'ארגנטינה', 'Argentina'),
  CountryEntry('MX', '🇲🇽', 'מקסיקו', 'Mexico'),
  CountryEntry('IN', '🇮🇳', 'הודו', 'India'),
  CountryEntry('CN', '🇨🇳', 'סין', 'China'),
  CountryEntry('JP', '🇯🇵', 'יפן', 'Japan'),
  CountryEntry('KR', '🇰🇷', 'דרום קוריאה', 'South Korea'),
  CountryEntry('AE', '🇦🇪', 'איחוד האמירויות', 'United Arab Emirates'),
  CountryEntry('SA', '🇸🇦', 'ערב הסעודית', 'Saudi Arabia'),
  CountryEntry('EG', '🇪🇬', 'מצרים', 'Egypt'),
  CountryEntry('JO', '🇯🇴', 'ירדן', 'Jordan'),
  CountryEntry('TR', '🇹🇷', 'טורקיה', 'Turkey'),
  CountryEntry('GR', '🇬🇷', 'יוון', 'Greece'),
  CountryEntry('CY', '🇨🇾', 'קפריסין', 'Cyprus'),
  CountryEntry('NL', '🇳🇱', 'הולנד', 'Netherlands'),
  CountryEntry('BE', '🇧🇪', 'בלגיה', 'Belgium'),
  CountryEntry('CH', '🇨🇭', 'שווייץ', 'Switzerland'),
  CountryEntry('AT', '🇦🇹', 'אוסטריה', 'Austria'),
  CountryEntry('SE', '🇸🇪', 'שוודיה', 'Sweden'),
  CountryEntry('NO', '🇳🇴', 'נורווגיה', 'Norway'),
  CountryEntry('DK', '🇩🇰', 'דנמרק', 'Denmark'),
  CountryEntry('FI', '🇫🇮', 'פינלנד', 'Finland'),
  CountryEntry('IS', '🇮🇸', 'איסלנד', 'Iceland'),
  CountryEntry('IE', '🇮🇪', 'אירלנד', 'Ireland'),
  CountryEntry('PT', '🇵🇹', 'פורטוגל', 'Portugal'),
  CountryEntry('PL', '🇵🇱', 'פולין', 'Poland'),
  CountryEntry('CZ', '🇨🇿', 'צ\'כיה', 'Czech Republic'),
  CountryEntry('SK', '🇸🇰', 'סלובקיה', 'Slovakia'),
  CountryEntry('HU', '🇭🇺', 'הונגריה', 'Hungary'),
  CountryEntry('RO', '🇷🇴', 'רומניה', 'Romania'),
  CountryEntry('BG', '🇧🇬', 'בולגריה', 'Bulgaria'),
  CountryEntry('HR', '🇭🇷', 'קרואטיה', 'Croatia'),
  CountryEntry('RS', '🇷🇸', 'סרביה', 'Serbia'),
  CountryEntry('SI', '🇸🇮', 'סלובניה', 'Slovenia'),
  CountryEntry('BA', '🇧🇦', 'בוסניה והרצגובינה', 'Bosnia and Herzegovina'),
  CountryEntry('MK', '🇲🇰', 'צפון מקדוניה', 'North Macedonia'),
  CountryEntry('AL', '🇦🇱', 'אלבניה', 'Albania'),
  CountryEntry('XK', '🇽🇰', 'קוסובו', 'Kosovo'),
  CountryEntry('MT', '🇲🇹', 'מלטה', 'Malta'),
  CountryEntry('LU', '🇱🇺', 'לוקסמבורג', 'Luxembourg'),
  CountryEntry('MC', '🇲🇨', 'מונקו', 'Monaco'),
  CountryEntry('LI', '🇱🇮', 'ליכטנשטיין', 'Liechtenstein'),
  CountryEntry('AD', '🇦🇩', 'אנדורה', 'Andorra'),
  CountryEntry('SM', '🇸🇲', 'סן מרינו', 'San Marino'),
  CountryEntry('VA', '🇻🇦', 'ותיקן', 'Vatican City'),
  CountryEntry('EE', '🇪🇪', 'אסטוניה', 'Estonia'),
  CountryEntry('LV', '🇱🇻', 'לטביה', 'Latvia'),
  CountryEntry('LT', '🇱🇹', 'ליטא', 'Lithuania'),
  CountryEntry('BY', '🇧🇾', 'בלארוס', 'Belarus'),
  CountryEntry('MD', '🇲🇩', 'מולדובה', 'Moldova'),
  CountryEntry('GE', '🇬🇪', 'גאורגיה', 'Georgia'),
  CountryEntry('AM', '🇦🇲', 'ארמניה', 'Armenia'),
  CountryEntry('AZ', '🇦🇿', 'אזרבייג\'ן', 'Azerbaijan'),
  CountryEntry('KZ', '🇰🇿', 'קזחסטן', 'Kazakhstan'),
  CountryEntry('UZ', '🇺🇿', 'אוזבקיסטן', 'Uzbekistan'),
  CountryEntry('KG', '🇰🇬', 'קירגיזסטן', 'Kyrgyzstan'),
  CountryEntry('TJ', '🇹🇯', 'טג\'יקיסטן', 'Tajikistan'),
  CountryEntry('TM', '🇹🇲', 'טורקמניסטן', 'Turkmenistan'),
  CountryEntry('IR', '🇮🇷', 'איראן', 'Iran'),
  CountryEntry('IQ', '🇮🇶', 'עיראק', 'Iraq'),
  CountryEntry('SY', '🇸🇾', 'סוריה', 'Syria'),
  CountryEntry('LB', '🇱🇧', 'לבנון', 'Lebanon'),
  CountryEntry('PS', '🇵🇸', 'פלסטין', 'Palestine'),
  CountryEntry('KW', '🇰🇼', 'כווית', 'Kuwait'),
  CountryEntry('BH', '🇧🇭', 'בחריין', 'Bahrain'),
  CountryEntry('QA', '🇶🇦', 'קטר', 'Qatar'),
  CountryEntry('OM', '🇴🇲', 'עומאן', 'Oman'),
  CountryEntry('YE', '🇾🇪', 'תימן', 'Yemen'),
  CountryEntry('AF', '🇦🇫', 'אפגניסטן', 'Afghanistan'),
  CountryEntry('PK', '🇵🇰', 'פקיסטן', 'Pakistan'),
  CountryEntry('BD', '🇧🇩', 'בנגלדש', 'Bangladesh'),
  CountryEntry('LK', '🇱🇰', 'סרי לנקה', 'Sri Lanka'),
  CountryEntry('NP', '🇳🇵', 'נפאל', 'Nepal'),
  CountryEntry('BT', '🇧🇹', 'בהוטן', 'Bhutan'),
  CountryEntry('MV', '🇲🇻', 'מלדיביים', 'Maldives'),
  CountryEntry('MM', '🇲🇲', 'מיאנמר', 'Myanmar'),
  CountryEntry('TH', '🇹🇭', 'תאילנד', 'Thailand'),
  CountryEntry('LA', '🇱🇦', 'לאוס', 'Laos'),
  CountryEntry('KH', '🇰🇭', 'קמבודיה', 'Cambodia'),
  CountryEntry('VN', '🇻🇳', 'וייטנאם', 'Vietnam'),
  CountryEntry('MY', '🇲🇾', 'מלזיה', 'Malaysia'),
  CountryEntry('SG', '🇸🇬', 'סינגפור', 'Singapore'),
  CountryEntry('ID', '🇮🇩', 'אינדונזיה', 'Indonesia'),
  CountryEntry('PH', '🇵🇭', 'פיליפינים', 'Philippines'),
  CountryEntry('BN', '🇧🇳', 'ברוניי', 'Brunei'),
  CountryEntry('TL', '🇹🇱', 'מזרח טימור', 'Timor-Leste'),
  CountryEntry('MN', '🇲🇳', 'מונגוליה', 'Mongolia'),
  CountryEntry('TW', '🇹🇼', 'טייוואן', 'Taiwan'),
  CountryEntry('HK', '🇭🇰', 'הונג קונג', 'Hong Kong'),
  CountryEntry('MO', '🇲🇴', 'מקאו', 'Macau'),
  CountryEntry('KP', '🇰🇵', 'צפון קוריאה', 'North Korea'),
  CountryEntry('NZ', '🇳🇿', 'ניו זילנד', 'New Zealand'),
  CountryEntry('FJ', '🇫🇯', 'פיג\'י', 'Fiji'),
  CountryEntry('PG', '🇵🇬', 'פפואה גינאה החדשה', 'Papua New Guinea'),
  CountryEntry('SB', '🇸🇧', 'איי שלמה', 'Solomon Islands'),
  CountryEntry('VU', '🇻🇺', 'ונואטו', 'Vanuatu'),
  CountryEntry('WS', '🇼🇸', 'סמואה', 'Samoa'),
  CountryEntry('TO', '🇹🇴', 'טונגה', 'Tonga'),
  CountryEntry('KI', '🇰🇮', 'קיריבטי', 'Kiribati'),
  CountryEntry('MA', '🇲🇦', 'מרוקו', 'Morocco'),
  CountryEntry('DZ', '🇩🇿', 'אלג\'יריה', 'Algeria'),
  CountryEntry('TN', '🇹🇳', 'תוניסיה', 'Tunisia'),
  CountryEntry('LY', '🇱🇾', 'לוב', 'Libya'),
  CountryEntry('SD', '🇸🇩', 'סודן', 'Sudan'),
  CountryEntry('SS', '🇸🇸', 'דרום סודן', 'South Sudan'),
  CountryEntry('ET', '🇪🇹', 'אתיופיה', 'Ethiopia'),
  CountryEntry('ER', '🇪🇷', 'אריתריאה', 'Eritrea'),
  CountryEntry('DJ', '🇩🇯', 'ג\'יבוטי', 'Djibouti'),
  CountryEntry('SO', '🇸🇴', 'סומליה', 'Somalia'),
  CountryEntry('KE', '🇰🇪', 'קניה', 'Kenya'),
  CountryEntry('UG', '🇺🇬', 'אוגנדה', 'Uganda'),
  CountryEntry('TZ', '🇹🇿', 'טנזניה', 'Tanzania'),
  CountryEntry('RW', '🇷🇼', 'רואנדה', 'Rwanda'),
  CountryEntry('BI', '🇧🇮', 'בורונדי', 'Burundi'),
  CountryEntry('CD', '🇨🇩', 'קונגו (DRC)', 'DR Congo'),
  CountryEntry('CG', '🇨🇬', 'קונגו', 'Republic of the Congo'),
  CountryEntry('CF', '🇨🇫', 'רפובליקה מרכז-אפריקאית', 'Central African Republic'),
  CountryEntry('TD', '🇹🇩', 'צ\'אד', 'Chad'),
  CountryEntry('CM', '🇨🇲', 'קמרון', 'Cameroon'),
  CountryEntry('GQ', '🇬🇶', 'גינאה המשוונית', 'Equatorial Guinea'),
  CountryEntry('GA', '🇬🇦', 'גבון', 'Gabon'),
  CountryEntry('NG', '🇳🇬', 'ניגריה', 'Nigeria'),
  CountryEntry('NE', '🇳🇪', 'ניז\'ר', 'Niger'),
  CountryEntry('ML', '🇲🇱', 'מאלי', 'Mali'),
  CountryEntry('BF', '🇧🇫', 'בורקינה פאסו', 'Burkina Faso'),
  CountryEntry('SN', '🇸🇳', 'סנגל', 'Senegal'),
  CountryEntry('GM', '🇬🇲', 'גמביה', 'Gambia'),
  CountryEntry('GW', '🇬🇼', 'גינאה-ביסאו', 'Guinea-Bissau'),
  CountryEntry('GN', '🇬🇳', 'גינאה', 'Guinea'),
  CountryEntry('SL', '🇸🇱', 'סיירה לאונה', 'Sierra Leone'),
  CountryEntry('LR', '🇱🇷', 'ליבריה', 'Liberia'),
  CountryEntry('CI', '🇨🇮', 'חוף השנהב', 'Ivory Coast'),
  CountryEntry('GH', '🇬🇭', 'גאנה', 'Ghana'),
  CountryEntry('TG', '🇹🇬', 'טוגו', 'Togo'),
  CountryEntry('BJ', '🇧🇯', 'בנין', 'Benin'),
  CountryEntry('MR', '🇲🇷', 'מאוריטניה', 'Mauritania'),
  CountryEntry('CV', '🇨🇻', 'כף ורדה', 'Cape Verde'),
  CountryEntry('ST', '🇸🇹', 'סאו טומה ופרינסיפה', 'São Tomé and Príncipe'),
  CountryEntry('AO', '🇦🇴', 'אנגולה', 'Angola'),
  CountryEntry('NA', '🇳🇦', 'נמיביה', 'Namibia'),
  CountryEntry('ZM', '🇿🇲', 'זמביה', 'Zambia'),
  CountryEntry('ZW', '🇿🇼', 'זימבבואה', 'Zimbabwe'),
  CountryEntry('BW', '🇧🇼', 'בוטסואנה', 'Botswana'),
  CountryEntry('SZ', '🇸🇿', 'אסוואטיני', 'Eswatini'),
  CountryEntry('LS', '🇱🇸', 'לסוטו', 'Lesotho'),
  CountryEntry('MW', '🇲🇼', 'מלאווי', 'Malawi'),
  CountryEntry('MZ', '🇲🇿', 'מוזמביק', 'Mozambique'),
  CountryEntry('MG', '🇲🇬', 'מדגסקר', 'Madagascar'),
  CountryEntry('MU', '🇲🇺', 'מאוריציוס', 'Mauritius'),
  CountryEntry('SC', '🇸🇨', 'סיישל', 'Seychelles'),
  CountryEntry('KM', '🇰🇲', 'קומורו', 'Comoros'),
  CountryEntry('ZA', '🇿🇦', 'דרום אפריקה', 'South Africa'),
  CountryEntry('CL', '🇨🇱', 'צ\'ילה', 'Chile'),
  CountryEntry('PE', '🇵🇪', 'פרו', 'Peru'),
  CountryEntry('CO', '🇨🇴', 'קולומביה', 'Colombia'),
  CountryEntry('VE', '🇻🇪', 'ונצואלה', 'Venezuela'),
  CountryEntry('EC', '🇪🇨', 'אקוודור', 'Ecuador'),
  CountryEntry('BO', '🇧🇴', 'בוליביה', 'Bolivia'),
  CountryEntry('PY', '🇵🇾', 'פרגוואי', 'Paraguay'),
  CountryEntry('UY', '🇺🇾', 'אורוגוואי', 'Uruguay'),
  CountryEntry('GY', '🇬🇾', 'גיאנה', 'Guyana'),
  CountryEntry('SR', '🇸🇷', 'סורינאם', 'Suriname'),
  CountryEntry('GF', '🇬🇫', 'גיאנה הצרפתית', 'French Guiana'),
  CountryEntry('CR', '🇨🇷', 'קוסטה ריקה', 'Costa Rica'),
  CountryEntry('PA', '🇵🇦', 'פנמה', 'Panama'),
  CountryEntry('NI', '🇳🇮', 'ניקרגואה', 'Nicaragua'),
  CountryEntry('HN', '🇭🇳', 'הונדורס', 'Honduras'),
  CountryEntry('SV', '🇸🇻', 'אל סלבדור', 'El Salvador'),
  CountryEntry('GT', '🇬🇹', 'גואטמלה', 'Guatemala'),
  CountryEntry('BZ', '🇧🇿', 'בליז', 'Belize'),
  CountryEntry('CU', '🇨🇺', 'קובה', 'Cuba'),
  CountryEntry('DO', '🇩🇴', 'הרפובליקה הדומיניקנית', 'Dominican Republic'),
  CountryEntry('HT', '🇭🇹', 'האיטי', 'Haiti'),
  CountryEntry('JM', '🇯🇲', 'ג\'מייקה', 'Jamaica'),
  CountryEntry('PR', '🇵🇷', 'פוארטו ריקו', 'Puerto Rico'),
  CountryEntry('TT', '🇹🇹', 'טרינידד וטובגו', 'Trinidad and Tobago'),
  CountryEntry('BB', '🇧🇧', 'ברבדוס', 'Barbados'),
  CountryEntry('BS', '🇧🇸', 'איי בהאמה', 'Bahamas'),
  CountryEntry('AG', '🇦🇬', 'אנטיגואה וברבודה', 'Antigua and Barbuda'),
  CountryEntry('LC', '🇱🇨', 'סנט לוסיה', 'Saint Lucia'),
  CountryEntry('GD', '🇬🇩', 'גרנדה', 'Grenada'),
  CountryEntry('DM', '🇩🇲', 'דומיניקה', 'Dominica'),
  CountryEntry('KN', '🇰🇳', 'סנט קיטס ונוויס', 'Saint Kitts and Nevis'),
  CountryEntry('VC', '🇻🇨', 'סנט וינסנט והגרנדינים', 'Saint Vincent and the Grenadines'),
];

/// Map of country code → comprehensive city list. Countries not in this map
/// should render a free-text city input on the client.
const Map<String, List<String>> kCitiesByCountryCode = {
  'IL': _kCitiesIL,
  'US': _kCitiesUS,
  'GB': _kCitiesGB,
  'FR': _kCitiesFR,
  'DE': _kCitiesDE,
  'IT': _kCitiesIT,
  'ES': _kCitiesES,
  'CA': _kCitiesCA,
  'AU': _kCitiesAU,
  'RU': _kCitiesRU,
  'UA': _kCitiesUA,
  'BR': _kCitiesBR,
  'IN': _kCitiesIN,
  'AE': _kCitiesAE,
  'EG': _kCitiesEG,
  'JO': _kCitiesJO,
  'TR': _kCitiesTR,
  'GR': _kCitiesGR,
  'NL': _kCitiesNL,
  'BE': _kCitiesBE,
  'PL': _kCitiesPL,
  'RO': _kCitiesRO,
  'MA': _kCitiesMA,
  'ZA': _kCitiesZA,
  'MX': _kCitiesMX,
  'AR': _kCitiesAR,
  'CN': _kCitiesCN,
  'JP': _kCitiesJP,
  'KR': _kCitiesKR,
  'TH': _kCitiesTH,
  'SG': _kCitiesSG,
};

// ── Israel (comprehensive — ~200) ───────────────────────────────────────────
const List<String> _kCitiesIL = [
  'ירושלים', 'תל אביב - יפו', 'חיפה', 'ראשון לציון', 'פתח תקווה',
  'אשדוד', 'נתניה', 'באר שבע', 'בני ברק', 'חולון',
  'רמת גן', 'אשקלון', 'רחובות', 'בת ים', 'בית שמש',
  'כפר סבא', 'הרצליה', 'חדרה', 'מודיעין-מכבים-רעות', 'נצרת',
  'לוד', 'רמלה', 'רעננה', 'מודיעין עילית', 'רהט',
  'נהריה', 'קריית גת', 'הוד השרון', 'גבעתיים', 'קריית אתא',
  'אום אל-פחם', 'אילת', 'ראש העין', 'קריית אונו', 'עפולה',
  'נס ציונה', 'אור יהודה', 'אכסאל', 'טבריה', 'טירה',
  'דימונה', 'קריית ים', 'קריית מוצקין', 'קריית ביאליק', 'יהוד-מונוסון',
  'טייבה', 'באקה אל-גרבייה', 'שפרעם', 'ערד', 'מגדל העמק',
  'יבנה', 'קריית מלאכי', 'צפת', 'סחנין', 'נוף הגליל',
  'אור עקיבא', 'טמרה', 'כרמיאל', 'מעלות-תרשיחא', 'קריית שמונה',
  'נצרת עילית', 'קלנסווה', 'עראבה', 'עכו', 'מצפה רמון',
  'זכרון יעקב', 'כפר קאסם', 'פרדס חנה-כרכור', 'גני תקווה', 'קדימה-צורן',
  'בית שאן', 'יקנעם עילית', 'מעלה אדומים', 'ביתר עילית', 'אריאל',
  'אלעד', 'גבעת שמואל', 'קצרין', 'בנימינה-גבעת עדה', 'תל מונד',
  'עתלית', 'זמר', 'אבו גוש', 'מזכרת בתיה', 'שלומי',
  'מגאר', 'ג\'דיידה-מכר', 'טובא-זנגרייה', 'יסוד המעלה', 'חצור הגלילית',
  'חורה', 'תל שבע', 'כסיפה', 'ירוחם', 'אופקים',
  'נתיבות', 'שדרות', 'רמת ישי', 'רמת השרון', 'סביון',
  'כפר יונה', 'גדרה', 'אור עקיבא', 'בית דגן', 'בית חנניה',
  'גן יבנה', 'אבן יהודה', 'פרדסיה', 'עמנואל', 'מבשרת ציון',
  'פסגות', 'אפרת', 'קרני שומרון', 'אלפי מנשה', 'אורנית',
  'מעלה אפרים', 'עומר', 'להבים', 'מיתר', 'גן נר',
  'כפר ורדים', 'שוהם', 'כפר ברא', 'ג\'לג\'וליה', 'רמת ישי',
  'שלומי', 'מטולה', 'עין טל', 'כוכב יאיר', 'גבעת זאב',
  'בית אל', 'כוכב השחר', 'עלי', 'קריית ארבע', 'עתניאל',
  'הר חברון', 'קדומים', 'אורנית', 'חשמונאים', 'מנחמיה',
  'ראש פינה', 'עין מחיל', 'ביר אל-מכסור', 'בענה', 'דייר אל-אסד',
  'כעביה-טבאש-חג\'אג\'רה', 'ג\'ת', 'עראבה', 'עיילוט', 'דבוריה',
  'כפר כנא', 'אילוט', 'רינה', 'אעבלין', 'טורעאן',
  'סאג\'ור', 'עין מאהל', 'ראמה', 'יאנוח-ג\'ת', 'דיר חנא',
  'מג\'ד אל-כרום', 'נחף', 'דאלית אל-כרמל', 'עוספיה', 'יפיע',
  'משהד', 'כפר מנדא', 'כאבול', 'שבלי - אום אל-גנם', 'ביר אל-סיכה',
  'ג\'סר א-זרקא', 'פוריידיס', 'כפר ברא', 'ג\'ת', 'מעיליא',
  'פקיעין', 'חורפיש', 'ג\'וליס', 'ירכא', 'כסרא-סמיע',
];

// ── United States (top 50) ──────────────────────────────────────────────────
const List<String> _kCitiesUS = [
  'New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix',
  'Philadelphia', 'San Antonio', 'San Diego', 'Dallas', 'Austin',
  'Jacksonville', 'Fort Worth', 'Columbus', 'Charlotte', 'San Francisco',
  'Indianapolis', 'Seattle', 'Denver', 'Washington', 'Boston',
  'El Paso', 'Nashville', 'Detroit', 'Oklahoma City', 'Portland',
  'Las Vegas', 'Memphis', 'Louisville', 'Baltimore', 'Milwaukee',
  'Albuquerque', 'Tucson', 'Fresno', 'Sacramento', 'Kansas City',
  'Mesa', 'Atlanta', 'Omaha', 'Colorado Springs', 'Raleigh',
  'Miami', 'Long Beach', 'Virginia Beach', 'Oakland', 'Minneapolis',
  'Tulsa', 'Arlington', 'Tampa', 'New Orleans', 'Wichita',
];

// ── United Kingdom ──────────────────────────────────────────────────────────
const List<String> _kCitiesGB = [
  'London', 'Birmingham', 'Manchester', 'Glasgow', 'Liverpool',
  'Leeds', 'Sheffield', 'Edinburgh', 'Bristol', 'Cardiff',
  'Leicester', 'Coventry', 'Belfast', 'Nottingham', 'Newcastle upon Tyne',
  'Brighton', 'Kingston upon Hull', 'Plymouth', 'Stoke-on-Trent', 'Wolverhampton',
  'Derby', 'Southampton', 'Portsmouth', 'York', 'Aberdeen',
  'Swansea', 'Dundee', 'Oxford', 'Cambridge', 'Bath',
];

const List<String> _kCitiesFR = [
  'Paris', 'Marseille', 'Lyon', 'Toulouse', 'Nice',
  'Nantes', 'Strasbourg', 'Montpellier', 'Bordeaux', 'Lille',
  'Rennes', 'Reims', 'Le Havre', 'Saint-Étienne', 'Toulon',
  'Angers', 'Grenoble', 'Dijon', 'Nîmes', 'Aix-en-Provence',
  'Brest', 'Le Mans', 'Amiens', 'Tours', 'Limoges',
  'Clermont-Ferrand', 'Villeurbanne', 'Besançon', 'Orléans', 'Metz',
];

const List<String> _kCitiesDE = [
  'Berlin', 'Hamburg', 'München', 'Köln', 'Frankfurt am Main',
  'Stuttgart', 'Düsseldorf', 'Leipzig', 'Dortmund', 'Essen',
  'Bremen', 'Dresden', 'Hannover', 'Nürnberg', 'Duisburg',
  'Bochum', 'Wuppertal', 'Bielefeld', 'Bonn', 'Münster',
  'Karlsruhe', 'Mannheim', 'Augsburg', 'Wiesbaden', 'Mönchengladbach',
  'Gelsenkirchen', 'Braunschweig', 'Kiel', 'Chemnitz', 'Aachen',
];

const List<String> _kCitiesIT = [
  'Roma', 'Milano', 'Napoli', 'Torino', 'Palermo',
  'Genova', 'Bologna', 'Firenze', 'Bari', 'Catania',
  'Venezia', 'Verona', 'Messina', 'Padova', 'Trieste',
  'Brescia', 'Parma', 'Taranto', 'Prato', 'Modena',
  'Reggio Calabria', 'Reggio Emilia', 'Perugia', 'Livorno', 'Ravenna',
  'Cagliari', 'Foggia', 'Rimini', 'Salerno', 'Ferrara',
];

const List<String> _kCitiesES = [
  'Madrid', 'Barcelona', 'Valencia', 'Sevilla', 'Zaragoza',
  'Málaga', 'Murcia', 'Palma', 'Las Palmas', 'Bilbao',
  'Alicante', 'Córdoba', 'Valladolid', 'Vigo', 'Gijón',
  'L\'Hospitalet de Llobregat', 'A Coruña', 'Granada', 'Vitoria-Gasteiz', 'Elche',
  'Oviedo', 'Santa Cruz de Tenerife', 'Badalona', 'Cartagena', 'Terrassa',
  'Jerez de la Frontera', 'Sabadell', 'Móstoles', 'Santander', 'Pamplona',
];

const List<String> _kCitiesCA = [
  'Toronto', 'Montreal', 'Vancouver', 'Calgary', 'Edmonton',
  'Ottawa', 'Winnipeg', 'Quebec City', 'Hamilton', 'Kitchener',
  'London', 'Victoria', 'Halifax', 'Oshawa', 'Windsor',
  'Saskatoon', 'St. Catharines', 'Regina', 'Sherbrooke', 'St. John\'s',
  'Barrie', 'Kelowna', 'Abbotsford', 'Kingston', 'Saguenay',
  'Trois-Rivières', 'Guelph', 'Moncton', 'Brantford', 'Saint John',
];

const List<String> _kCitiesAU = [
  'Sydney', 'Melbourne', 'Brisbane', 'Perth', 'Adelaide',
  'Gold Coast', 'Canberra', 'Newcastle', 'Central Coast', 'Wollongong',
  'Sunshine Coast', 'Geelong', 'Hobart', 'Townsville', 'Cairns',
  'Darwin', 'Toowoomba', 'Ballarat', 'Bendigo', 'Albury',
  'Launceston', 'Mackay', 'Rockhampton', 'Bunbury', 'Bundaberg',
];

const List<String> _kCitiesRU = [
  'Москва', 'Санкт-Петербург', 'Новосибирск', 'Екатеринбург', 'Казань',
  'Нижний Новгород', 'Челябинск', 'Самара', 'Омск', 'Ростов-на-Дону',
  'Уфа', 'Красноярск', 'Пермь', 'Воронеж', 'Волгоград',
  'Краснодар', 'Саратов', 'Тюмень', 'Тольятти', 'Ижевск',
  'Барнаул', 'Ульяновск', 'Иркутск', 'Хабаровск', 'Ярославль',
  'Владивосток', 'Махачкала', 'Томск', 'Оренбург', 'Кемерово',
];

const List<String> _kCitiesUA = [
  'Київ', 'Харків', 'Одеса', 'Дніпро', 'Донецьк',
  'Запоріжжя', 'Львів', 'Кривий Ріг', 'Миколаїв', 'Маріуполь',
  'Луганськ', 'Вінниця', 'Сімферополь', 'Херсон', 'Чернігів',
  'Полтава', 'Черкаси', 'Хмельницький', 'Житомир', 'Суми',
  'Рівне', 'Івано-Франківськ', 'Кам\'янське', 'Тернопіль', 'Кропивницький',
];

const List<String> _kCitiesBR = [
  'São Paulo', 'Rio de Janeiro', 'Brasília', 'Salvador', 'Fortaleza',
  'Belo Horizonte', 'Manaus', 'Curitiba', 'Recife', 'Porto Alegre',
  'Belém', 'Goiânia', 'Guarulhos', 'Campinas', 'São Luís',
  'São Gonçalo', 'Maceió', 'Duque de Caxias', 'Natal', 'Teresina',
  'Campo Grande', 'Nova Iguaçu', 'São Bernardo do Campo', 'João Pessoa', 'Santo André',
  'Osasco', 'Jaboatão dos Guararapes', 'Ribeirão Preto', 'Uberlândia', 'Sorocaba',
];

const List<String> _kCitiesIN = [
  'Mumbai', 'Delhi', 'Bangalore', 'Hyderabad', 'Ahmedabad',
  'Chennai', 'Kolkata', 'Surat', 'Pune', 'Jaipur',
  'Lucknow', 'Kanpur', 'Nagpur', 'Indore', 'Thane',
  'Bhopal', 'Visakhapatnam', 'Patna', 'Vadodara', 'Ghaziabad',
  'Ludhiana', 'Agra', 'Nashik', 'Faridabad', 'Meerut',
  'Rajkot', 'Kalyan-Dombivli', 'Vasai-Virar', 'Varanasi', 'Srinagar',
];

const List<String> _kCitiesAE = [
  'Dubai', 'Abu Dhabi', 'Sharjah', 'Al Ain', 'Ajman',
  'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain', 'Khor Fakkan', 'Dibba Al-Fujairah',
];

const List<String> _kCitiesEG = [
  'القاهرة', 'الإسكندرية', 'الجيزة', 'شبرا الخيمة', 'بورسعيد',
  'السويس', 'الأقصر', 'المنصورة', 'طنطا', 'أسيوط',
  'الإسماعيلية', 'الفيوم', 'الزقازيق', 'أسوان', 'دمياط',
  'المنيا', 'بني سويف', 'قنا', 'سوهاج', 'حلوان',
  'شرم الشيخ', 'الغردقة', 'مرسى مطروح', 'رأس غارب', '6 أكتوبر',
];

const List<String> _kCitiesJO = [
  'عمّان', 'الزرقاء', 'إربد', 'الرصيفة', 'العقبة',
  'السلط', 'المفرق', 'جرش', 'الطفيلة', 'الكرك',
  'مادبا', 'عجلون', 'معان', 'الرمثا',
];

const List<String> _kCitiesTR = [
  'İstanbul', 'Ankara', 'İzmir', 'Bursa', 'Adana',
  'Gaziantep', 'Konya', 'Antalya', 'Kayseri', 'Mersin',
  'Eskişehir', 'Diyarbakır', 'Samsun', 'Denizli', 'Şanlıurfa',
  'Adapazarı', 'Malatya', 'Kahramanmaraş', 'Erzurum', 'Van',
  'Batman', 'Elazığ', 'Tokat', 'Sivas', 'Trabzon',
];

const List<String> _kCitiesGR = [
  'Αθήνα', 'Θεσσαλονίκη', 'Πάτρα', 'Ηράκλειο', 'Λάρισα',
  'Βόλος', 'Ρόδος', 'Ιωάννινα', 'Χανιά', 'Χαλκίδα',
  'Αγρίνιο', 'Κατερίνη', 'Καλαμάτα', 'Σέρρες', 'Κέρκυρα',
  'Αλεξανδρούπολη', 'Ξάνθη', 'Τρίκαλα', 'Λαμία', 'Κομοτηνή',
];

const List<String> _kCitiesNL = [
  'Amsterdam', 'Rotterdam', 'Den Haag', 'Utrecht', 'Eindhoven',
  'Groningen', 'Tilburg', 'Almere', 'Breda', 'Nijmegen',
  'Apeldoorn', 'Haarlem', 'Arnhem', 'Enschede', 'Amersfoort',
  'Zaanstad', 'Den Bosch', 'Zwolle', 'Leeuwarden', 'Dordrecht',
];

const List<String> _kCitiesBE = [
  'Brussels', 'Antwerp', 'Ghent', 'Charleroi', 'Liège',
  'Bruges', 'Namur', 'Leuven', 'Mons', 'Mechelen',
  'Aalst', 'La Louvière', 'Kortrijk', 'Hasselt', 'Ostend',
];

const List<String> _kCitiesPL = [
  'Warszawa', 'Kraków', 'Łódź', 'Wrocław', 'Poznań',
  'Gdańsk', 'Szczecin', 'Bydgoszcz', 'Lublin', 'Białystok',
  'Katowice', 'Gdynia', 'Częstochowa', 'Radom', 'Sosnowiec',
  'Toruń', 'Kielce', 'Rzeszów', 'Gliwice', 'Zabrze',
];

const List<String> _kCitiesRO = [
  'București', 'Cluj-Napoca', 'Timișoara', 'Iași', 'Constanța',
  'Craiova', 'Brașov', 'Galați', 'Ploiești', 'Oradea',
  'Brăila', 'Arad', 'Pitești', 'Sibiu', 'Bacău',
  'Târgu Mureș', 'Baia Mare', 'Buzău', 'Botoșani', 'Satu Mare',
];

const List<String> _kCitiesMA = [
  'الدار البيضاء', 'الرباط', 'فاس', 'مراكش', 'طنجة',
  'أكادير', 'مكناس', 'وجدة', 'القنيطرة', 'تطوان',
  'آسفي', 'المحمدية', 'خريبكة', 'الجديدة', 'بني ملال',
  'تازة', 'الناظور', 'سطات', 'العرائش', 'خنيفرة',
];

const List<String> _kCitiesZA = [
  'Johannesburg', 'Cape Town', 'Durban', 'Pretoria', 'Port Elizabeth',
  'Bloemfontein', 'East London', 'Pietermaritzburg', 'Nelspruit', 'Kimberley',
  'Polokwane', 'Rustenburg', 'George', 'Welkom', 'Soweto',
];

const List<String> _kCitiesMX = [
  'Ciudad de México', 'Guadalajara', 'Monterrey', 'Puebla', 'Tijuana',
  'León', 'Juárez', 'Torreón', 'Querétaro', 'San Luis Potosí',
  'Mérida', 'Mexicali', 'Aguascalientes', 'Cuernavaca', 'Saltillo',
  'Culiacán', 'Hermosillo', 'Chihuahua', 'Morelia', 'Acapulco',
  'Cancún', 'Veracruz', 'Villahermosa', 'Oaxaca', 'Tuxtla Gutiérrez',
];

const List<String> _kCitiesAR = [
  'Buenos Aires', 'Córdoba', 'Rosario', 'Mendoza', 'La Plata',
  'San Miguel de Tucumán', 'Mar del Plata', 'Salta', 'Santa Fe', 'San Juan',
  'Resistencia', 'Neuquén', 'Santiago del Estero', 'Corrientes', 'Posadas',
  'Bahía Blanca', 'Paraná', 'Formosa', 'San Luis', 'La Rioja',
];

const List<String> _kCitiesCN = [
  '北京', '上海', '广州', '深圳', '天津',
  '武汉', '成都', '重庆', '南京', '杭州',
  '西安', '苏州', '青岛', '大连', '沈阳',
  '长沙', '济南', '哈尔滨', '长春', '厦门',
  '福州', '昆明', '南昌', '合肥', '郑州',
  '石家庄', '太原', '贵阳', '南宁', '乌鲁木齐',
];

const List<String> _kCitiesJP = [
  '東京', '横浜', '大阪', '名古屋', '札幌',
  '福岡', '神戸', '川崎', '京都', 'さいたま',
  '広島', '仙台', '北九州', '千葉', '新潟',
  '浜松', '静岡', '岡山', '熊本', '相模原',
  '鹿児島', '船橋', '八王子', '川口', '東大阪',
];

const List<String> _kCitiesKR = [
  '서울', '부산', '인천', '대구', '대전',
  '광주', '수원시', '울산', '고양시', '용인시',
  '성남시', '창원시', '청주시', '부천시', '남양주시',
  '화성시', '전주시', '안산시', '천안시', '안양시',
];

const List<String> _kCitiesTH = [
  'Bangkok', 'Nonthaburi', 'Nakhon Ratchasima', 'Chiang Mai', 'Hat Yai',
  'Udon Thani', 'Pak Kret', 'Khon Kaen', 'Chaophraya Surasak', 'Nakhon Si Thammarat',
  'Phuket', 'Pattaya', 'Ubon Ratchathani', 'Nakhon Sawan', 'Rayong',
];

const List<String> _kCitiesSG = [
  'Singapore',
];
