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
}
