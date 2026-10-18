import { describe, expect, test } from "vitest";
import { END_LENGTH, pickTopics, pointsFor, SUBJECT_LENGTH, TOPIC_CATALOGS, validateOwnTopic } from "./consensio";

describe("topic catalogs", () => {
  for (const [language, catalog] of Object.entries(TOPIC_CATALOGS)) {
    test(`${language} has 150 well-formed topics`, () => {
      expect(catalog.language).toBe(language);
      expect(catalog.topics).toHaveLength(150);
      expect(new Set(catalog.topics.map((topic) => topic.id)).size).toBe(150);
      expect(new Set(catalog.topics.map((topic) => topic.subject.toLowerCase())).size).toBe(150);
      for (const topic of catalog.topics) {
        expect(topic.id).toMatch(/^[a-z0-9]+(_[a-z0-9]+)*$/);
        expect(validateOwnTopic(topic.subject, topic.left, topic.right), topic.id).toBeNull();
        expect(topic.subject.length).toBeLessThanOrEqual(SUBJECT_LENGTH.max);
        expect(Math.max(topic.left.length, topic.right.length)).toBeLessThanOrEqual(END_LENGTH.max);
        expect(topic.subject, topic.id).not.toMatch(/\?/);
      }
    });
  }

  test("no topic speaks as the partner", () => {
    const firstPerson = { en: /\b(i|me|my|mine|we|us|our|ours)\b/i, nb: /\b(jeg|meg|min|mitt|mine|vi|oss|vår|vårt|våre)\b/i };
    for (const [language, catalog] of Object.entries(TOPIC_CATALOGS) as [keyof typeof firstPerson, (typeof TOPIC_CATALOGS)["en"]][]) {
      for (const topic of catalog.topics) {
        expect(`${topic.subject} | ${topic.left} | ${topic.right}`, topic.id).not.toMatch(firstPerson[language]);
      }
    }
  });
});

describe("pickTopics", () => {
  test("offers three unused topics, and starts over when fewer than three are left", () => {
    const all = TOPIC_CATALOGS.en.topics.map((topic) => topic.id);
    const fresh = pickTopics("en", new Set(all.slice(0, 140)));
    expect(fresh.reset).toBe(false);
    expect(fresh.choices.every((choice) => all.slice(140).includes(choice.topic_id))).toBe(true);
    expect(pickTopics("en", new Set(all.slice(0, 148))).reset).toBe(true);
  });
});

test("pointsFor", () => {
  expect([0, 3, 4, 7, 8, 11, 12, 15, 16, 19, 20, 100].map(pointsFor)).toEqual([5, 5, 4, 4, 3, 3, 2, 2, 1, 1, 0, 0]);
});
