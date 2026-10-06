import Testing
import Foundation
@testable import MeToDoCore

@Suite struct QuickAddTests {
    let inbox = AppData.fresh().projects[0]
    let sprint = Project(name: "Sprint", color: .yellow, emoji: "🚀")
    let spring = Project(name: "Spring cleaning", color: .green)
    let work = Project(name: "Work", color: .green)
    let workshop = Project(name: "Workshop", color: .blue)
    let ingles = Project(name: "Inglés", color: .purple, emoji: "🎓")
    var all: [Project] { [inbox, sprint, work, workshop, ingles] }

    @Test func projectAndDateAreExtracted() throws {
        let r = try #require(QuickAdd.parse("Call Ana #sprint tomorrow 9am", projects: all))
        #expect(r.title == "Call Ana")
        #expect(r.projectID == sprint.id)
        #expect(r.remindAt == Queries.at(hour: 9, daysFromNow: 1, now: Date()))
    }

    @Test func uniquePrefixMatches() {
        #expect(QuickAdd.parse("Plan #spr", projects: all)?.projectID == sprint.id)
    }

    @Test func ambiguousPrefixStaysInTitle() {
        let r = QuickAdd.parse("Plan #spr", projects: all + [spring])
        #expect(r?.projectID == nil)
        #expect(r?.title == "Plan #spr")
    }

    @Test func exactMatchBeatsPrefix() {
        #expect(QuickAdd.parse("Fix #work", projects: all)?.projectID == work.id)
    }

    @Test func accentsCaseAndEmojiAreIgnored() {
        #expect(QuickAdd.parse("Homework #INGLES", projects: all)?.projectID == ingles.id)
        #expect(QuickAdd.normalize("🎓 Inglés B1") == "inglesb1")
    }

    @Test func spacesInProjectNamesAreIgnored() {
        #expect(QuickAdd.parse("Mop #springcleaning", projects: all + [spring])?.projectID == spring.id)
    }

    @Test func unknownTagStaysInTitle() {
        let r = QuickAdd.parse("Buy milk #nope", projects: all)
        #expect(r?.title == "Buy milk #nope")
        #expect(r?.projectID == nil)
    }

    @Test func dateWithoutTimeDefaultsToNine() throws {
        let r = try #require(QuickAdd.parse("Pay rent friday", projects: all))
        #expect(r.title == "Pay rent")
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: try #require(r.remindAt))
        #expect(c.weekday == 6)
        #expect(c.hour == 9)
        #expect(c.minute == 0)
    }

    @Test func trailingPrepositionIsDropped() throws {
        let r = try #require(QuickAdd.parse("Call Ana at 3pm", projects: all))
        #expect(r.title == "Call Ana")
        #expect(Calendar.current.component(.hour, from: try #require(r.remindAt)) == 15)
    }

    @Test func bareHourAfterAtIsATime() throws {
        let r = try #require(QuickAdd.parse("Call Ana tomorrow at 3", projects: all))
        #expect(r.title == "Call Ana")
        #expect(Calendar.current.component(.hour, from: try #require(r.remindAt)) != 9)
    }

    @Test func timeOnlyInThePastRollsToTomorrow() throws {
        let r = try #require(QuickAdd.parse("Call mom at 12:01am", projects: all))
        #expect(try #require(r.remindAt) > Date())
    }

    @Test func relativeTimeKeepsDetectedTime() throws {
        let r = try #require(QuickAdd.parse("Stretch in 2 hours", projects: all))
        #expect(r.title == "Stretch")
        let delta = try #require(r.remindAt).timeIntervalSinceNow
        #expect(abs(delta - 7200) < 120)
    }

    @Test(arguments: ["   ", "#sprint", "tomorrow 9am", "#sprint tomorrow"])
    func emptyTitlesCreateNothing(_ input: String) {
        #expect(QuickAdd.parse(input, projects: all) == nil)
    }

    @Test(arguments: [
        "Crear la presentación para entrega el 14",
        "Crear presentación para clase de inglés (octubre 14)",
        "Poner a funcionar AWS",
        "Subir 3 archivos",
        "Revisar sprint 42",
        "Call 911 contacts",
    ])
    func strayNumbersAreNotDates(_ input: String) {
        let r = QuickAdd.parse(input, projects: all)
        #expect(r?.remindAt == nil)
        #expect(r?.title == input)
    }
}
