export type SyntheticMockProfileDetails = {
  readonly displayName: string;
  readonly fullName: string;
  readonly nickname: string;
  readonly avatarInitials: string;
  readonly nicknameKey: string;
  readonly dateOfBirth: string;
  readonly ageYears: number;
  readonly weightKg: number;
  readonly fitnessLevel: string;
  readonly goals: readonly string[];
  readonly availability: {
    readonly weeklySessions: string;
    readonly preferredDays: readonly string[];
    readonly preferredTime: string;
    readonly sessionLengthMinutes: string;
  };
  readonly planCautiousness: string;
  readonly healthSafetyReadiness: {
    readonly comfort: "ready";
    readonly activitySymptoms: readonly ["none"];
    readonly recentRunningConsistency: string;
    readonly currentWeeklyRunFrequency: string;
    readonly continuousRunCapacity: string;
    readonly runningPlace: string;
    readonly motivationStyle: string;
  };
};

export function syntheticProfileDetails(
  userIndex: number,
): SyntheticMockProfileDetails {
  const firstName =
    syntheticFirstNames[userIndex % syntheticFirstNames.length] ?? "Avery";
  const lastName =
    syntheticLastNames[Math.floor(userIndex / syntheticFirstNames.length)] ??
    "Tan";
  const fullName = `${firstName} ${lastName}`;
  const birthYear = 1979 + Math.floor(userIndex / 4);
  const birthMonth = String((userIndex % 12) + 1).padStart(2, "0");
  const birthDay = String((userIndex % 28) + 1).padStart(2, "0");
  const ageYears = 2026 - birthYear - (birthMonth > "07" ? 1 : 0);
  const profileVariant = userIndex % 5;
  return {
    displayName: fullName,
    fullName,
    nickname: fullName,
    avatarInitials: `${firstName.slice(0, 1)}${lastName.slice(0, 1)}`,
    nicknameKey: `lbmock-${String(userIndex + 1).padStart(3, "0")}-${firstName.toLowerCase()}-${lastName.toLowerCase()}`,
    dateOfBirth: `${birthYear}-${birthMonth}-${birthDay}`,
    ageYears,
    weightKg: 48 + ((userIndex * 7) % 49) + 0.5,
    fitnessLevel: syntheticFitnessLevels[profileVariant] ?? "new",
    goals: [syntheticGoals[profileVariant] ?? "habit"],
    availability: {
      weeklySessions: String(2 + (userIndex % 3)),
      preferredDays: preferredDaysFor(userIndex),
      preferredTime:
        syntheticPreferredTimes[userIndex % syntheticPreferredTimes.length] ??
        "morning",
      sessionLengthMinutes:
        syntheticSessionLengths[userIndex % syntheticSessionLengths.length] ??
        "30",
    },
    planCautiousness:
      syntheticPlanCautiousness[userIndex % syntheticPlanCautiousness.length] ??
      "balanced",
    healthSafetyReadiness: {
      comfort: "ready",
      activitySymptoms: ["none"],
      recentRunningConsistency:
        syntheticConsistency[userIndex % syntheticConsistency.length] ?? "none",
      currentWeeklyRunFrequency:
        syntheticWeeklyFrequency[userIndex % syntheticWeeklyFrequency.length] ??
        "0",
      continuousRunCapacity:
        syntheticRunCapacity[userIndex % syntheticRunCapacity.length] ?? "walk",
      runningPlace:
        syntheticRunningPlaces[userIndex % syntheticRunningPlaces.length] ?? "park",
      motivationStyle:
        syntheticMotivationStyles[userIndex % syntheticMotivationStyles.length] ??
        "encourage",
    },
  };
}

function preferredDaysFor(userIndex: number): readonly string[] {
  const daySets = [
    ["Mon", "Thu"],
    ["Tue", "Fri"],
    ["Mon", "Wed", "Sat"],
    ["Tue", "Thu", "Sun"],
    ["Mon", "Wed", "Fri", "Sun"],
  ] as const;
  return daySets[userIndex % daySets.length] ?? daySets[0] ?? [];
}

const syntheticFirstNames = [
  "Avery",
  "Kai",
  "Mei",
  "Noah",
  "Priya",
  "Rafi",
  "Sofia",
  "Theo",
  "Uma",
  "Zara",
] as const;

const syntheticLastNames = [
  "Tan",
  "Lim",
  "Koh",
  "Lee",
  "Ng",
  "Ong",
  "Goh",
  "Yeo",
  "Chua",
  "Low",
] as const;

const syntheticFitnessLevels = [
  "new",
  "walk",
  "intervals",
  "run10",
  "run30",
] as const;
const syntheticGoals = ["habit", "gentle", "5k", "10k", "stamina"] as const;
const syntheticPreferredTimes = [
  "morning",
  "afternoon",
  "evening",
  "night",
  "flexible",
] as const;
const syntheticSessionLengths = ["15", "20", "30", "45", "unsure"] as const;
const syntheticPlanCautiousness = [
  "verygentle",
  "balanced",
  "standard",
] as const;
const syntheticConsistency = [
  "none",
  "under4",
  "1-3m",
  "3-6m",
  "6plus",
] as const;
const syntheticWeeklyFrequency = ["0", "1-2", "3", "4", "5plus"] as const;
const syntheticRunCapacity = [
  "walk",
  "runwalk",
  "10min",
  "20-30min",
  "45plus",
] as const;
const syntheticRunningPlaces = [
  "park",
  "road",
  "track",
  "treadmill",
  "mixed",
] as const;
const syntheticMotivationStyles = [
  "reminders",
  "plan",
  "encourage",
  "challenge",
  "expert",
] as const;
