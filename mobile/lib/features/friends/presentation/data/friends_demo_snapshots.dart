import '../../domain/models/friends_read_model.dart';

// Display-only demo snapshots. In production, friend relationships, request
// state, and level labels must come from backend-owned read models; the
// client never derives levels, XP, rank, or streak values and never writes
// users/{uid}/friends.
const List<FriendUserReadModel> friendsDemoFriends = [
  FriendUserReadModel(
    userId: 'friend-aisha-rahman',
    displayName: 'Aisha Rahman',
    avatarInitials: 'AR',
    levelLabel: 'Lv.12',
    subtitleLabel: 'Runs around Bishan Park',
  ),
  FriendUserReadModel(
    userId: 'friend-marcus-tan',
    displayName: 'Marcus Tan',
    avatarInitials: 'MT',
    levelLabel: 'Lv.9',
    subtitleLabel: 'Weekend East Coast regular',
  ),
  FriendUserReadModel(
    userId: 'friend-priya-nair',
    displayName: 'Priya Nair',
    avatarInitials: 'PN',
    levelLabel: 'Lv.15',
    subtitleLabel: 'Morning miles before work',
  ),
  FriendUserReadModel(
    userId: 'friend-daniel-lim',
    displayName: 'Daniel Lim',
    avatarInitials: 'DL',
    levelLabel: 'Lv.7',
    subtitleLabel: 'Building a steady habit',
  ),
  FriendUserReadModel(
    userId: 'friend-hannah-lee',
    displayName: 'Hannah Lee',
    avatarInitials: 'HL',
    levelLabel: 'Lv.11',
    subtitleLabel: 'Loves Punggol Waterway',
  ),
  FriendUserReadModel(
    userId: 'friend-wei-jie-ng',
    displayName: 'Wei Jie Ng',
    avatarInitials: 'WN',
    levelLabel: 'Lv.5',
    subtitleLabel: 'New to evening runs',
  ),
];

const List<FriendUserReadModel> friendsDemoRecommended = [
  FriendUserReadModel(
    userId: 'suggested-clara-goh',
    displayName: 'Clara Goh',
    avatarInitials: 'CG',
    levelLabel: 'Lv.8',
    subtitleLabel: 'Runs a similar weekly plan',
  ),
  FriendUserReadModel(
    userId: 'suggested-ryan-chua',
    displayName: 'Ryan Chua',
    avatarInitials: 'RC',
    levelLabel: 'Lv.10',
    subtitleLabel: 'Often nearby in Jurong East',
  ),
  FriendUserReadModel(
    userId: 'suggested-mei-ling-ho',
    displayName: 'Mei Ling Ho',
    avatarInitials: 'MH',
    levelLabel: 'Lv.6',
    subtitleLabel: 'Also training for a first 5K',
  ),
  FriendUserReadModel(
    userId: 'suggested-arjun-pillai',
    displayName: 'Arjun Pillai',
    avatarInitials: 'AP',
    levelLabel: 'Lv.13',
    subtitleLabel: 'Enjoys park connector loops',
  ),
  FriendUserReadModel(
    userId: 'suggested-sofia-lim',
    displayName: 'Sofia Lim',
    avatarInitials: 'SL',
    levelLabel: 'Lv.4',
    subtitleLabel: 'Beginner-friendly pace group',
  ),
];

const List<FriendUserReadModel> friendsDemoIncomingRequests = [
  FriendUserReadModel(
    userId: 'request-jasmine-koh',
    displayName: 'Jasmine Koh',
    avatarInitials: 'JK',
    levelLabel: 'Lv.9',
    subtitleLabel: 'Wants to run together',
  ),
  FriendUserReadModel(
    userId: 'request-benjamin-ong',
    displayName: 'Benjamin Ong',
    avatarInitials: 'BO',
    levelLabel: 'Lv.3',
    subtitleLabel: 'Just started their journey',
  ),
  FriendUserReadModel(
    userId: 'request-nadia-hassan',
    displayName: 'Nadia Hassan',
    avatarInitials: 'NH',
    levelLabel: 'Lv.14',
    subtitleLabel: 'Met at a community run',
  ),
];

const List<FriendUserReadModel> friendsDemoSearchableUsers = [
  FriendUserReadModel(
    userId: 'search-alex-wong',
    displayName: 'Alex Wong',
    avatarInitials: 'AW',
    levelLabel: 'Lv.6',
    subtitleLabel: 'Runs in Tampines',
  ),
  FriendUserReadModel(
    userId: 'search-grace-teo',
    displayName: 'Grace Teo',
    avatarInitials: 'GT',
    levelLabel: 'Lv.11',
    subtitleLabel: 'MacRitchie trail fan',
  ),
  FriendUserReadModel(
    userId: 'search-samuel-chen',
    displayName: 'Samuel Chen',
    avatarInitials: 'SC',
    levelLabel: 'Lv.8',
    subtitleLabel: 'Lunchtime city runner',
  ),
  FriendUserReadModel(
    userId: 'search-farah-ismail',
    displayName: 'Farah Ismail',
    avatarInitials: 'FI',
    levelLabel: 'Lv.5',
    subtitleLabel: 'Enjoys gentle long walks',
  ),
  FriendUserReadModel(
    userId: 'search-lucas-yeo',
    displayName: 'Lucas Yeo',
    avatarInitials: 'LY',
    levelLabel: 'Lv.16',
    subtitleLabel: 'Marathon hopeful',
  ),
  FriendUserReadModel(
    userId: 'search-chloe-ang',
    displayName: 'Chloe Ang',
    avatarInitials: 'CA',
    levelLabel: 'Lv.7',
    subtitleLabel: 'Sunset runs at Marina Bay',
  ),
  FriendUserReadModel(
    userId: 'search-imran-shah',
    displayName: 'Imran Shah',
    avatarInitials: 'IS',
    levelLabel: 'Lv.10',
    subtitleLabel: 'Track intervals on Tuesdays',
  ),
  FriendUserReadModel(
    userId: 'search-vanessa-loh',
    displayName: 'Vanessa Loh',
    avatarInitials: 'VL',
    levelLabel: 'Lv.2',
    subtitleLabel: 'First month of running',
  ),
  FriendUserReadModel(
    userId: 'search-kai-wen-toh',
    displayName: 'Kai Wen Toh',
    avatarInitials: 'KT',
    levelLabel: 'Lv.12',
    subtitleLabel: 'Sengkang riverside loops',
  ),
  FriendUserReadModel(
    userId: 'search-olivia-fernandez',
    displayName: 'Olivia Fernandez',
    avatarInitials: 'OF',
    levelLabel: 'Lv.9',
    subtitleLabel: 'Runs with a jogging stroller',
  ),
];

const FriendsOverviewReadModel friendsOverviewDemoSnapshot =
    FriendsOverviewReadModel(
      friends: friendsDemoFriends,
      recommended: friendsDemoRecommended,
      incomingRequests: friendsDemoIncomingRequests,
      searchableUsers: friendsDemoSearchableUsers,
    );
