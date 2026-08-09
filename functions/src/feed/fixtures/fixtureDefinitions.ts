export type SyntheticFeedIdentityRole = "author" | "accepted_friend" | "non_friend";
export type SyntheticFeedIdentity = {
  readonly uid: string;
  readonly role: SyntheticFeedIdentityRole;
  readonly displayName: string;
  readonly avatarInitials: string;
  readonly email: string;
};
export type SyntheticFriendship = { readonly ownerUid: string; readonly friendUid: string };

const author: SyntheticFeedIdentity = { uid: "feed-fixture-author", role: "author", displayName: "Feed Fixture Author", avatarInitials: "FA", email: "feed-author@fixture.invalid" };
const acceptedFriend: SyntheticFeedIdentity = { uid: "feed-fixture-friend", role: "accepted_friend", displayName: "Feed Fixture Friend", avatarInitials: "FF", email: "feed-friend@fixture.invalid" };
const nonFriend: SyntheticFeedIdentity = { uid: "feed-fixture-non-friend", role: "non_friend", displayName: "Feed Fixture Non-Friend", avatarInitials: "FN", email: "feed-non-friend@fixture.invalid" };

export const syntheticFeedFixture = {
  author,
  acceptedFriend,
  nonFriend,
  identities: [author, acceptedFriend, nonFriend],
} as const;

export function reciprocalFriendships(leftUid: string, rightUid: string): readonly [SyntheticFriendship, SyntheticFriendship] {
  return [{ ownerUid: leftUid, friendUid: rightUid }, { ownerUid: rightUid, friendUid: leftUid }];
}
