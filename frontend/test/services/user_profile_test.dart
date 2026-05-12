import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/user_profile_service.dart';

/// Locks in the JSON round-trip for `UserProfile` + `UserInterest`. The
/// shapes have to match the backend's `UserProfilePayload` and
/// `InterestPayload` exactly — if a key drifts on either side, real users'
/// preferences silently round-trip to empty. These tests are the
/// fastest way to catch that.
void main() {
  group('UserInterest JSON round-trip', () {
    test('decodes minimum payload (label only)', () {
      final interest = UserInterest.fromJson({'label': 'small wineries'});
      expect(interest.label, 'small wineries');
      expect(interest.mapboxCategories, isEmpty);
      expect(interest.keywords, isEmpty);
    });

    test('decodes full payload', () {
      final interest = UserInterest.fromJson({
        'label': 'lakes to fish',
        'mapbox_categories': ['lake', 'marina'],
        'keywords': ['fishing', 'boat launch'],
      });
      expect(interest.label, 'lakes to fish');
      expect(interest.mapboxCategories, ['lake', 'marina']);
      expect(interest.keywords, ['fishing', 'boat launch']);
    });

    test('toJson preserves all fields', () {
      const interest = UserInterest(
        label: 'card shops',
        mapboxCategories: ['hobby_shop', 'gift_shop'],
        keywords: ['card', 'gaming'],
      );
      expect(interest.toJson(), {
        'label': 'card shops',
        'mapbox_categories': ['hobby_shop', 'gift_shop'],
        'keywords': ['card', 'gaming'],
      });
    });

    test('round-trip is identity for the same shape', () {
      const original = UserInterest(
        label: 'scenic overlooks',
        mapboxCategories: ['scenic'],
        keywords: ['view', 'overlook'],
      );
      final round = UserInterest.fromJson(original.toJson());
      expect(round.label, original.label);
      expect(round.mapboxCategories, original.mapboxCategories);
      expect(round.keywords, original.keywords);
    });

    test('missing list fields default to empty (not null)', () {
      // Backend may omit these fields entirely on a freshly-saved
      // free-text interest pending LLM normalization.
      final interest = UserInterest.fromJson({
        'label': 'whatever the user typed',
        'mapbox_categories': null,
        'keywords': null,
      });
      expect(interest.mapboxCategories, isEmpty);
      expect(interest.keywords, isEmpty);
    });
  });

  group('UserProfile JSON round-trip', () {
    test('decodes a fully-populated profile including interests', () {
      final profile = UserProfile.fromJson({
        'preferred_poi_types': ['restaurant', 'park'],
        'default_time_budget_minutes': 60,
        'dietary_restrictions': ['vegetarian'],
        'interests': [
          {
            'label': 'wineries',
            'mapbox_categories': ['winery'],
            'keywords': [],
          },
          {
            'label': 'state parks',
            'mapbox_categories': ['state_park'],
            'keywords': ['state park'],
          },
        ],
        'recommendations_enabled': true,
        'recommendations_max_per_trip': 5,
        'recommendations_min_gap_minutes': 20,
      });
      expect(profile.preferredPoiTypes, ['restaurant', 'park']);
      expect(profile.defaultTimeBudgetMinutes, 60);
      expect(profile.dietaryRestrictions, ['vegetarian']);
      expect(profile.interests, hasLength(2));
      expect(profile.interests[0].label, 'wineries');
      expect(profile.interests[1].mapboxCategories, ['state_park']);
      expect(profile.recommendationsEnabled, isTrue);
      expect(profile.recommendationsMaxPerTrip, 5);
      expect(profile.recommendationsMinGapMinutes, 20);
    });

    test('decodes a minimum (empty) profile with sensible defaults', () {
      final profile = UserProfile.fromJson({});
      expect(profile.preferredPoiTypes, isEmpty);
      expect(profile.defaultTimeBudgetMinutes, isNull);
      expect(profile.dietaryRestrictions, isEmpty);
      expect(profile.interests, isEmpty);
      expect(profile.recommendationsEnabled, isTrue);
      expect(profile.recommendationsMaxPerTrip, 3);
      expect(profile.recommendationsMinGapMinutes, 15);
    });

    test('toJson includes interests as a list of maps', () {
      const profile = UserProfile(
        preferredPoiTypes: ['coffee'],
        interests: [
          UserInterest(
            label: 'specialty roasters',
            mapboxCategories: ['cafe'],
          ),
        ],
      );
      final json = profile.toJson();
      expect(json['interests'], [
        {
          'label': 'specialty roasters',
          'mapbox_categories': ['cafe'],
          'keywords': <String>[],
        }
      ]);
    });

    test('copyWith preserves interests when not overridden', () {
      const original = UserProfile(
        preferredPoiTypes: ['park'],
        interests: [UserInterest(label: 'scenic')],
      );
      final updated = original.copyWith(preferredPoiTypes: ['restaurant']);
      expect(updated.preferredPoiTypes, ['restaurant']);
      expect(updated.interests, hasLength(1));
      expect(updated.interests.first.label, 'scenic');
    });

    test('copyWith replaces interests when supplied', () {
      const original = UserProfile(
        interests: [UserInterest(label: 'scenic')],
      );
      final updated = original.copyWith(interests: const []);
      expect(updated.interests, isEmpty);
    });
  });
}
