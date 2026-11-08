describe("StarterPackRules", function()
	local StarterPackRules = load("ReplicatedStorage/Shared/StarterPackRules")
	local StarterPackTable = load("ReplicatedStorage/Tables/StarterPackTable")
	local WINDOW = StarterPackTable.WindowSeconds
	local JOIN = 5000

	it("uses a 15 minute window", function()
		expect(WINDOW):equal(900)
	end)

	it("is live one second before the window ends and over exactly at 15:00", function()
		expect(StarterPackRules.IsLive(JOIN + WINDOW - 1, JOIN, false, WINDOW)):equal(true)
		expect(StarterPackRules.IsLive(JOIN + WINDOW, JOIN, false, WINDOW)):equal(false)
		expect(StarterPackRules.IsLive(JOIN + WINDOW + 1, JOIN, false, WINDOW)):equal(false)
	end)

	it("counts offline time: a rejoin after 20 minutes finds it gone", function()
		expect(StarterPackRules.IsLive(JOIN + 20 * 60, JOIN, false, WINDOW)):equal(false)
		expect(StarterPackRules.IsLive(JOIN + 10 * 60, JOIN, false, WINDOW)):equal(true)
	end)

	it("is never live once bought, or before data is ready", function()
		expect(StarterPackRules.IsLive(JOIN + 1, JOIN, true, WINDOW)):equal(false)
		expect(StarterPackRules.IsLive(JOIN + 1, 0, false, WINDOW)):equal(false)
	end)

	it("reports time left, clamped at zero", function()
		expect(StarterPackRules.SecondsLeft(JOIN + 100, JOIN, WINDOW)):equal(800)
		expect(StarterPackRules.SecondsLeft(JOIN + 5000, JOIN, WINDOW)):equal(0)
		expect(StarterPackRules.EndsAt(JOIN, WINDOW)):equal(JOIN + WINDOW)
	end)

	it("reminds from 2:00 left until the end", function()
		local reminder = StarterPackTable.ReminderSecondsLeft
		expect(StarterPackRules.ReminderDue(JOIN + WINDOW - reminder - 1, JOIN, WINDOW, reminder)):equal(false)
		expect(StarterPackRules.ReminderDue(JOIN + WINDOW - reminder, JOIN, WINDOW, reminder)):equal(true)
		expect(StarterPackRules.ReminderDue(JOIN + WINDOW, JOIN, WINDOW, reminder)):equal(false)
	end)
end)
