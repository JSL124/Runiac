import { applySyntheticFeedFixture } from "./fixtureLibrary.js";
import { runFeedFixtureScenario } from "./emulatorFixtures.js";

const scenario = readScenario(process.argv.slice(2));
const result = await runFeedFixtureScenario({ environment: process.env, scenario, mutate: applySyntheticFeedFixture });
if (!result.ok) process.exitCode = 1;

function readScenario(argumentsList: readonly string[]): string {
  const index = argumentsList.indexOf("--scenario");
  return index >= 0 ? argumentsList[index + 1] ?? "" : "";
}
