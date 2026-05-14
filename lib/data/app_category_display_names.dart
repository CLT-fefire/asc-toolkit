/// ASC `appCategories` enum id → 한국어 표시명 매핑.
/// 매핑이 없으면 id 그대로 반환 (Apple이 새 카테고리를 추가하면 fallback 동작).
///
/// 출처: App Store Connect 한국어 UI 기준.
const Map<String, String> _categoryDisplayNamesKo = {
  // ---- Top-level ----
  'BOOKS': '도서',
  'BUSINESS': '비즈니스',
  'DEVELOPER_TOOLS': '개발자 도구',
  'EDUCATION': '교육',
  'ENTERTAINMENT': '엔터테인먼트',
  'FINANCE': '금융',
  'FOOD_AND_DRINK': '음식 및 음료',
  'GAMES': '게임',
  'GRAPHICS_AND_DESIGN': '그래픽 및 디자인',
  'HEALTH_AND_FITNESS': '건강 및 피트니스',
  'KIDS': '키즈',
  'LIFESTYLE': '라이프스타일',
  'MAGAZINES_AND_NEWSPAPERS': '매거진 및 신문',
  'MEDICAL': '의료',
  'MUSIC': '음악',
  'NAVIGATION': '내비게이션',
  'NEWS': '뉴스',
  'PHOTO_AND_VIDEO': '사진 및 비디오',
  'PRODUCTIVITY': '생산성',
  'REFERENCE': '참고',
  'SHOPPING': '쇼핑',
  'SOCIAL_NETWORKING': '소셜 네트워킹',
  'SPORTS': '스포츠',
  'STICKERS': '스티커',
  'TRAVEL': '여행',
  'UTILITIES': '유틸리티',
  'WEATHER': '날씨',

  // ---- Games subcategories ----
  'GAMES_ACTION': '게임 / 액션',
  'GAMES_ADVENTURE': '게임 / 어드벤처',
  'GAMES_BOARD': '게임 / 보드',
  'GAMES_CARD': '게임 / 카드',
  'GAMES_CASINO': '게임 / 카지노',
  'GAMES_CASUAL': '게임 / 캐주얼',
  'GAMES_FAMILY': '게임 / 가족',
  'GAMES_MUSIC': '게임 / 음악',
  'GAMES_PUZZLE': '게임 / 퍼즐',
  'GAMES_RACING': '게임 / 레이싱',
  'GAMES_ROLE_PLAYING': '게임 / 롤플레잉',
  'GAMES_SIMULATION': '게임 / 시뮬레이션',
  'GAMES_SPORTS': '게임 / 스포츠',
  'GAMES_STRATEGY': '게임 / 전략',
  'GAMES_TRIVIA': '게임 / 트리비아',
  'GAMES_WORD': '게임 / 단어',

  // ---- Kids subcategories ----
  'KIDS_FIVE_AND_UNDER': '키즈 / 5세 이하',
  'KIDS_SIX_TO_EIGHT': '키즈 / 6-8세',
  'KIDS_NINE_TO_ELEVEN': '키즈 / 9-11세',

  // ---- Stickers subcategories ----
  'STICKERS_PLACES_AND_OBJECTS': '스티커 / 장소 및 사물',
  'STICKERS_EMOJI_AND_EXPRESSIONS': '스티커 / 이모지 및 표현',
  'STICKERS_CELEBRATIONS': '스티커 / 기념 및 축하',
  'STICKERS_CELEBRITIES': '스티커 / 유명인',
  'STICKERS_MOVIES_AND_TV': '스티커 / 영화 및 TV',
  'STICKERS_MUSIC': '스티커 / 음악',
  'STICKERS_SPORTS_AND_ACTIVITIES': '스티커 / 스포츠 및 활동',
  'STICKERS_EATING_AND_DRINKING': '스티커 / 식사 및 음료',
  'STICKERS_CHARACTERS': '스티커 / 캐릭터',
  'STICKERS_ANIMALS': '스티커 / 동물',
  'STICKERS_FASHION': '스티커 / 패션',
  'STICKERS_ART': '스티커 / 예술',
  'STICKERS_KIDS_AND_FAMILY': '스티커 / 어린이 및 가족',
  'STICKERS_PEOPLE': '스티커 / 사람',
  'STICKERS_OTHER': '스티커 / 기타',
};

/// 카테고리 id의 한국어 표시명. 매핑 없으면 id 그대로.
/// UI에는 보통 `"한국어 (ID)"` 형태로 노출해서 식별성 ↑.
String categoryDisplayName(String id) =>
    _categoryDisplayNamesKo[id] ?? id;

/// "한국어 (ID)" 형태로 노출. 디버깅·식별 친화.
String categoryLabel(String id) {
  final name = _categoryDisplayNamesKo[id];
  if (name == null) return id;
  return '$name ($id)';
}
