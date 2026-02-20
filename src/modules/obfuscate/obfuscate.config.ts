import { faker, fakerKO } from "@faker-js/faker";

export interface ColumnRule {
  generator: () => string | number | Date | null;
  nullFrequency?: number;
}

export interface TableConfig {
  primaryKey?: string | string[];
  columns: Record<string, ColumnRule>;
}

export type MaskingConfig = Record<string, TableConfig>;

export const maskingConfig: MaskingConfig = {
  member: {
    columns: {
      name_in_korean: {
        generator: () => fakerKO.person.fullName(),
      },
      name: {
        generator: () => faker.person.firstName() + ' ' + faker.person.lastName(),
        nullFrequency: 0.2,
      },
      dob: {
        generator: () =>
          faker.date.birthdate({ min: 18, max: 45, mode: "age" }),
        nullFrequency: 0.2,
      },
      phone_number: {
        generator: () => faker.phone.number({ style: "national" }),
        nullFrequency: 0.2,
      },
      email: {
        generator: () => faker.internet.email(),
        nullFrequency: 0.3,
      },
      address: {
        generator: () =>
          faker.location.streetAddress({ useFullAddress: true }),
        nullFrequency: 0.3,
      },
    }
  },
  group_meeting_record: {
    primaryKey: ["group_meeting_id", "member_id"],
    columns: {
      prayer_request: {
        generator: () => fakerKO.lorem.sentence(),
        nullFrequency: 0.4,
      }
    }
  },
  test_table: {
    primaryKey: "id",
    columns: {
      text_column: {
        generator: () => fakerKO.lorem.sentence(),
        nullFrequency: 0.1,
      }, 
      phone_number: {
        generator: () => faker.phone.number(),
      },
      name: {
        generator: () => fakerKO.person.fullName(),
      }
    }
  }
};

export const skipEmailMatchTables: string[] = ["member"];

export const OBFUSCATION_TIMEOUT_MS = 60_000;