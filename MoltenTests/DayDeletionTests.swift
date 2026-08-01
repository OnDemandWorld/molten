//
//  DayDeletionTests.swift
//  MoltenTests
//
//  Regression coverage for audit findings F-01 + F-43:
//  "Delete daily conversations" must delete exactly the conversations in the
//  targeted calendar day — nothing more, nothing less — and must only clear
//  the open conversation when it was part of the deleted day.
//

import XCTest
import SwiftData
@testable import Molten

final class DayDeletionTests: XCTestCase {

    // MARK: - Service level: half-open day interval, fixed non-UTC calendar

    func testDeleteConversationsRemovesOnlyTargetCalendarDay() async throws {
        let service = SwiftDataService(inMemory: true)

        // Fixed UTC+14 calendar: catches off-by-one day bugs that a UTC or
        // machine-local calendar could hide, and makes boundaries deterministic.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!

        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        let previousDayLateNight = calendar.date(byAdding: .second, value: -1, to: day)!      // Mar 14 23:59:59
        let targetDayStart       = day                                                       // Mar 15 00:00:00
        let targetDayNoon        = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let targetDayLateNight   = calendar.date(byAdding: .second, value: -1, to: nextDay)! // Mar 15 23:59:59
        let nextDayStart         = nextDay                                                   // Mar 16 00:00:00

        try await service.createConversation(ConversationSD(name: "prev-day", updatedAt: previousDayLateNight))
        try await service.createConversation(ConversationSD(name: "target-start", updatedAt: targetDayStart))
        try await service.createConversation(ConversationSD(name: "target-noon", updatedAt: targetDayNoon))
        try await service.createConversation(ConversationSD(name: "target-end", updatedAt: targetDayLateNight))
        try await service.createConversation(ConversationSD(name: "next-day", updatedAt: nextDayStart))

        // The sidebar passes the group's startOfDay date.
        try await service.deleteConversations(day, calendar: calendar)

        let survivors = try await service.fetchConversations().map(\.name).sorted()
        XCTAssertEqual(survivors, ["next-day", "prev-day"],
                       "Only conversations whose updatedAt falls in [startOfDay, startOfNextDay) may be deleted")
    }

    func testDeleteConversationsIsPersisted() async throws {
        let service = SwiftDataService(inMemory: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!

        try await service.createConversation(ConversationSD(name: "doomed", updatedAt: day))
        try await service.createConversation(ConversationSD(
            name: "keeper",
            updatedAt: calendar.date(byAdding: .day, value: 1, to: day)!))

        try await service.deleteConversations(day, calendar: calendar)

        // A fresh context over the same container sees only saved state
        // (autosave is disabled), proving the delete was explicitly saved.
        let container = await service.modelContainer
        let verifier = ModelContext(container)
        let count = try verifier.fetchCount(FetchDescriptor<ConversationSD>())
        XCTAssertEqual(count, 1, "Day deletion must be persisted via saveChanges()")
    }

    // MARK: - Store level: Calendar.current semantics matching the sidebar UI

    @MainActor
    func testStoreDeleteDailyKeepsOtherDaysAndUnrelatedSelection() async throws {
        let service = SwiftDataService(inMemory: true)
        let store = ConversationStore(swiftDataService: service)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let yesterdayConversation = ConversationSD(name: "yesterday", updatedAt: yesterday.addingTimeInterval(3600))
        try await service.createConversation(yesterdayConversation)
        try await service.createConversation(ConversationSD(name: "today", updatedAt: today.addingTimeInterval(3600)))
        try await service.createConversation(ConversationSD(name: "tomorrow", updatedAt: tomorrow.addingTimeInterval(3600)))

        // Selection is on a conversation outside the deleted day — must be kept.
        store.selectedConversation = yesterdayConversation

        await store.deleteDailyConversations(today)

        let survivors = try await service.fetchConversations().map(\.name).sorted()
        XCTAssertEqual(survivors, ["tomorrow", "yesterday"])
        XCTAssertNotNil(store.selectedConversation,
                        "Selection outside the deleted day must not be cleared")
        XCTAssertEqual(store.selectedConversation?.name, "yesterday")
    }

    @MainActor
    func testStoreDeleteDailyClearsSelectionWhenSelectedConversationDeleted() async throws {
        let service = SwiftDataService(inMemory: true)
        let store = ConversationStore(swiftDataService: service)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        try await service.createConversation(ConversationSD(name: "today", updatedAt: today.addingTimeInterval(3600)))
        try await service.createConversation(ConversationSD(name: "tomorrow", updatedAt: tomorrow.addingTimeInterval(3600)))

        store.selectedConversation = try await service.fetchConversations().first { $0.name == "today" }
        XCTAssertNotNil(store.selectedConversation, "fixture precondition")
        store.messages = []

        await store.deleteDailyConversations(today)

        let survivors = try await service.fetchConversations().map(\.name)
        XCTAssertEqual(survivors, ["tomorrow"])
        XCTAssertNil(store.selectedConversation,
                     "Selection inside the deleted day must be cleared")
        XCTAssertTrue(store.messages.isEmpty)
    }

    // MARK: - DST transition days

    // Calendar arithmetic (date(byAdding: .day, value: 1)) must track
    // wall-clock days, so 23-hour and 25-hour transition days are deleted
    // as single calendar days.

    func testDeleteConversationsOnSpringForwardDay() async throws {
        let service = SwiftDataService(inMemory: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // 2026-03-08: US spring forward — a 23-hour wall-clock day.
        let dstDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: dstDay)!
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dstDay)!

        // Sanity: the transition day really is 23 hours long.
        XCTAssertEqual(nextMidnight.timeIntervalSince(dstDay), 23 * 3600)

        func at(_ date: Date, hour: Int, minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        }

        try await service.createConversation(ConversationSD(name: "before-day", updatedAt: at(dayBefore, hour: 23, minute: 30)))
        try await service.createConversation(ConversationSD(name: "dst-midnight", updatedAt: dstDay))
        try await service.createConversation(ConversationSD(name: "dst-noon", updatedAt: at(dstDay, hour: 12, minute: 0)))
        try await service.createConversation(ConversationSD(name: "dst-late-night", updatedAt: at(dstDay, hour: 23, minute: 30)))
        try await service.createConversation(ConversationSD(name: "next-day", updatedAt: nextMidnight))

        try await service.deleteConversations(dstDay, calendar: calendar)

        let survivors = try await service.fetchConversations().map(\.name).sorted()
        XCTAssertEqual(survivors, ["before-day", "next-day"],
                       "All of the 23-hour transition day must be deleted, and only that day")
    }

    func testDeleteConversationsOnFallBackDay() async throws {
        let service = SwiftDataService(inMemory: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // 2026-11-01: US fall back — a 25-hour wall-clock day.
        let dstDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dstDay)!

        // Sanity: the transition day really is 25 hours long.
        XCTAssertEqual(nextMidnight.timeIntervalSince(dstDay), 25 * 3600)

        // 24.5h after midnight is still 23:30 wall-clock on Nov 1 — inside the day.
        let lateInLongDay = dstDay.addingTimeInterval(24.5 * 3600)
        XCTAssertLessThan(lateInLongDay, nextMidnight)

        try await service.createConversation(ConversationSD(name: "long-day-late", updatedAt: lateInLongDay))
        try await service.createConversation(ConversationSD(name: "next-day", updatedAt: nextMidnight))

        try await service.deleteConversations(dstDay, calendar: calendar)

        let survivors = try await service.fetchConversations().map(\.name)
        XCTAssertEqual(survivors, ["next-day"],
                       "A conversation at 23:30 on the 25-hour day belongs to that day and must be deleted")
    }
}
