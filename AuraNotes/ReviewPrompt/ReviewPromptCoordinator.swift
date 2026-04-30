//
//  ReviewPromptCoordinator.swift
//  AuraNotes
//

import Foundation
import StoreKit
import SwiftUI

/// Tracks engagement signals and asks the system to surface the App Store
/// review prompt at well-chosen moments. macOS itself caps the prompt at
/// ~3 per 365 days per user, so calling `requestReview` more often is safe;
/// our job here is to make every attempt land at a moment of momentum.
///
/// Policy (v1.0, **front-loaded** — try hard in the first 2 weeks):
///
/// Ordered milestones, each fires at most once. On every signal we walk
/// the list and fire the first eligible-but-unattempted milestone.
///
///   1. `secondEntry`  — user just created their 2nd entry
///   2. `day3`         — ≥ 3 calendar days since first launch
///   3. `day7`         — ≥ 7 days
///   4. `day10`        — ≥ 10 days
///   5. `day14`        — ≥ 14 days (last shot inside the launch window)
///
/// After day 14 we stop unless the app version changes or 120 days pass —
/// then the milestone log resets and the cycle can repeat.
///
/// Hard rules:
///   • At most one attempt per launch session.
///   • macOS still throttles to its own quota — that's fine, our extra
///     attempts are cheap and only fire on genuine activity.
@MainActor
final class ReviewPromptCoordinator {
    static let shared = ReviewPromptCoordinator()

    // MARK: - Milestones

    private enum Milestone: String, CaseIterable {
        case secondEntry
        case day3
        case day7
        case day10
        case day14
    }

    // MARK: - UserDefaults keys

    private enum Key {
        static let firstLaunchDate     = "review.firstLaunchDate"
        static let entriesCreated      = "review.entriesCreated"
        static let attemptedMilestones = "review.attemptedMilestones"
        static let lastPromptedVersion = "review.lastPromptedVersion"
        static let lastPromptDate      = "review.lastPromptDate"
    }

    private let resetAfterDays = 120.0

    private var didPromptThisSession = false
    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Signals

    /// Call once per cold launch. Records install date and gives the
    /// coordinator a chance to fire a calendar-based milestone.
    func recordSessionStart(using requestReview: RequestReviewAction) {
        if defaults.object(forKey: Key.firstLaunchDate) == nil {
            defaults.set(Date.now, forKey: Key.firstLaunchDate)
        }
        resetIfStale()
        evaluate(using: requestReview)
    }

    func recordEntryCreated(using requestReview: RequestReviewAction) {
        defaults.set(defaults.integer(forKey: Key.entriesCreated) + 1,
                     forKey: Key.entriesCreated)
        evaluate(using: requestReview)
    }

    /// Extra opportunity hooks — neither is required to fire a milestone,
    /// but if one happens to coincide with an unfired calendar milestone,
    /// it's a nice positive moment to attach the prompt to.
    func recordMeaningfulEdit(using requestReview: RequestReviewAction) {
        evaluate(using: requestReview)
    }

    func recordWritingToolsAccepted(using requestReview: RequestReviewAction) {
        evaluate(using: requestReview)
    }

    // MARK: - Decision

    private func evaluate(using requestReview: RequestReviewAction) {
        if didPromptThisSession { return }
        guard let milestone = nextEligibleMilestone() else { return }

        markAttempted(milestone)
        didPromptThisSession = true

        // Small delay so the prompt doesn't collide with the action that
        // just fired (sheet animations, Writing Tools fade-out, etc).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            requestReview()
        }
    }

    private func nextEligibleMilestone() -> Milestone? {
        let attempted = attemptedSet()
        let entries = defaults.integer(forKey: Key.entriesCreated)
        let days = daysSinceInstall()

        for m in Milestone.allCases where !attempted.contains(m.rawValue) {
            switch m {
            case .secondEntry: if entries >= 2 { return m }
            case .day3:        if days >= 3    { return m }
            case .day7:        if days >= 7    { return m }
            case .day10:       if days >= 10   { return m }
            case .day14:       if days >= 14   { return m }
            }
        }
        return nil
    }

    private func markAttempted(_ milestone: Milestone) {
        var set = attemptedSet()
        set.insert(milestone.rawValue)
        defaults.set(Array(set), forKey: Key.attemptedMilestones)
        defaults.set(currentAppVersion(), forKey: Key.lastPromptedVersion)
        defaults.set(Date.now, forKey: Key.lastPromptDate)
    }

    /// Reset the milestone log if either a new app version shipped or
    /// `resetAfterDays` have elapsed since the last attempt — that lets
    /// the cycle repeat for long-time users on a major update.
    private func resetIfStale() {
        let current = currentAppVersion()
        let lastVersion = defaults.string(forKey: Key.lastPromptedVersion)
        let lastDate = defaults.object(forKey: Key.lastPromptDate) as? Date

        let versionChanged = lastVersion != nil && lastVersion != current
        let longGap: Bool = {
            guard let d = lastDate else { return false }
            return Date.now.timeIntervalSince(d) / 86_400 >= resetAfterDays
        }()

        if versionChanged || longGap {
            defaults.removeObject(forKey: Key.attemptedMilestones)
        }
    }

    // MARK: - Helpers

    private func attemptedSet() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.attemptedMilestones) ?? [])
    }

    private func daysSinceInstall() -> Double {
        guard let first = defaults.object(forKey: Key.firstLaunchDate) as? Date else {
            return 0
        }
        return Date.now.timeIntervalSince(first) / 86_400
    }

    private func currentAppVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
